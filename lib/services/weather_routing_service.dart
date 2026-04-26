import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../config/service_constants.dart';
import '../models/weather_route_request.dart';
import '../models/weather_route_result.dart';
import 'route_planner_auth_service.dart';
import 'storage_service.dart';

/// Lifecycle of a compute job. Mirrors the server's JobStatus vocabulary
/// (`routes.py` + `jobs.py`) plus a local `idle` state for "no job in flight".
enum WeatherRoutingStatus {
  idle,
  submitting,
  queued,
  running,
  done,
  cancelled,
  error,
}

/// Colour-coded log line — mirrors the web UI's `#modalLog` styling where
/// `error` lines render red and `done` lines render bold green.
class WeatherRoutingLogLine {
  WeatherRoutingLogLine(this.text, this.kind);
  final String text;
  final WeatherRoutingLogKind kind;
}

enum WeatherRoutingLogKind { log, error, done, status }

/// One row in the "Recent routes" list — a thin projection of the
/// server's `GET /api/v1/routes` response. We only carry the fields
/// the UI needs to render a tap-to-load row; full GeoJSON is fetched
/// on demand via [WeatherRoutingService.loadRecentRoute].
class WeatherRecentJob {
  const WeatherRecentJob({
    required this.jobId,
    required this.status,
    required this.createdAt,
    this.summary,
  });

  final String jobId;
  final String status;
  final DateTime createdAt;

  /// Server-side summary stats when the job is `done`. Populated by
  /// `GET /api/v1/routes/{id}` since the list endpoint may not include
  /// the full summary block.
  final WeatherRouteSummary? summary;
}

