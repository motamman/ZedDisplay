import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/app_colors.dart';
import '../../models/weather_route_request.dart';
import '../../models/weather_route_result.dart';
import '../../services/route_planner_auth_service.dart';
import '../../services/weather_routing_service.dart';
import 'weather_routing_itinerary_card.dart';
import 'weather_routing_overlay.dart';

typedef WeatherRoutingWaypointFocus = void Function(int index);

/// Shows the weather routing sheet. The caller provides:
/// - [vesselPosition] — current own-vessel position. Used as the start
///   fallback when no explicit start pin is placed, and as the "Use
///   vessel" action target in the compose tab.
/// - [defaultMode] — persisted in V3's `customProperties`
/// - [defaultPolar] — persisted in V3's `customProperties`
/// - [onFocusWaypoint] — pans the chart to a waypoint when the user
///   selects a card
///
/// Planned start/end pins are read from [WeatherRoutingService] so that
/// the chart's long-press + drag-marker UX stays in sync with the panel.
void showWeatherRoutingSheet(
  BuildContext context, {
  required LatLon? vesselPosition,
  required RouteMode defaultMode,
  required String? defaultPolar,
  required WeatherRoutingWaypointFocus onFocusWaypoint,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => DraggableScrollableSheet(
      initialChildSize: 0.55,
      maxChildSize: 0.92,
      minChildSize: 0.25,
      snap: true,
      snapSizes: const [0.25, 0.55, 0.92],
      builder: (_, scrollController) => _WeatherRoutingSheet(
        scrollController: scrollController,
        vesselPosition: vesselPosition,
        defaultMode: defaultMode,
        defaultPolar: defaultPolar,
        onFocusWaypoint: onFocusWaypoint,
      ),
    ),
  );
}

class _WeatherRoutingSheet extends StatefulWidget {
  const _WeatherRoutingSheet({
    required this.scrollController,
    required this.vesselPosition,
    required this.defaultMode,
    required this.defaultPolar,
    required this.onFocusWaypoint,
  });

  final ScrollController scrollController;
  final LatLon? vesselPosition;
  final RouteMode defaultMode;
  final String? defaultPolar;
  final WeatherRoutingWaypointFocus onFocusWaypoint;

  @override
  State<_WeatherRoutingSheet> createState() => _WeatherRoutingSheetState();
}

