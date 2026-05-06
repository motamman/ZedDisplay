import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:uuid/uuid.dart';

import 'auth_service.dart';
import 'storage_service.dart';

/// Bearer-token store for the weather route-planner API.
///
/// Persists the token via [StorageService] (unencrypted Hive, matching
/// SignalK tokens) and notifies listeners so any UI bound to it can
/// re-render. The Google sign-in flow lives on this service as
/// [signInWithGoogle] — it opens the router's `/auth/google/login-mobile`
/// endpoint in a system Custom Tab / `ASWebAuthenticationSession`,
/// which Google permits (an embedded WebView is blocked by their "Use
/// secure browsers" policy with a 403 `disallowed_useragent`). After
/// the user signs in, the router mints a fresh API key and redirects
/// to `zeddisplay://auth-callback?token=…`; the OS catches the deep
/// link and `flutter_web_auth_2` returns the URL to us. We extract the
/// token, persist it via [setBearerToken], and the configurator UI
/// auto-syncs through [notifyListeners].
class RoutePlannerAuthService extends ChangeNotifier {
  RoutePlannerAuthService(this._storage) {
    _cached = _storage.getSetting(_tokenKey);
  }

  static const String _tokenKey = 'route_planner_api_key';

  /// Stable per-install UUID. Sent to the router as `?device_id=…` so
  /// it can scope each issued key to this device — re-signing in on
  /// this phone revokes only the key from a previous sign-in *here*,
  /// without touching keys minted by other devices that share the
  /// same Google account.
  static const String _deviceIdKey = 'route_planner_device_id';

  /// URL scheme registered for the deep-link callback. iOS:
  /// `Info.plist` `CFBundleURLTypes`. Android: `AndroidManifest.xml`
  /// intent-filter on `com.linusu.flutter_web_auth_2.CallbackActivity`.
  static const String _callbackScheme = 'zeddisplay';

  /// Native bridge for nudging `MainActivity` back to the foreground
  /// after the Custom Tab OAuth flow returns. Defined in
  /// `MainActivity.kt`; iOS is a no-op (ASWebAuthenticationSession
  /// auto-dismisses).
  static const MethodChannel _platform =
      MethodChannel('com.zennora.zed_display/intent');

  final StorageService _storage;
  String? _cached;

  /// The current bearer token, or null if the user has not yet signed in.
  String? get token => _cached;
  bool get hasToken => (_cached ?? '').isNotEmpty;

  /// Returns the `Authorization` header value, or null when no token is set.
  String? get authHeader =>
      hasToken ? 'Bearer ${_cached!}' : null;

  Map<String, String> authorisedHeaders({Map<String, String>? extra}) {
    final h = <String, String>{};
    if (extra != null) h.addAll(extra);
    final a = authHeader;
    if (a != null) h['Authorization'] = a;
    return h;
  }

