import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'storage_service.dart';

/// Bearer-token store for the weather route-planner API.
///
/// Phase 1 (ship first) auth strategy: the user taps "Sign in with Google",
/// which opens the router's web OAuth page in the system browser. They sign
/// in, mint an API key in the web UI, copy it, and paste it into the tool
/// config here. Token is persisted in [StorageService]'s settings box
/// (unencrypted Hive, matching the pattern used for SignalK tokens).
///
/// Phase 2 will add an in-app WebView that captures the minted token
/// automatically. This service exposes a stable API surface so that
/// upgrade is transparent to callers.
class RoutePlannerAuthService extends ChangeNotifier {
  RoutePlannerAuthService(this._storage) {
    _cached = _storage.getSetting(_tokenKey);
  }

  static const String _tokenKey = 'route_planner_api_key';

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

  /// Phase 1 sign-in: opens `<baseUrl>/auth/google/login?next=/settings/api-keys.html`
  /// in the system browser so the user can authenticate with Google and mint
  /// an API key, then paste it back into the tool configurator.
  ///
  /// Returns true if the browser launch succeeded (not whether the user
  /// completed the flow).
  Future<bool> signInWithGoogle(String baseUrl) async {
    final uri = _buildSignInUri(baseUrl);
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Uri? _buildSignInUri(String baseUrl) {
    var trimmed = baseUrl.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null || !parsed.hasScheme) return null;
    return parsed.replace(
      path: '${parsed.path}/auth/google/login'.replaceAll('//', '/'),
      queryParameters: {'next': '/settings/api-keys.html'},
    );
  }
}