/// Submits, tracks, and streams a weather-routing compute job.
///
/// Exposed as a `ChangeNotifier` so panel tabs / the chart overlay can
/// rebuild off a single source of truth. The service survives the modal
/// sheet being dismissed, meaning the user can navigate away from the
/// chart and come back to a still-streaming job. Pattern modelled on
/// [WeatherApiService] — `_isLoading` / `_errorMessage` + `notifyListeners`.
class WeatherRoutingService extends ChangeNotifier
    with WidgetsBindingObserver {
  WeatherRoutingService(this._auth, this._storage) {
    WidgetsBinding.instance.addObserver(this);
  }

  final RoutePlannerAuthService _auth;
  final StorageService _storage;

  /// Hive key for the "active job" blob — see [_persistActiveJob].
  static const String _activeJobKey = 'weather_routing_active_job';

  // ===== Configuration (set per-submission from tool config) =====
  String _baseUrl = 'https://router.zeddisplay.com';
  String get baseUrl => _baseUrl;
  set baseUrl(String v) {
    final trimmed = v.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed == _baseUrl) return;
    _baseUrl = trimmed;
    notifyListeners();
  }

  // ===== Planned endpoints (user-placed pins on the chart) =====
  //
  // Shared state for the chart's drag-markers, the long-press handler,
  // and the compose panel. Null = not yet placed; the compose tab
  // falls back to the vessel's current position for start at submit
  // time so an unconfigured pin doesn't block the happy path.
  LatLon? _plannedStart;
  LatLon? _plannedEnd;
  LatLon? get plannedStart => _plannedStart;
  LatLon? get plannedEnd => _plannedEnd;

  set plannedStart(LatLon? v) {
    if (_isSamePoint(_plannedStart, v)) return;
    _plannedStart = v;
    notifyListeners();
  }

  set plannedEnd(LatLon? v) {
    if (_isSamePoint(_plannedEnd, v)) return;
    _plannedEnd = v;
    notifyListeners();
  }

  void clearPlannedPins() {
    final hadPins = _plannedStart != null || _plannedEnd != null;
    final hadVias = _plannedVias.isNotEmpty;
    if (!hadPins && !hadVias) return;
    _plannedStart = null;
    _plannedEnd = null;
    _plannedVias.clear();
    notifyListeners();
  }

  static bool _isSamePoint(LatLon? a, LatLon? b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return a.lat == b.lat && a.lon == b.lon;
  }

  // ===== Intermediate "via" waypoints =====
  //
  // Mirrors the route-planner web UI's `waypointCoords` array. The
  // server happily accepts these in [WeatherRouteRequest.waypoints]
  // and switches to `compute_multi_leg_route` when present.
  final List<LatLon> _plannedVias = [];
  List<LatLon> get plannedVias => List.unmodifiable(_plannedVias);

  void addVia(LatLon p) {
    _plannedVias.add(p);
    notifyListeners();
  }

  void moveVia(int index, LatLon p) {
    if (index < 0 || index >= _plannedVias.length) return;
    _plannedVias[index] = p;
    notifyListeners();
  }

  void removeVia(int index) {
    if (index < 0 || index >= _plannedVias.length) return;
    _plannedVias.removeAt(index);
    notifyListeners();
  }

  void clearVias() {
    if (_plannedVias.isEmpty) return;
    _plannedVias.clear();
    notifyListeners();
  }

  // ===== Recent routes =====
  List<WeatherRecentJob> _recentJobs = const [];
  List<WeatherRecentJob> get recentJobs => _recentJobs;

  // ===== Live job state =====
  WeatherRoutingStatus _status = WeatherRoutingStatus.idle;
  WeatherRoutingStatus get status => _status;

  String? _currentJobId;
  String? get currentJobId => _currentJobId;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  final List<WeatherRoutingLogLine> _logLines = [];
  List<WeatherRoutingLogLine> get logLines =>
      List.unmodifiable(_logLines);

  WeatherRouteResult? _currentResult;
  WeatherRouteResult? get currentResult => _currentResult;

  WeatherRouteRequest? _lastRequest;
  WeatherRouteRequest? get lastRequest => _lastRequest;

  DateTime? _submittedAt;
  DateTime? get submittedAt => _submittedAt;

  // ===== Internal =====
  http.Client? _sseClient;
  StreamSubscription<String>? _sseSub;
  String? _lastEventId;

  // SSE reconnect bookkeeping. Counter grows on each `onError`; resets
  // to zero whenever we successfully parse a frame. Hard-cap at 5 so we
  // don't pound the server forever after a real outage.
  int _sseReconnectAttempts = 0;
  Timer? _sseReconnectTimer;
  static const int _sseMaxReconnectAttempts = 5;

  bool get isBusy =>
      _status == WeatherRoutingStatus.submitting ||
      _status == WeatherRoutingStatus.queued ||
      _status == WeatherRoutingStatus.running;

  /// Submit a new route compute job. Cancels any in-flight job first.
  ///
  /// The auth token must already be configured on [RoutePlannerAuthService]
  /// — on a missing token the call fails fast with [_errorMessage] set so
  /// the UI can prompt "Sign in first".
  Future<void> submitRoute(WeatherRouteRequest request) async {
    await _teardownSse();

    if (!_auth.hasToken) {
      _errorMessage = 'Sign in or paste a bearer token first.';
      _status = WeatherRoutingStatus.error;
      notifyListeners();
      return;
    }

    _status = WeatherRoutingStatus.submitting;
    _errorMessage = null;
    _logLines.clear();
    _currentResult = null;
    _currentJobId = null;
    _lastEventId = null;
    _lastRequest = request;
    _submittedAt = DateTime.now();
    notifyListeners();

    try {
      final uri = Uri.parse('$_baseUrl/api/v1/routes');
      final resp = await http
          .post(
            uri,
            headers: _auth.authorisedHeaders(
              extra: const {'Content-Type': 'application/json'},
            ),
            body: jsonEncode(request.toJson()),
          )
          .timeout(ServiceConstants.longHttpTimeout);

      if (resp.statusCode != 202) {
        _status = WeatherRoutingStatus.error;
        _errorMessage = 'Submit failed: HTTP ${resp.statusCode} '
            '${_shortBody(resp.body)}';
        notifyListeners();
        return;
      }

      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      _currentJobId = body['job_id'] as String?;
      _status = _parseStatus(body['status'] as String?) ??
          WeatherRoutingStatus.queued;
      notifyListeners();

      if (_currentJobId == null) {
        _status = WeatherRoutingStatus.error;
        _errorMessage = 'Server returned no job_id.';
        notifyListeners();
        return;
      }

      _appendLog('Submitted job ${_currentJobId!}.', WeatherRoutingLogKind.status);
      _persistActiveJob();
      unawaited(_listenToEvents(_currentJobId!));
    } on TimeoutException {
      _status = WeatherRoutingStatus.error;
      _errorMessage = 'Request timed out contacting $_baseUrl';
      notifyListeners();
    } catch (e) {
      _status = WeatherRoutingStatus.error;
      _errorMessage = 'Submit error: $e';
      notifyListeners();
    }
  }

  Future<void> cancelJob() async {
    final id = _currentJobId;
    if (id == null) return;
    try {
      final uri = Uri.parse('$_baseUrl/api/v1/routes/$id/cancel');
      await http
          .post(uri, headers: _auth.authorisedHeaders())
          .timeout(ServiceConstants.shortHttpTimeout);
    } catch (_) {
      // Best-effort cancel; server may have already finished.
    }
    _appendLog('Cancellation requested.', WeatherRoutingLogKind.status);
    await _teardownSse();
    if (_status != WeatherRoutingStatus.done) {
      _status = WeatherRoutingStatus.cancelled;
    }
    _clearActiveJob();
    notifyListeners();
  }

  /// Clear the current result + logs. Does not touch the remote job.
  void clearResult() {
    _currentResult = null;
    _logLines.clear();
    _currentJobId = null;
    _status = WeatherRoutingStatus.idle;
    _errorMessage = null;
    _clearActiveJob();
    notifyListeners();
  }

  Future<void> deleteRemoteJob() async {
    final id = _currentJobId;
    if (id == null) return;
    try {
      final uri = Uri.parse('$_baseUrl/api/v1/routes/$id');
      await http
          .delete(uri, headers: _auth.authorisedHeaders())
          .timeout(ServiceConstants.shortHttpTimeout);
    } catch (_) {
      // Best-effort delete.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sseReconnectTimer?.cancel();
    _sseSub?.cancel();
    _sseClient?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // The OS may have suspended the TCP socket while backgrounded, so the
    // SSE stream is silently dead. If we still think the job is alive,
    // kick a reconnect with `Last-Event-ID` so the server replays
    // anything we missed.
    if (_currentJobId != null && isBusy && _sseSub == null) {
      _appendLog('App resumed — reconnecting stream.',
          WeatherRoutingLogKind.status);
      _sseReconnectAttempts = 0;
      unawaited(_listenToEvents(_currentJobId!));
    }
  }

  // ---------- SSE ----------

  /// Stream `/api/v1/routes/{id}/events`. Parses `event:` / `data:` / `id:`
  /// frames separated by blank lines (RFC EventSource format). Server adds a
  /// 1000-frame ring buffer so `Last-Event-ID` header lets us reconnect
  /// without missing frames.
  Future<void> _listenToEvents(String jobId) async {
    await _teardownSse();
    final client = http.Client();
    _sseClient = client;

    final uri = Uri.parse('$_baseUrl/api/v1/routes/$jobId/events');
    final req = http.Request('GET', uri);
    req.headers.addAll(_auth.authorisedHeaders(
      extra: const {'Accept': 'text/event-stream', 'Cache-Control': 'no-cache'},
    ));
    if (_lastEventId != null) {
      req.headers['Last-Event-ID'] = _lastEventId!;
    }

    try {
      final resp = await client.send(req);
      if (resp.statusCode != 200) {
        _status = WeatherRoutingStatus.error;
        _errorMessage = 'SSE failed: HTTP ${resp.statusCode}';
        notifyListeners();
        await _teardownSse();
        return;
      }

      final stream = resp.stream.transform(utf8.decoder);
      String buffer = '';
      _sseSub = stream.listen(
        (chunk) {
          buffer += chunk;
          // Frames are separated by a blank line. Support both \n\n and
          // \r\n\r\n to be robust to server formatting.
          final pattern = RegExp(r'\r?\n\r?\n');
          while (true) {
            final match = pattern.firstMatch(buffer);
            if (match == null) break;
            final frame = buffer.substring(0, match.start);
            buffer = buffer.substring(match.end);
            // Successful parse → we're back on a healthy stream, reset
            // the reconnect counter so a *future* drop gets the full
            // 2^n window again.
            _sseReconnectAttempts = 0;
            _handleFrame(frame);
          }
        },
        onError: (e) {
          if (kDebugMode) {
            debugPrint('SSE stream error: $e');
          }
          // Null the subscription/client *before* the backoff timer is
          // scheduled. Without this, `didChangeAppLifecycleState`'s
          // `_sseSub == null` fast-path can never fire during the
          // backoff window (or after retries are exhausted), and a
          // user resuming from background would silently fail to
          // reconnect.
          _sseSub = null;
          _sseClient?.close();
          _sseClient = null;
          _scheduleSseReconnect(e);
        },
        onDone: () {
          // The server closed the stream. If the close came after a
          // terminal frame, status is already done/error/cancelled and
          // `_scheduleSseReconnect` is a no-op. If the close came mid-
          // route (proxy idle timeout, Wi-Fi flap), kick the reconnect
          // ladder so we don't sit forever with stale state.
          _sseSub = null;
          _sseClient?.close();
          _sseClient = null;
          if (isBusy && _currentJobId == jobId) {
            _scheduleSseReconnect('stream closed before completion');
          }
        },
        cancelOnError: true,
      );
    } catch (e) {
      _status = WeatherRoutingStatus.error;
      _errorMessage = 'SSE connect error: $e';
      notifyListeners();
      await _teardownSse();
    }
  }

  // Matches both LF and CRLF line endings. Servers that emit CRLF
  // used to leave a trailing `\r` on every parsed value — `event`
  // became `"status\r"` and missed every switch case; `_lastEventId`
  // got poisoned the same way.
  static final _sseLineSplit = RegExp(r'\r?\n');

  void _handleFrame(String frame) {
    String? event;
    final dataLines = <String>[];
    String? id;
    for (final raw in frame.split(_sseLineSplit)) {
      if (raw.isEmpty) continue;
      if (raw.startsWith(':')) continue; // comment
      final colon = raw.indexOf(':');
      if (colon < 0) continue;
      final field = raw.substring(0, colon);
      var value = raw.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);
      switch (field) {
        case 'event':
          event = value;
          break;
        case 'data':
          dataLines.add(value);
          break;
        case 'id':
          id = value;
          break;
      }
    }
    if (id != null && id.isNotEmpty) {
      _lastEventId = id;
      _persistActiveJob();
    }
    if (event == null && dataLines.isEmpty) return;

    final data = dataLines.join('\n');
    switch (event) {
      case 'status':
        _handleStatusEvent(data);
        break;
      case 'log':
        _handleLogEvent(data);
        break;
      case 'route':
        _handleRouteEvent(data);
        break;
      case 'done':
        _handleDoneEvent(data);
        break;
      case 'error':
        _handleErrorEvent(data);
        break;
      default:
        // Unknown event — surface as a log line for visibility.
        _appendLog('[$event] $data', WeatherRoutingLogKind.log);
    }
  }

  void _handleStatusEvent(String data) {
    try {
      final m = jsonDecode(data) as Map<String, dynamic>;
      final s = _parseStatus(m['status'] as String?);
      if (s != null) {
        _status = s;
        _appendLog('Status: ${m['status']}', WeatherRoutingLogKind.status);
        notifyListeners();
      }
    } catch (_) {
      _appendLog('status: $data', WeatherRoutingLogKind.status);
    }
  }

  void _handleLogEvent(String data) {
    try {
      final m = jsonDecode(data) as Map<String, dynamic>;
      final line = (m['line'] as String?) ?? data;
      _appendLog(line, WeatherRoutingLogKind.log);
    } catch (_) {
      _appendLog(data, WeatherRoutingLogKind.log);
    }
  }

  void _handleRouteEvent(String data) {
    try {
      final m = jsonDecode(data) as Map<String, dynamic>;
      _currentResult = WeatherRouteResult.fromGeoJson(m);
      notifyListeners();
    } catch (e) {
      _appendLog('Failed to parse route: $e', WeatherRoutingLogKind.error);
    }
  }

  void _handleDoneEvent(String data) {
    _status = WeatherRoutingStatus.done;
    _appendLog('Done.', WeatherRoutingLogKind.done);
    // Some deployments send `route` as part of the `done` payload rather
    // than a separate frame. Parse defensively.
    if (_currentResult == null) {
      try {
        final m = jsonDecode(data) as Map<String, dynamic>;
        final gj = m['geojson'] ?? m['result'];
        if (gj is Map<String, dynamic>) {
          _currentResult = WeatherRouteResult.fromGeoJson(gj);
        }
      } catch (_) {/* result already null — fetch via /result below */}
    }
    _clearActiveJob();
    notifyListeners();
    // Fall back to a direct /result fetch if no route came through SSE.
    if (_currentResult == null && _currentJobId != null) {
      unawaited(_fetchResultFallback(_currentJobId!));
    }
    _teardownSse();
  }

  void _handleErrorEvent(String data) {
    _status = WeatherRoutingStatus.error;
    String message = data;
    try {
      final m = jsonDecode(data) as Map<String, dynamic>;
      message = (m['message'] as String?) ?? data;
    } catch (_) {/* leave as raw */}
    _errorMessage = message;
    _appendLog(message, WeatherRoutingLogKind.error);
    _clearActiveJob();
    notifyListeners();
    _teardownSse();
  }

  Future<void> _fetchResultFallback(String jobId) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/v1/routes/$jobId/result');
      final resp = await http
          .get(uri, headers: _auth.authorisedHeaders())
          .timeout(ServiceConstants.longHttpTimeout);
      if (resp.statusCode == 200) {
        final m = jsonDecode(resp.body) as Map<String, dynamic>;
        _currentResult = WeatherRouteResult.fromGeoJson(m);
        notifyListeners();
      } else {
        _appendLog('Fetch /result failed: HTTP ${resp.statusCode}',
            WeatherRoutingLogKind.error);
      }
    } catch (e) {
      _appendLog('Fetch /result error: $e', WeatherRoutingLogKind.error);
    }
  }

  Future<void> _teardownSse() async {
    _sseReconnectTimer?.cancel();
    _sseReconnectTimer = null;
    await _sseSub?.cancel();
    _sseSub = null;
    _sseClient?.close();
    _sseClient = null;
  }

  // ---------- Reconnect / Resume ----------

  /// Schedule a `_listenToEvents` retry with exponential backoff, capped
  /// at 5 attempts and 30 s. Caller already detected an SSE drop.
  void _scheduleSseReconnect(Object error) {
    // Don't reconnect after a terminal frame — `done` / `error` /
    // `cancelled` already tore everything down and cleared the blob.
    if (!isBusy || _currentJobId == null) return;
    if (_sseReconnectAttempts >= _sseMaxReconnectAttempts) {
      _appendLog(
          'Stream lost — gave up after $_sseMaxReconnectAttempts retries.',
          WeatherRoutingLogKind.error);
      // Tear down so a future lifecycle resume (or
      // `tryReattachActiveJob` on next launch) sees `_sseSub == null`
      // and can have another go. Active-job blob stays on disk on
      // purpose: the server's TTL is the right authority for whether
      // the job is still recoverable.
      unawaited(_teardownSse());
      return;
    }
    final attempt = _sseReconnectAttempts + 1;
    _sseReconnectAttempts = attempt;
    final delaySeconds = math.min(30, 1 << (attempt - 1));
    _appendLog(
        'Stream dropped ($error) — reconnecting in ${delaySeconds}s '
        '(attempt $attempt/$_sseMaxReconnectAttempts).',
        WeatherRoutingLogKind.status);
    _sseReconnectTimer?.cancel();
    _sseReconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (_currentJobId != null && isBusy) {
        unawaited(_listenToEvents(_currentJobId!));
      }
    });
  }

  /// Persist the in-flight job's `job_id` + last seen event id so a
  /// fresh app launch (or a lifecycle resume after hours of sleep)
  /// can reattach via [tryReattachActiveJob]. Cheap to call on every
  /// SSE frame — just a small Hive `put`.
  void _persistActiveJob() {
    final id = _currentJobId;
    if (id == null) return;
    try {
      final payload = jsonEncode({
        'job_id': id,
        'last_event_id': _lastEventId,
        'submitted_at': _submittedAt?.toUtc().toIso8601String(),
      });
      unawaited(_storage.saveSetting(_activeJobKey, payload));
    } catch (_) {/* best effort */}
  }

  void _clearActiveJob() {
    try {
      unawaited(_storage.deleteSetting(_activeJobKey));
    } catch (_) {/* best effort */}
  }

  /// Look for a persisted in-flight job from a previous session and
  /// reattach to it. Called from `main.dart` once the auth token has
  /// loaded. No-op when nothing is stored, the server has TTL'd the
  /// job, or we lack a token.
  Future<void> tryReattachActiveJob() async {
    final raw = _storage.getSetting(_activeJobKey);
    if (raw == null || raw.isEmpty) return;
    if (!_auth.hasToken) return;

    Map<String, dynamic> blob;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        _clearActiveJob();
        return;
      }
      blob = decoded;
    } catch (_) {
      _clearActiveJob();
      return;
    }

    final jobId = blob['job_id'] as String?;
    if (jobId == null || jobId.isEmpty) {
      _clearActiveJob();
      return;
    }
    final lastEventId = blob['last_event_id'] as String?;
    final submittedAtIso = blob['submitted_at'] as String?;
    final submittedAt =
        submittedAtIso != null ? DateTime.tryParse(submittedAtIso) : null;

    final WeatherRoutingStatus? remoteStatus;
    try {
      final uri = Uri.parse('$_baseUrl/api/v1/routes/$jobId');
      final resp = await http
          .get(uri, headers: _auth.authorisedHeaders())
          .timeout(ServiceConstants.shortHttpTimeout);
      if (resp.statusCode == 404) {
        // Server has TTL'd the job — nothing to resume.
        _clearActiveJob();
        return;
      }
      if (resp.statusCode != 200) {
        // Transient — leave the blob in place so a later boot can retry.
        return;
      }
      final m = jsonDecode(resp.body) as Map<String, dynamic>;
      remoteStatus = _parseStatus(m['status'] as String?);
    } catch (_) {
      // Network down at boot — leave the blob; lifecycle resume will
      // pick it up later when the user has connectivity again.
      return;
    }

    if (remoteStatus == null) {
      _clearActiveJob();
      return;
    }

    _currentJobId = jobId;
    _lastEventId = lastEventId;
    _submittedAt = submittedAt;
    _status = remoteStatus;
    notifyListeners();

    switch (remoteStatus) {
      case WeatherRoutingStatus.done:
        _appendLog('Job $jobId already finished — fetching result.',
            WeatherRoutingLogKind.status);
        await _fetchResultFallback(jobId);
        _clearActiveJob();
        break;
      case WeatherRoutingStatus.queued:
      case WeatherRoutingStatus.running:
        _appendLog('Resuming job $jobId from previous session.',
            WeatherRoutingLogKind.status);
        unawaited(_listenToEvents(jobId));
        break;
      case WeatherRoutingStatus.error:
      case WeatherRoutingStatus.cancelled:
        _appendLog('Previous job $jobId ended as ${remoteStatus.name}.',
            WeatherRoutingLogKind.status);
        _clearActiveJob();
        break;
      case WeatherRoutingStatus.idle:
      case WeatherRoutingStatus.submitting:
        // Server should never report these — treat as terminal junk.
        _clearActiveJob();
        break;
    }
  }

  // ---------- Recent routes ----------

  /// Fetch the caller's recent jobs from `GET /api/v1/routes`, filter
  /// to `status == "done"`, and keep the top 5. Surfaces them via
  /// [recentJobs] so the panel's "Recent" tab can render them.
  Future<void> refreshRecentRoutes() async {
    if (!_auth.hasToken) return;
    try {
      final uri = Uri.parse('$_baseUrl/api/v1/routes?limit=20');
      final resp = await http
          .get(uri, headers: _auth.authorisedHeaders())
          .timeout(ServiceConstants.shortHttpTimeout);
      if (resp.statusCode != 200) return;
      final body = jsonDecode(resp.body);
      // Server may shape this as `{items: [...]}` or as a bare list.
      final List rawItems = body is List
          ? body
          : (body is Map<String, dynamic>
              ? (body['items'] as List? ?? const [])
              : const []);
      final parsed = <WeatherRecentJob>[];
      for (final item in rawItems) {
        if (item is! Map<String, dynamic>) continue;
        final status = (item['status'] as String?) ?? '';
        if (status != 'done') continue;
        final jobId = (item['job_id'] as String?) ?? '';
        if (jobId.isEmpty) continue;
        final createdAtIso = item['created_at'] as String?;
        final createdAt = createdAtIso != null
            ? (DateTime.tryParse(createdAtIso)?.toLocal() ?? DateTime.now())
            : DateTime.now();
        WeatherRouteSummary? summary;
        final summaryMap = item['summary'];
        if (summaryMap is Map<String, dynamic>) {
          summary = WeatherRouteSummary.fromProperties(summaryMap);
        }
        parsed.add(WeatherRecentJob(
          jobId: jobId,
          status: status,
          createdAt: createdAt,
          summary: summary,
        ));
        if (parsed.length >= 5) break;
      }
      _recentJobs = List.unmodifiable(parsed);
      notifyListeners();
    } catch (_) {/* best effort */}
  }

  /// Fetch one finished job's full GeoJSON and hydrate it as the
  /// current result so the Results tab and the on-map overlay
  /// re-render. Sets `_status` to `done` to reflect the loaded
  /// completed result — this isn't a live in-flight job, but the
  /// UI is otherwise indistinguishable from one that just finished.
  ///
  /// Refuses to run when [isBusy] — clobbering an in-flight job's
  /// state would let the live SSE stream race ahead and overwrite
  /// the recent-route result a few frames later. Caller must cancel
  /// or finish the live job first.
  Future<void> loadRecentRoute(String jobId) async {
    if (isBusy) {
      _appendLog(
          'Refusing to load recent route while a job is in flight.',
          WeatherRoutingLogKind.error);
      notifyListeners();
      return;
    }
    try {
      final uri = Uri.parse('$_baseUrl/api/v1/routes/$jobId/result');
      final resp = await http
          .get(uri, headers: _auth.authorisedHeaders())
          .timeout(ServiceConstants.longHttpTimeout);
      if (resp.statusCode != 200) {
        _appendLog('Failed to load recent route: HTTP ${resp.statusCode}',
            WeatherRoutingLogKind.error);
        notifyListeners();
        return;
      }
      final m = jsonDecode(resp.body) as Map<String, dynamic>;
      // Belt-and-braces: drop any persisted resume blob from a prior
      // session, and tear down a stray SSE subscription if one is
      // somehow still alive even though `isBusy` returned false.
      _clearActiveJob();
      await _teardownSse();
      _currentResult = WeatherRouteResult.fromGeoJson(m);
      _currentJobId = jobId;
      _status = WeatherRoutingStatus.done;
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      _appendLog('Load recent route error: $e', WeatherRoutingLogKind.error);
      notifyListeners();
    }
  }

  void _appendLog(String text, WeatherRoutingLogKind kind) {
    _logLines.add(WeatherRoutingLogLine(text, kind));
    // Cap log history to avoid unbounded memory growth for long jobs.
    const maxLines = 2000;
    if (_logLines.length > maxLines) {
      _logLines.removeRange(0, _logLines.length - maxLines);
    }
    notifyListeners();
  }

  static WeatherRoutingStatus? _parseStatus(String? s) {
    switch (s) {
      case 'queued':
        return WeatherRoutingStatus.queued;
      case 'running':
        return WeatherRoutingStatus.running;
      case 'done':
        return WeatherRoutingStatus.done;
      case 'cancelled':
        return WeatherRoutingStatus.cancelled;
      case 'error':
        return WeatherRoutingStatus.error;
      default:
        return null;
    }
  }

  static String _shortBody(String body) {
    if (body.length <= 200) return body;
    return '${body.substring(0, 200)}…';
  }
}