  Future<void> setBearerToken(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      await clear();
      return;
    }
    _cached = trimmed;
    await _storage.saveSetting(_tokenKey, trimmed);
    notifyListeners();
  }

  Future<void> clear() async {
    _cached = null;
    await _storage.deleteSetting(_tokenKey);
    notifyListeners();
  }

  /// Run the system-browser sign-in flow and persist the minted token
  /// on success. Returns null on cancel, or the error string on
  /// failure. Returns the fresh token on success (also persisted).
  ///
  /// `baseUrl` must point at a route-planner deployment whose
  /// `auth.py` exposes `/auth/google/login-mobile` and is configured
  /// to redirect to the [_callbackScheme] deep link after auth.
  Future<RoutePlannerSignInResult> signInWithGoogle(String baseUrl) async {
    final start = _buildStartUri(baseUrl, _ensureDeviceId());
    if (start == null) {
      return const RoutePlannerSignInResult.error('Invalid base URL.');
    }
    try {
      // Returns the full redirect URL when the OS catches the deep
      // link, throws when the user cancels (PlatformException on iOS,
      // CanceledLoginException on Android). `ephemeralIntentFlags`
      // adds `FLAG_ACTIVITY_NO_HISTORY` so the Chrome Custom Tab task
      // is removed once the deep link fires — without it the parked
      // Google sign-in page hangs around on Android until the user
      // swipes back. iOS's ASWebAuthenticationSession auto-dismisses,
      // so the flag is a no-op there.
      final result = await FlutterWebAuth2.authenticate(
        url: start.toString(),
        callbackUrlScheme: _callbackScheme,
        options: const FlutterWebAuth2Options(
          intentFlags: ephemeralIntentFlags,
        ),
      );
      final callback = Uri.parse(result);
      final token = callback.queryParameters['token']?.trim();
      if (token == null || token.isEmpty) {
        await _bringAppToFront();
        return const RoutePlannerSignInResult.error(
          'No token in callback URL.',
        );
      }
      await setBearerToken(token);
      await _bringAppToFront();
      return RoutePlannerSignInResult.success(token);
    } catch (e) {
      // The user-facing UX is identical for any failure (cancel,
      // network, server) — surface the message and let the caller
      // decide whether to snackbar it.
      await _bringAppToFront();
      return RoutePlannerSignInResult.error(e.toString());
    }
  }

  /// Pull `MainActivity` back to the foreground on Android once the
  /// Custom Tab flow returns. Without this nudge Chrome's task stays
  /// parked on the Google account chooser even after the deep link
  /// has been delivered to the plugin and the future has resolved.
  /// iOS / desktop are no-ops because their auth windows auto-dismiss.
  Future<void> _bringAppToFront() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _platform.invokeMethod('bringToFront');
    } on PlatformException catch (e) {
      if (kDebugMode) {
        debugPrint('bringToFront failed: $e');
      }
    }
  }

  /// Read or lazily-generate this install's stable device UUID. Used
  /// to scope route-planner key revocation per device — see [_deviceIdKey].
  String _ensureDeviceId() {
    final existing = _storage.getSetting(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final fresh = const Uuid().v4();
    // Fire-and-forget: the value is also held in `existing` if a later
    // call lands before the box flushes, but the storage write itself
    // is fast and the worst-case is a duplicate UUID generation if the
    // app is killed mid-flight.
    unawaited(_storage.saveSetting(_deviceIdKey, fresh));
    return fresh;
  }

  /// Builds `<baseUrl>/auth/google/login-mobile?device_id=<id>`.
  /// Tolerates a trailing slash and an inline path prefix on `baseUrl`.
  static Uri? _buildStartUri(String baseUrl, String deviceId) {
    var trimmed = baseUrl.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null || !parsed.hasScheme) return null;
    return parsed.replace(
      path: '${parsed.path}/auth/google/login-mobile'
          .replaceAll('//', '/'),
      queryParameters: {'device_id': deviceId},
    );
  }

  /// Suggested key name for the route planner's `api_keys.json`. Not
  /// sent today — the server names mobile keys itself ("ZedDisplay
  /// Mobile ({date})") — but exposed here so a future server change
  /// can accept a client-supplied label without another round of
  /// service rewiring. Reuses [AuthService.generateDeviceDescription]
  /// so the convention matches SignalK access requests.
  static Future<String> defaultKeyName() async {
    final base = await AuthService.generateDeviceDescription();
    final date = DateTime.now().toIso8601String().substring(0, 10);
    return '$base ($date)';
  }
}

/// Result of [RoutePlannerAuthService.signInWithGoogle]. Sealed-style
/// enum so the caller can distinguish "user cancelled" from "real
/// error" without parsing the message.
class RoutePlannerSignInResult {
  const RoutePlannerSignInResult.success(this.token)
      : ok = true,
        error = null;
  const RoutePlannerSignInResult.error(this.error)
      : ok = false,
        token = null;

  final bool ok;
  final String? token;
  final String? error;
}
