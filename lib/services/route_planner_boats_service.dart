import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/service_constants.dart';
import '../models/boat.dart';
import '../models/boat_polar_specs.dart';
import '../models/polar_entry.dart';
import '../models/sailboatdata_hit.dart';
import 'route_planner_auth_service.dart';
import 'storage_service.dart';

/// Wraps the route-planner `/boats` + `/polars` surface. Caches the
/// caller's boat list and polar list, holds the currently-selected
/// boat (persisted via `StorageService` so it survives restarts),
/// exposes errors as `lastError` for snackbar surfacing.
///
/// Base URL is shared with `WeatherRoutingService` — the caller
/// updates it via [baseUrl] at the same time the routing service
/// gets its per-tool override.
class RoutePlannerBoatsService extends ChangeNotifier {
  RoutePlannerBoatsService({
    required RoutePlannerAuthService auth,
    required StorageService storage,
  })  : _auth = auth,
        _storage = storage {
    _selectedBoatId = _storage.getSetting(_selectedBoatIdKey);
  }

  static const String _selectedBoatIdKey =
      'route_planner_selected_boat_id';

  final RoutePlannerAuthService _auth;
  final StorageService _storage;

  // ===== Base URL =====
  String _baseUrl = 'https://router.zeddisplay.com';
  String get baseUrl => _baseUrl;
  set baseUrl(String v) {
    final trimmed = v.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed == _baseUrl) return;
    _baseUrl = trimmed;
    // Drop cached state — it's owned by the old server.
    _allBoats = const [];
    _ownedBoatIds.clear();
    _polars = const [];
    notifyListeners();
  }

  // ===== State =====
  //
  // `_allBoats` is the full server inventory (`GET /boats/all`) —
  // drives the picker.
  // `_ownedBoatIds` is a cached set of ids the caller can edit /
  // delete / reference by `vessel.boat_id` in `POST /route`. The
  // server 404s `boat_id` for foreign boats, so the client has to
  // expand those into explicit `polar` + `vessel` overrides at
  // submit time.
  List<Boat> _allBoats = const [];
  final Set<String> _ownedBoatIds = {};

  List<Boat> get boats => _allBoats;

  /// Subset of [boats] owned by the authenticated caller.
  Iterable<Boat> get ownedBoats =>
      _allBoats.where((b) => _ownedBoatIds.contains(b.id));

  bool isOwnedByCaller(String boatId) => _ownedBoatIds.contains(boatId);

  List<PolarEntry> _polars = const [];
  List<PolarEntry> get polars => _polars;

  String? _selectedBoatId;
  Boat? get selectedBoat {
    if (_selectedBoatId == null) return null;
    for (final b in _allBoats) {
      if (b.id == _selectedBoatId) return b;
    }
    return null;
  }

  String? get selectedBoatId => _selectedBoatId;

  String? _lastError;
  String? get lastError => _lastError;
  void clearError() {
    if (_lastError == null) return;
    _lastError = null;
    notifyListeners();
  }

  bool _loadingBoats = false;
  bool get loadingBoats => _loadingBoats;

  bool _loadingPolars = false;
  bool get loadingPolars => _loadingPolars;

  // ===== Boat CRUD =====

  /// Fetches the caller's saved boats (`GET /boats`) and the full
  /// polar library (`GET /polars`) in parallel. The picker renders
  /// the saved boats as editable rows; polars that aren't yet
  /// attached to any saved boat appear below as "adopt me" rows
  /// that call `POST /boats` on tap via [adoptPolar].
  Future<void> refreshAllBoats() async {
    _loadingBoats = true;
    notifyListeners();
    final results = await Future.wait([
      _getJsonList('/boats'),
      _getJsonList('/polars'),
    ]);
    final boatList = results[0];
    final polarList = results[1];
    if (boatList != null) {
      _allBoats = boatList
          .whereType<Map<String, dynamic>>()
          .map(Boat.fromJson)
          .toList(growable: false);
      _ownedBoatIds
        ..clear()
        ..addAll(_allBoats.map((b) => b.id));
    }
    if (polarList != null) {
      _polars = polarList
          .whereType<Map<String, dynamic>>()
          .map(PolarEntry.fromJson)
          .toList(growable: false);
    }
    // Drop stale selection if the saved id no longer exists.
    if (_selectedBoatId != null &&
        _allBoats.every((b) => b.id != _selectedBoatId)) {
      _selectedBoatId = null;
      unawaited(_storage.deleteSetting(_selectedBoatIdKey));
    }
    _loadingBoats = false;
    notifyListeners();
  }

  /// Polars from the library that aren't yet attached to any of the
  /// caller's saved boats. Rendered as "adopt me" rows in the picker;
  /// tapping one calls [adoptPolar] which materialises a boat and
  /// selects it.
  List<PolarEntry> get orphanedPolars {
    final attached = <String>{
      for (final b in _allBoats)
        if (b.polarPath != null && b.polarPath!.isNotEmpty) b.polarPath!,
    };
    return _polars
        .where((p) => !attached.contains(p.path))
        .toList(growable: false);
  }

  /// Materialise a polar as a saved boat on the server (name + type +
  /// polar_path only — dimensions null, server falls back to vessel
  /// defaults). Selects the new boat on success.
  Future<Boat?> adoptPolar(PolarEntry polar) async {
    final draft = BoatDraft(
      name: polar.label.isNotEmpty ? polar.label : polar.name,
      type: 'sail',
      polarPath: polar.path,
    );
    final boat = await createBoat(draft);
    if (boat != null) setSelectedBoat(boat);
    return boat;
  }

  /// Legacy: refresh only the caller's own boats (`GET /boats`).
  /// Still useful when you need to know "what can I edit?" without
  /// touching the full inventory. Most UI paths should call
  /// [refreshAllBoats] instead.
  Future<void> refreshBoats() async {
    _loadingBoats = true;
    notifyListeners();
    final list = await _getJsonList('/boats');
    if (list != null) {
      final owned = list
          .whereType<Map<String, dynamic>>()
          .map(Boat.fromJson)
          .toList(growable: false);
      _ownedBoatIds
        ..clear()
        ..addAll(owned.map((b) => b.id));
      // Merge owned entries into `_allBoats` (retain any foreign
      // entries already cached from a prior /boats/all call).
      final merged = <String, Boat>{
        for (final b in _allBoats) b.id: b,
        for (final b in owned) b.id: b,
      };
      _allBoats = merged.values.toList(growable: false);
      if (_selectedBoatId != null &&
          _allBoats.every((b) => b.id != _selectedBoatId)) {
        _selectedBoatId = null;
        unawaited(_storage.deleteSetting(_selectedBoatIdKey));
      }
    }
    _loadingBoats = false;
    notifyListeners();
  }

  Future<Boat?> createBoat(BoatDraft draft) async {
    final resp = await _request(
      method: 'POST',
      path: '/boats',
      body: draft.toBoatSpecJson(),
    );
    if (resp == null) return null;
    final boat = Boat.fromJson(resp);
    _allBoats = [boat, ..._allBoats];
    _ownedBoatIds.add(boat.id);
    notifyListeners();
    return boat;
  }

  Future<Boat?> patchBoat(String id, Map<String, dynamic> changes) async {
    final resp = await _request(
      method: 'PATCH',
      path: '/boats/$id',
      body: changes,
    );
    if (resp == null) return null;
    final updated = Boat.fromJson(resp);
    _allBoats = [
      for (final b in _allBoats)
        if (b.id == id) updated else b,
    ];
    notifyListeners();
    return updated;
  }

  Future<Boat?> replaceBoat(String id, BoatDraft draft) async {
    final resp = await _request(
      method: 'PUT',
      path: '/boats/$id',
      body: draft.toFullReplaceJson(),
    );
    if (resp == null) return null;
    final updated = Boat.fromJson(resp);
    _allBoats = [
      for (final b in _allBoats)
        if (b.id == id) updated else b,
    ];
    notifyListeners();
    return updated;
  }

  Future<bool> deleteBoat(String id) async {
    final ok = await _requestNoContent(
      method: 'DELETE',
      path: '/boats/$id',
    );
    if (!ok) return false;
    _allBoats = _allBoats.where((b) => b.id != id).toList(growable: false);
    _ownedBoatIds.remove(id);
    if (_selectedBoatId == id) {
      _selectedBoatId = null;
      unawaited(_storage.deleteSetting(_selectedBoatIdKey));
    }
    notifyListeners();
    return true;
  }

  void setSelectedBoat(Boat? boat) {
    final id = boat?.id;
    if (id == _selectedBoatId) return;
    _selectedBoatId = id;
    if (id == null) {
      unawaited(_storage.deleteSetting(_selectedBoatIdKey));
    } else {
      unawaited(_storage.saveSetting(_selectedBoatIdKey, id));
    }
    notifyListeners();
  }

  // ===== Sailboatdata =====

  Future<SailboatdataSearchResult?> searchSailboatdata(
    String query, {
    int limit = 25,
  }) async {
    final q = query.trim();
    if (q.length < 2) {
      return const SailboatdataSearchResult(
          query: '', cached: false, hits: []);
    }
    final uri = Uri.parse('$_baseUrl/boats/search').replace(
      queryParameters: {
        'q': q,
        'limit': '$limit',
      },
    );
    try {
      final resp = await http
          .get(uri, headers: _auth.authorisedHeaders())
          .timeout(ServiceConstants.longHttpTimeout);
      if (resp.statusCode != 200) {
        _setError('Search failed: HTTP ${resp.statusCode}');
        return null;
      }
      final j = jsonDecode(resp.body);
      if (j is! Map<String, dynamic>) return null;
      return SailboatdataSearchResult.fromJson(j);
    } catch (e) {
      _setError('Search error: $e');
      return null;
    }
  }

  Future<ExternalBoatPayload?> fromExternalSailboatdata(String id) async {
    final uri = Uri.parse('$_baseUrl/boats/from-external/sailboatdata/$id');
    try {
      final resp = await http
          .get(uri, headers: _auth.authorisedHeaders())
          .timeout(ServiceConstants.longHttpTimeout);
      if (resp.statusCode != 200) {
        _setError('Prefill failed: HTTP ${resp.statusCode}');
        return null;
      }
      final j = jsonDecode(resp.body);
      if (j is! Map<String, dynamic>) return null;
      return ExternalBoatPayload.fromJson(j);
    } catch (e) {
      _setError('Prefill error: $e');
      return null;
    }
  }

  // ===== Polars =====

  Future<void> refreshPolars() async {
    _loadingPolars = true;
    notifyListeners();
    final list = await _getJsonList('/polars');
    if (list != null) {
      _polars = list
          .whereType<Map<String, dynamic>>()
          .map(PolarEntry.fromJson)
          .toList(growable: false);
    }
    _loadingPolars = false;
    notifyListeners();
  }

  /// Generates a polar CSV from the specs and saves it server-side.
  /// Returns the new polar's relative path on success, null on error
  /// (error surfaced via [lastError]). Pass `overwrite: true` to
  /// replace an existing polar of the same slug.
  Future<String?> generatePolarFromSpecs({
    required String name,
    required BoatPolarSpecs specs,
    bool overwrite = false,
  }) async {
    final resp = await _request(
      method: 'POST',
      path: '/polar-from-specs',
      body: {
        'name': name,
        'specs': specs.toJson(),
        'overwrite': overwrite,
      },
    );
    if (resp == null) return null;
    // Refresh the polar list so the new entry shows up in the picker.
    await refreshPolars();
    return resp['polar_path'] as String?;
  }

  Future<bool> deletePolar(String path) async {
    final uri = Uri.parse('$_baseUrl/polars').replace(
      queryParameters: {'path': path},
    );
    try {
      final resp = await http
          .delete(uri, headers: _auth.authorisedHeaders())
          .timeout(ServiceConstants.shortHttpTimeout);
      if (resp.statusCode == 200 || resp.statusCode == 204) {
        _polars =
            _polars.where((p) => p.path != path).toList(growable: false);
        notifyListeners();
        return true;
      }
      _setError('Delete polar failed: HTTP ${resp.statusCode} '
          '${_shortBody(resp.body)}');
      return false;
    } catch (e) {
      _setError('Delete polar error: $e');
      return false;
    }
  }

  // ===== HTTP helpers =====

  Future<List<dynamic>?> _getJsonList(String path) async {
    final uri = Uri.parse('$_baseUrl$path');
    try {
      final resp = await http
          .get(uri, headers: _auth.authorisedHeaders())
          .timeout(ServiceConstants.shortHttpTimeout);
      if (resp.statusCode != 200) {
        _setError('GET $path failed: HTTP ${resp.statusCode}');
        return null;
      }
      final j = jsonDecode(resp.body);
      if (j is! List) {
        _setError('GET $path: expected JSON list');
        return null;
      }
      return j;
    } catch (e) {
      _setError('GET $path error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _request({
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    try {
      final headers = _auth.authorisedHeaders(
        extra: const {'Content-Type': 'application/json'},
      );
      final bodyStr = body == null ? null : jsonEncode(body);
      final future = switch (method) {
        'POST' => http.post(uri, headers: headers, body: bodyStr),
        'PUT' => http.put(uri, headers: headers, body: bodyStr),
        'PATCH' => http.patch(uri, headers: headers, body: bodyStr),
        'DELETE' => http.delete(uri, headers: headers, body: bodyStr),
        _ => http.get(uri, headers: headers),
      };
      final resp = await future.timeout(ServiceConstants.longHttpTimeout);
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        if (resp.body.isEmpty) return <String, dynamic>{};
        final j = jsonDecode(resp.body);
        if (j is Map<String, dynamic>) return j;
        return <String, dynamic>{};
      }
      _setError('$method $path failed: HTTP ${resp.statusCode} '
          '${_shortBody(resp.body)}');
      return null;
    } catch (e) {
      _setError('$method $path error: $e');
      return null;
    }
  }

  Future<bool> _requestNoContent({
    required String method,
    required String path,
  }) async {
    final uri = Uri.parse('$_baseUrl$path');
    try {
      final headers = _auth.authorisedHeaders();
      final future = switch (method) {
        'DELETE' => http.delete(uri, headers: headers),
        _ => http.get(uri, headers: headers),
      };
      final resp = await future.timeout(ServiceConstants.shortHttpTimeout);
      if (resp.statusCode >= 200 && resp.statusCode < 300) return true;
      _setError('$method $path failed: HTTP ${resp.statusCode} '
          '${_shortBody(resp.body)}');
      return false;
    } catch (e) {
      _setError('$method $path error: $e');
      return false;
    }
  }

  void _setError(String message) {
    _lastError = message;
    if (kDebugMode) debugPrint('[RoutePlannerBoatsService] $message');
    notifyListeners();
  }

  static String _shortBody(String body) {
    if (body.length <= 200) return body;
    return '${body.substring(0, 200)}…';
  }
}