class _WeatherRoutingSheetState extends State<_WeatherRoutingSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  // Cache the service so `dispose()` / the listener callback never need
  // to look it up via `context`. Once the sheet is dismissed, the
  // BuildContext is deactivated and `context.read` throws
  // "Looking up a deactivated widget's ancestor is unsafe."
  WeatherRoutingService? _service;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    final service = context.read<WeatherRoutingService>();
    _service = service;
    service.addListener(_onServiceChanged);
    _maybeSelectTabForStatus(service.status);
  }

  @override
  void dispose() {
    _service?.removeListener(_onServiceChanged);
    _service = null;
    _tabs.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    if (!mounted) return;
    final service = _service;
    if (service == null) return;
    _maybeSelectTabForStatus(service.status);
  }

  void _maybeSelectTabForStatus(WeatherRoutingStatus status) {
    switch (status) {
      case WeatherRoutingStatus.submitting:
      case WeatherRoutingStatus.queued:
      case WeatherRoutingStatus.running:
        if (_tabs.index != 1) _tabs.animateTo(1);
        break;
      case WeatherRoutingStatus.done:
        if (_tabs.index != 2) _tabs.animateTo(2);
        break;
      case WeatherRoutingStatus.error:
      case WeatherRoutingStatus.cancelled:
      case WeatherRoutingStatus.idle:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.cardBackgroundDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Handle.
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.flight_takeoff, color: Colors.white70, size: 20),
                SizedBox(width: 8),
                Text(
                  'Weather Routing',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabs,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            indicatorColor: AppColors.infoBlue,
            tabs: const [
              Tab(text: 'Compose'),
              Tab(text: 'Progress'),
              Tab(text: 'Result'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _ComposeTab(
                  scrollController: widget.scrollController,
                  vesselPosition: widget.vesselPosition,
                  defaultMode: widget.defaultMode,
                  defaultPolar: widget.defaultPolar,
                ),
                _ProgressTab(scrollController: widget.scrollController),
                _ResultTab(
                  scrollController: widget.scrollController,
                  onFocusWaypoint: widget.onFocusWaypoint,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ================= Compose Tab =================

class _ComposeTab extends StatefulWidget {
  const _ComposeTab({
    required this.scrollController,
    required this.vesselPosition,
    required this.defaultMode,
    required this.defaultPolar,
  });

  final ScrollController scrollController;
  final LatLon? vesselPosition;
  final RouteMode defaultMode;
  final String? defaultPolar;

  @override
  State<_ComposeTab> createState() => _ComposeTabState();
}

class _ComposeTabState extends State<_ComposeTab> {
  late RouteMode _mode = widget.defaultMode;
  late DateTime _departure = DateTime.now();
  final _tokenCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tokenCtrl.text =
        context.read<RoutePlannerAuthService>().token ?? '';
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDeparture() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _departure,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 7)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_departure),
    );
    if (time == null || !mounted) return;
    setState(() {
      _departure = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<RoutePlannerAuthService>();
    final service = context.watch<WeatherRoutingService>();

    final effectiveStart = service.plannedStart ?? widget.vesselPosition;
    final usingVesselStart =
        service.plannedStart == null && widget.vesselPosition != null;

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF14142A),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFF2A2A44)),
          ),
          child: const Row(
            children: [
              Icon(Icons.touch_app, color: Colors.white54, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Long-press the chart to place Start and End pins. '
                  'Drag a pin to refine its position.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _sectionLabel('Start'),
        _coordRow(
          label: usingVesselStart ? 'From (vessel)' : 'From',
          value: effectiveStart,
          primary: widget.vesselPosition == null
              ? null
              : _PinAction(
                  label: 'Use vessel',
                  onTap: () {
                    service.plannedStart = widget.vesselPosition;
                  },
                ),
          secondary: service.plannedStart == null
              ? null
              : _PinAction(
                  label: 'Clear',
                  onTap: () => service.plannedStart = null,
                ),
        ),
        const SizedBox(height: 12),
        _sectionLabel('End'),
        _coordRow(
          label: 'To',
          value: service.plannedEnd,
          primary: service.plannedEnd == null
              ? const _PinAction(
                  label: 'Long-press chart',
                  onTap: null,
                )
              : _PinAction(
                  label: 'Clear',
                  onTap: () => service.plannedEnd = null,
                ),
        ),
        const SizedBox(height: 16),
        _sectionLabel('Routing mode'),
        SegmentedButton<RouteMode>(
          segments: const [
            ButtonSegment(value: RouteMode.sailMax, label: Text('Sail max')),
            ButtonSegment(value: RouteMode.fastest, label: Text('Fastest')),
            ButtonSegment(value: RouteMode.motor, label: Text('Motor')),
          ],
          selected: {_mode},
          onSelectionChanged: (v) => setState(() => _mode = v.first),
        ),
        const SizedBox(height: 16),
        _sectionLabel('Departure'),
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(
            _formatDateTime(_departure),
            style: const TextStyle(color: Colors.white),
          ),
          trailing: TextButton.icon(
            icon: const Icon(Icons.access_time, size: 18),
            label: const Text('Change'),
            onPressed: _pickDeparture,
          ),
        ),
        const SizedBox(height: 16),
        const Divider(color: Colors.white12),
        const SizedBox(height: 8),
        _sectionLabel('Authentication'),
        const Text(
          'Paste a bearer token, or tap "Sign in with Google" to mint one.',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _tokenCtrl,
                obscureText: true,
                style: const TextStyle(color: Colors.white, fontFamily: 'Menlo'),
                decoration: InputDecoration(
                  hintText: auth.hasToken
                      ? 'Token set — paste new to replace'
                      : 'Bearer token',
                  hintStyle: const TextStyle(color: Colors.white38),
                  isDense: true,
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: const Color(0xFF141424),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Paste',
              icon: const Icon(Icons.paste, color: Colors.white70),
              onPressed: () async {
                final data = await Clipboard.getData('text/plain');
                if (data?.text != null) {
                  _tokenCtrl.text = data!.text!.trim();
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.login),
                label: const Text('Sign in with Google'),
                onPressed: () async {
                  final ok = await auth.signInWithGoogle(service.baseUrl);
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Could not open browser')),
                    );
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _tokenCtrl.text.isEmpty && !auth.hasToken
                  ? null
                  : () async {
                      await auth.setBearerToken(_tokenCtrl.text);
                    },
              child: const Text('Save token'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          icon: const Icon(Icons.play_arrow),
          label: const Text('Compute route'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: _canSubmit(auth, service)
              ? () => _submit(service)
              : null,
        ),
        if (service.errorMessage != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF3A1A1A),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.alarmRed, width: 1),
            ),
            child: Text(
              service.errorMessage!,
              style: const TextStyle(color: Color(0xFFFF8888)),
            ),
          ),
        ],
      ],
    );
  }

  bool _canSubmit(
      RoutePlannerAuthService auth, WeatherRoutingService service) {
    if (service.isBusy) return false;
    final effectiveStart = service.plannedStart ?? widget.vesselPosition;
    if (effectiveStart == null || service.plannedEnd == null) return false;
    if (!auth.hasToken && _tokenCtrl.text.trim().isEmpty) return false;
    return true;
  }

  Future<void> _submit(WeatherRoutingService service) async {
    // Commit any pasted-but-unsaved token before submitting.
    final auth = context.read<RoutePlannerAuthService>();
    if (_tokenCtrl.text.trim().isNotEmpty &&
        _tokenCtrl.text.trim() != auth.token) {
      await auth.setBearerToken(_tokenCtrl.text.trim());
    }
    final start = service.plannedStart ?? widget.vesselPosition!;
    final req = WeatherRouteRequest(
      start: start,
      end: service.plannedEnd!,
      mode: _mode,
      departure: _departure,
      polar: widget.defaultPolar,
    );
    await service.submitRoute(req);
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      );

  Widget _coordRow({
    required String label,
    required LatLon? value,
    _PinAction? primary,
    _PinAction? secondary,
  }) {
    final text = value == null
        ? '— not set —'
        : '${value.lat.toStringAsFixed(5)}, ${value.lon.toStringAsFixed(5)}';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 2),
              Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontFamily: 'Menlo',
                ),
              ),
            ],
          ),
        ),
        if (primary != null)
          TextButton(onPressed: primary.onTap, child: Text(primary.label)),
        if (secondary != null)
          TextButton(onPressed: secondary.onTap, child: Text(secondary.label)),
      ],
    );
  }

  String _formatDateTime(DateTime d) {
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)}  ${two(l.hour)}:${two(l.minute)} local';
  }
}

