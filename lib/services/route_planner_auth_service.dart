import 'dart:async';
import 'dart:convert';
import 'dart:math' show Random;

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel, PlatformException;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
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
/// secure browsers" policy with a 403 `disallowed_useragent`).
///
/// Once the user signs in, the router redirects to the registered
/// deep link with a one-time `code` and the `state` we generated at
/// the start of the attempt. The token never appears in the URL —
/// the app POSTs `{code, state}` to `/auth/google/exchange` to fetch
/// it via JSON, keeping it out of browser history (RFC 9700). On
/// success the token is persisted via [setBearerToken] and the
/// configurator UI auto-syncs through [notifyListeners].
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

  /// URL scheme registered for the deep-link callback. Reverse-DNS per
  /// RFC 8252 §7.1 — domain we control, written backwards. iOS:
  /// `Info.plist` `CFBundleURLTypes`. Android: `AndroidManifest.xml`
  /// intent-filter on `com.linusu.flutter_web_auth_2.CallbackActivity`.
  static const String _callbackScheme = 'com.zennora.zeddisplay';

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

  /// Run the system-browser sign-in flow, exchange the one-time code
  /// for the minted token, and persist it. Returns a sealed result —
  /// callers should branch on [RoutePlannerSignInResult.ok] for
  /// success and on [RoutePlannerSignInResult.cancelled] to suppress
  /// "Sign-in failed" surfaces when the user just hit the close
  /// button.
  ///
  /// `baseUrl` must point at a route-planner deployment whose
  /// `auth.py` exposes both `/auth/google/login-mobile` and
  /// `/auth/google/exchange`, and is configured to redirect to the
  /// [_callbackScheme] deep link after auth.
  Future<RoutePlannerSignInResult> signInWithGoogle(String baseUrl) async {
    final state = const Uuid().v4();
    // PKCE: keep `verifier` only in memory for the duration of this
    // sign-in attempt. The server stores `challenge`, the client
    // sends `verifier` on /exchange, and the server checks
    // BASE64URL(SHA256(verifier)) == stored challenge — so even an
    // attacker who intercepts the deep-link redirect can't redeem
    // the code without our locally-held verifier.
    final verifier = _generatePkceVerifier();
    final challenge = _pkceChallenge(verifier);
    final start = _buildStartUri(
      baseUrl,
      _ensureDeviceId(),
      state,
      challenge,
    );
    if (start == null) {
      return const RoutePlannerSignInResult.error('Invalid base URL.');
    }
    String redirect;
    try {
      // `ephemeralIntentFlags` adds `FLAG_ACTIVITY_NO_HISTORY` so the
      // Chrome Custom Tab task is removed once the deep link fires —
      // iOS's ASWebAuthenticationSession auto-dismisses, so the flag
      // is a no-op there.
      redirect = await FlutterWebAuth2.authenticate(
        url: start.toString(),
        callbackUrlScheme: _callbackScheme,
        options: const FlutterWebAuth2Options(
          intentFlags: ephemeralIntentFlags,
        ),
      );
    } on PlatformException catch (e) {
      await _bringAppToFront();
      // `flutter_web_auth_2` reports user cancellation as a
      // PlatformException with code "CANCELED" on both platforms.
      // Anything else is a real error worth surfacing.
      if (e.code == 'CANCELED') {
        return const RoutePlannerSignInResult.cancelled();
      }
      return RoutePlannerSignInResult.error(
        e.message ?? e.code,
      );
    } catch (e) {
      await _bringAppToFront();
      return RoutePlannerSignInResult.error(e.toString());
    }

    final callback = Uri.parse(redirect);
    final returnedState = callback.queryParameters['state']?.trim();
    if (returnedState == null || returnedState != state) {
      // Anti-forgery: a deep link landing here whose state doesn't
      // match the value we generated isn't part of *this* sign-in —
      // could be a hostile app trying to inject a code.
      await _bringAppToFront();
      return const RoutePlannerSignInResult.error('Invalid OAuth state.');
    }
    final code = callback.queryParameters['code']?.trim();
    if (code == null || code.isEmpty) {
      await _bringAppToFront();
      return const RoutePlannerSignInResult.error('No code in callback.');
    }

    final exchange = _buildExchangeUri(baseUrl);
    if (exchange == null) {
      await _bringAppToFront();
      return const RoutePlannerSignInResult.error('Invalid base URL.');
    }
    try {
      // Bound the round trip — without a timeout a stalled socket on
      // a captive-portal Wi-Fi or a router gone unreachable can leave
      // the auth flow hanging forever instead of surfacing the error.
      final resp = await http
          .post(
            exchange,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'code': code,
              'state': state,
              'code_verifier': verifier,
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        await _bringAppToFront();
        return RoutePlannerSignInResult.error(
          'Exchange failed: HTTP ${resp.statusCode}',
        );
      }
      final body = jsonDecode(resp.body);
      if (body is! Map || body['token'] is! String) {
        await _bringAppToFront();
        return const RoutePlannerSignInResult.error(
          'Exchange response missing token.',
        );
      }
      final token = (body['token'] as String).trim();
      if (token.isEmpty) {
        await _bringAppToFront();
        return const RoutePlannerSignInResult.error('Empty token.');
      }
      await setBearerToken(token);
      await _bringAppToFront();
      return RoutePlannerSignInResult.success(token);
    } catch (e) {
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
    // `defaultTargetPlatform` works on web (where `dart:io.Platform`
    // throws) so this file stays web-buildable. The MethodChannel
    // call would no-op on platforms without the native handler, but
    // gating is cheaper than a round trip.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
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

  /// Builds the full `/auth/google/login-mobile` URL with all four
  /// query params the server expects (`device_id`, `state`,
  /// `code_challenge`, `code_challenge_method=S256`). Tolerates a
  /// trailing slash and an inline path prefix on `baseUrl`.
  static Uri? _buildStartUri(
    String baseUrl,
    String deviceId,
    String state,
    String codeChallenge,
  ) {
    final base = _normalizeBase(baseUrl);
    if (base == null) return null;
    return base.replace(
      path: '${base.path}/auth/google/login-mobile'.replaceAll('//', '/'),
      queryParameters: {
        'device_id': deviceId,
        'state': state,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
      },
    );
  }

  /// PKCE verifier: 43-char base64url-no-pad string. RFC 7636 §4.1
  /// allows any 43-128-char string from the `[A-Za-z0-9._~-]` alphabet;
  /// base64url-no-pad of 32 random bytes is the standard choice (a
  /// strict subset of that alphabet, exactly 43 chars).
  static String _generatePkceVerifier() {
    final rng = Random.secure();
    final bytes = Uint8List(32);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = rng.nextInt(256);
    }
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// PKCE challenge: `BASE64URL(SHA256(verifier))` with padding stripped.
  /// 43 chars — matches the server's `_PKCE_CHALLENGE_LEN`.
  static String _pkceChallenge(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier)).bytes;
    return base64Url.encode(digest).replaceAll('=', '');
  }

  static Uri? _buildExchangeUri(String baseUrl) {
    final base = _normalizeBase(baseUrl);
    if (base == null) return null;
    return base.replace(
      path: '${base.path}/auth/google/exchange'.replaceAll('//', '/'),
    );
  }

  static Uri? _normalizeBase(String baseUrl) {
    var trimmed = baseUrl.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null) return null;
    // Reject `file:`, `mailto:`, `javascript:`, custom-scheme deep
    // links, etc. — anything we'd later concatenate `/auth/…` onto
    // and try to launch in the system browser must be an absolute
    // HTTP(S) URL with a real host.
    final scheme = parsed.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    if (parsed.host.isEmpty) return null;
    return parsed;
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

/// Result of [RoutePlannerAuthService.signInWithGoogle]. Three
/// distinct outcomes so the caller can render cancellation silently
/// without parsing exception messages.
class RoutePlannerSignInResult {
  const RoutePlannerSignInResult.success(this.token)
      : ok = true,
        cancelled = false,
        error = null;
  const RoutePlannerSignInResult.error(this.error)
      : ok = false,
        cancelled = false,
        token = null;
  const RoutePlannerSignInResult.cancelled()
      : ok = false,
        cancelled = true,
        token = null,
        error = null;

  final bool ok;
  final bool cancelled;
  final String? token;
  final String? error;
}