class _PinAction {
  const _PinAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;
}

// ================= Progress Tab =================

class _ProgressTab extends StatefulWidget {
  const _ProgressTab({required this.scrollController});
  final ScrollController scrollController;

  @override
  State<_ProgressTab> createState() => _ProgressTabState();
}

class _ProgressTabState extends State<_ProgressTab> {
  final _logScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
  }

  void _scrollToEnd() {
    if (!_logScroll.hasClients) return;
    _logScroll.jumpTo(_logScroll.position.maxScrollExtent);
  }

  @override
  void dispose() {
    _logScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<WeatherRoutingService>();
    final elapsed = service.submittedAt == null
        ? null
        : DateTime.now().difference(service.submittedAt!);
    // Schedule a scroll-to-end after the build that added new log lines.
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _statusPill(service.status),
              const SizedBox(width: 12),
              if (elapsed != null)
                Text(
                  '${elapsed.inSeconds}s elapsed',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontFamily: 'Menlo',
                    fontSize: 11,
                  ),
                ),
              const Spacer(),
              if (service.isBusy)
                TextButton.icon(
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: const Text('Cancel'),
                  onPressed: service.cancelJob,
                ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(6),
            ),
            child: ListView.builder(
              controller: _logScroll,
              itemCount: service.logLines.length,
              itemBuilder: (_, i) => _logLine(service.logLines[i]),
            ),
          ),
        ),
        if (service.errorMessage != null)
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF3A1A1A),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              service.errorMessage!,
              style: const TextStyle(color: Color(0xFFFF8888)),
            ),
          ),
      ],
    );
  }

  Widget _statusPill(WeatherRoutingStatus s) {
    final (label, bg, fg) = switch (s) {
      WeatherRoutingStatus.idle => ('IDLE', Colors.black26, Colors.white54),
      WeatherRoutingStatus.submitting =>
        ('SUBMITTING', const Color(0xFF1A1A3A), const Color(0xFFAAAAFF)),
      WeatherRoutingStatus.queued =>
        ('QUEUED', const Color(0xFF3A2A0A), const Color(0xFFFFCC44)),
      WeatherRoutingStatus.running =>
        ('RUNNING', const Color(0xFF1A3A1A), const Color(0xFF88FF88)),
      WeatherRoutingStatus.done =>
        ('DONE', const Color(0xFF0A3A0A), const Color(0xFF44FF44)),
      WeatherRoutingStatus.cancelled =>
        ('CANCELLED', Colors.black45, Colors.white70),
      WeatherRoutingStatus.error =>
        ('ERROR', const Color(0xFF3A1A1A), const Color(0xFFFF8888)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontFamily: 'Menlo',
          letterSpacing: 0.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _logLine(WeatherRoutingLogLine line) {
    final (colour, bold) = switch (line.kind) {
      WeatherRoutingLogKind.log => (const Color(0xFF00FF00), false),
      WeatherRoutingLogKind.status => (const Color(0xFF88CCFF), false),
      WeatherRoutingLogKind.done => (const Color(0xFF44FF44), true),
      WeatherRoutingLogKind.error => (const Color(0xFFFF4444), false),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Text(
        line.text,
        style: TextStyle(
          color: colour,
          fontSize: 11,
          height: 1.5,
          fontFamily: 'Menlo',
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }
}

// ================= Result Tab =================

class _ResultTab extends StatelessWidget {
  const _ResultTab({
    required this.scrollController,
    required this.onFocusWaypoint,
  });

  final ScrollController scrollController;
  final WeatherRoutingWaypointFocus onFocusWaypoint;

  @override
  Widget build(BuildContext context) {
    final service = context.watch<WeatherRoutingService>();
    final result = service.currentResult;
    if (result == null || result.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No route computed yet. Compose one on the first tab.',
            style: TextStyle(color: Colors.white54),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(12),
      children: [
        _StatSummary(result: result),
        const SizedBox(height: 10),
        for (var i = 0; i < result.waypoints.length; i++)
          WeatherRoutingItineraryCard(
            index: i,
            waypoint: result.waypoints[i],
            kind: legKindAt(result.waypoints, i),
            selected: false,
            onTap: () => onFocusWaypoint(i),
          ),
      ],
    );
  }
}

class _StatSummary extends StatelessWidget {
  const _StatSummary({required this.result});
  final WeatherRouteResult result;

  @override
  Widget build(BuildContext context) {
    final s = result.summary;
    final parts = <Widget>[];
    void add(TextSpan t) => parts.add(RichText(text: t));

    const labelStyle = TextStyle(color: Color(0xFF888888), fontFamily: 'Menlo');
    const valueStyle = TextStyle(color: Colors.white, fontFamily: 'Menlo');
    const boldStyle = TextStyle(
      color: Colors.white,
      fontFamily: 'Menlo',
      fontWeight: FontWeight.bold,
    );

    if (s.totalDistanceM != null) {
      add(TextSpan(
        style: boldStyle,
        text: '${(s.totalDistanceM! / metersPerNm).toStringAsFixed(1)} nm',
      ));
    }
    if (s.totalTimeS != null) {
      add(TextSpan(style: labelStyle, children: [
        const TextSpan(text: '  |  '),
        TextSpan(
          style: valueStyle,
          text: '${(s.totalTimeS! / 3600).toStringAsFixed(1)} h',
        ),
      ]));
    }
    if (s.sailingTimeS != null) {
      add(TextSpan(style: labelStyle, children: [
        const TextSpan(text: '  |  Sail '),
        TextSpan(
          style: valueStyle,
          text: '${(s.sailingTimeS! / 3600).toStringAsFixed(1)} h',
        ),
      ]));
    }
    if (s.motoringTimeS != null) {
      add(TextSpan(style: labelStyle, children: [
        const TextSpan(text: '  |  Motor '),
        TextSpan(
          style: valueStyle,
          text: '${(s.motoringTimeS! / 3600).toStringAsFixed(1)} h',
        ),
      ]));
    }
    add(TextSpan(style: labelStyle, children: [
      const TextSpan(text: '  |  '),
      TextSpan(
        style: valueStyle,
        text: '${result.waypoints.length} wpts',
      ),
    ]));

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF14142A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF2A2A44)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: parts,
      ),
    );
  }
}
