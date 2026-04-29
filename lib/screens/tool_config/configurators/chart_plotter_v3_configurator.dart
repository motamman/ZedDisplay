import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../models/tool_config.dart';
import '../../../models/tool.dart';
import '../../../models/weather_route_request.dart';
import '../../../services/chart_tile_cache_service.dart';
import '../../../services/route_planner_auth_service.dart';
import '../../../services/signalk_service.dart';
import '../../../widgets/chart_plotter/chart_layer_panel.dart';
import '../base_tool_configurator.dart';

/// Configurator for the native-paint Chart Plotter (tool id
/// `chart_plotter_v3`). Covers layer stacking, display toggles, trail
/// length, HUD, tile-cache staleness policy, and — specific to V3 —
/// per-S-57-class visibility overrides so the user can hide any S-57
/// object class they don't want on the chart.
///
/// Independent of the V1 `ChartPlotterConfigurator`; V1 is deprecated.
class ChartPlotterV3Configurator extends ToolConfigurator {
  @override
  String get toolTypeId => 'chart_plotter_v3';

  @override
  Size get defaultSize => const Size(6, 6);

  List<Map<String, dynamic>> layers = [];
  int trailMinutes = 10;
  bool showAIS = true;
  bool showRoute = true;
  String hudStyle = 'text';
  String hudPosition = 'bottom';
  String cacheRefresh = 'stale';
  Set<String> hiddenClasses = <String>{};

  // Weather routing.
  bool weatherRoutingEnabled = true;
  String routePlannerBaseUrl = 'https://router.zeddisplay.com';
  RouteMode weatherRouteDefaultMode = RouteMode.sailMax;
  String weatherRoutePolar = '';

  @override
  void reset() {
    layers = [
      {'type': 'base', 'id': 'carto_voyager', 'enabled': true, 'opacity': 1.0},
      {'type': 's57', 'id': '01CGD_ENCs', 'enabled': true, 'opacity': 1.0},
    ];
    trailMinutes = 10;
    showAIS = true;
    showRoute = true;
    hudStyle = 'text';
    hudPosition = 'bottom';
    cacheRefresh = 'stale';
    hiddenClasses = <String>{};
    weatherRoutingEnabled = true;
    routePlannerBaseUrl = 'https://router.zeddisplay.com';
    weatherRouteDefaultMode = RouteMode.sailMax;
    weatherRoutePolar = '';
  }

  @override
  void loadDefaults(SignalKService signalKService) {
    reset();
  }

  @override
  void loadFromTool(Tool tool) {
    final props = tool.config.style.customProperties ?? {};
    final rawLayers = props['layers'] as List?;
    if (rawLayers != null && rawLayers.isNotEmpty) {
      layers =
          rawLayers.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } else {
      layers = [
        {'type': 'base', 'id': 'carto_voyager', 'enabled': true, 'opacity': 1.0},
        {'type': 's57', 'id': '01CGD_ENCs', 'enabled': true, 'opacity': 1.0},
      ];
    }
    trailMinutes = props['trailMinutes'] as int? ?? 10;
    showAIS = props['showAIS'] as bool? ?? true;
    showRoute = props['showRoute'] as bool? ?? true;
    hudStyle = props['hudStyle'] as String? ?? 'text';
    hudPosition = props['hudPosition'] as String? ?? 'bottom';
    cacheRefresh = props['cacheRefresh'] as String? ?? 'stale';
    final rawHidden = props['hiddenClasses'];
    if (rawHidden is List) {
      hiddenClasses = rawHidden.map((e) => e.toString()).toSet();
    } else {
      hiddenClasses = <String>{};
    }
    weatherRoutingEnabled = props['weatherRoutingEnabled'] as bool? ?? true;
    routePlannerBaseUrl = props['routePlannerBaseUrl'] as String? ??
        'https://router.zeddisplay.com';
    weatherRouteDefaultMode =
        RouteMode.fromWire(props['weatherRouteDefaultMode'] as String?);
    weatherRoutePolar = props['weatherRoutePolar'] as String? ?? '';
  }

  @override
  ToolConfig getConfig() {
    return ToolConfig(
      dataSources: const [],
      style: StyleConfig(
        customProperties: {
          'layers': layers,
          'trailMinutes': trailMinutes,
          'showAIS': showAIS,
          'showRoute': showRoute,
          'hudStyle': hudStyle,
          'hudPosition': hudPosition,
          'cacheRefresh': cacheRefresh,
          'hiddenClasses': hiddenClasses.toList()..sort(),
          'weatherRoutingEnabled': weatherRoutingEnabled,
          'routePlannerBaseUrl': routePlannerBaseUrl,
          'weatherRouteDefaultMode': weatherRouteDefaultMode.wire,
          'weatherRoutePolar': weatherRoutePolar,
        },
      ),
    );
  }

  @override
  String? validate() => null;

  @override
  Widget buildConfigUI(BuildContext context, SignalKService signalKService) {
    return StatefulBuilder(
      builder: (context, setState) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Chart layers — reorderable
              Text('Chart Layers',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              const Text(
                'Drag to reorder. Bottom layer renders first.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 8),
              ChartLayerPanel(
                layers: layers,
                signalKService: signalKService,
                setState: setState,
              ),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),

              Text('Display',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Show AIS Targets'),
                subtitle: const Text(
                    'Nearby vessel markers and COG projections'),
                value: showAIS,
                onChanged: (v) => setState(() => showAIS = v),
              ),
              SwitchListTile(
                title: const Text('Show Active Route'),
                subtitle:
                    const Text('Route line, waypoints, active leg'),
                value: showRoute,
                onChanged: (v) => setState(() => showRoute = v),
              ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),

              Text('Trail Duration',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 5, label: Text('5 min')),
                  ButtonSegment(value: 10, label: Text('10 min')),
                  ButtonSegment(value: 15, label: Text('15 min')),
                  ButtonSegment(value: 60, label: Text('60 min')),
                ],
                selected: {trailMinutes},
                onSelectionChanged: (v) =>
                    setState(() => trailMinutes = v.first),
              ),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),

              Text('HUD Style',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'text', label: Text('Text')),
                  ButtonSegment(value: 'visual', label: Text('Visual')),
                  ButtonSegment(value: 'off', label: Text('Off')),
                ],
                selected: {hudStyle},
                onSelectionChanged: (v) =>
                    setState(() => hudStyle = v.first),
              ),

              if (hudStyle != 'off') ...[
                const SizedBox(height: 16),
                Text('HUD Position',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'top', label: Text('Top')),
                    ButtonSegment(value: 'bottom', label: Text('Bottom')),
                  ],
                  selected: {hudPosition},
                  onSelectionChanged: (v) =>
                      setState(() => hudPosition = v.first),
                ),
              ],

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),

              Text('Auto-Refresh Charts',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              const Text(
                'Automatically re-fetch cached tiles when they reach this age',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'aging', label: Text('15 days')),
                  ButtonSegment(value: 'stale', label: Text('30 days')),
                ],
                selected: {cacheRefresh},
                onSelectionChanged: (v) =>
                    setState(() => cacheRefresh = v.first),
              ),

              const SizedBox(height: 16),

              // Cache management
              Builder(builder: (ctx) {
                ChartTileCacheService? cacheService;
                try {
                  cacheService = ctx.read<ChartTileCacheService>();
                } catch (_) {}
                if (cacheService == null) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${cacheService.cachedTileCount} tiles cached',
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.delete_sweep),
                        label: const Text('Clear Tile Cache'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                        ),
                        onPressed: () async {
                          await cacheService!.clearCache();
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                );
              }),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),

              // Weather Routing.
              Text('Weather Routing',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              const Text(
                'Connects to the route-planner API for weather-optimal routes.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Enable weather routing'),
                subtitle: const Text(
                    'Shows the toolbar button and draws computed routes'),
                value: weatherRoutingEnabled,
                onChanged: (v) => setState(() => weatherRoutingEnabled = v),
              ),
              if (weatherRoutingEnabled) ...[
                TextFormField(
                  initialValue: routePlannerBaseUrl,
                  decoration: const InputDecoration(
                    labelText: 'API URL',
                    hintText: 'https://router.zeddisplay.com',
                    isDense: true,
                  ),
                  onChanged: (v) =>
                      setState(() => routePlannerBaseUrl = v.trim()),
                ),
                const SizedBox(height: 12),
                const Text('Default routing mode',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 4),
                SegmentedButton<RouteMode>(
                  segments: const [
                    ButtonSegment(
                        value: RouteMode.sailMax,
                        label: Text('Sail max')),
                    ButtonSegment(
                        value: RouteMode.fastest,
                        label: Text('Fastest')),
                    ButtonSegment(
                        value: RouteMode.motor,
                        label: Text('Motor')),
                  ],
                  selected: {weatherRouteDefaultMode},
                  onSelectionChanged: (v) =>
                      setState(() => weatherRouteDefaultMode = v.first),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: weatherRoutePolar,
                  decoration: const InputDecoration(
                    labelText: 'Polar file (optional)',
                    hintText: 'e.g. catalina36.csv',
                    isDense: true,
                  ),
                  onChanged: (v) =>
                      setState(() => weatherRoutePolar = v.trim()),
                ),
                const SizedBox(height: 12),
                _BearerTokenSection(baseUrl: routePlannerBaseUrl),
              ],

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),

              // Per-class visibility overrides.
              _ClassVisibilitySection(
                hidden: hiddenClasses,
                onChanged: (next) => setState(() {
                  hiddenClasses = next;
                }),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Grouped toggle list for S-57 object-class visibility.
///
/// Categories mirror the sprite-report inventory groupings. Toggling
/// OFF a class adds it to the hidden set; the chart painter skips
/// features whose `objectClass` is in that set.
class _ClassVisibilitySection extends StatefulWidget {
  const _ClassVisibilitySection({
    required this.hidden,
    required this.onChanged,
  });

  final Set<String> hidden;
  final ValueChanged<Set<String>> onChanged;

  @override
  State<_ClassVisibilitySection> createState() =>
      _ClassVisibilitySectionState();
}

class _ClassVisibilitySectionState extends State<_ClassVisibilitySection> {
  String _search = '';
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // Curated groups of S-57 object classes. Labels describe what each
  // class represents on a NOAA ENC — sourced from the sprite report's
  // reference tables (devdocs/chart-plotter-v3-sprite-report.md). Not
  // exhaustive; covers the classes a mariner is likely to want to
  // toggle. Users can request additions via TODO if something is
  // missing.
  static const _groups = <_ClassGroup>[
    _ClassGroup('Navigation aids', [
      _ClassEntry('BOYLAT', 'Lateral buoy'),
      _ClassEntry('BCNLAT', 'Lateral beacon'),
      _ClassEntry('BOYCAR', 'Cardinal buoy'),
      _ClassEntry('BCNCAR', 'Cardinal beacon'),
      _ClassEntry('BOYSAW', 'Safe-water buoy'),
      _ClassEntry('BCNSAW', 'Safe-water beacon'),
      _ClassEntry('BOYSPP', 'Special-purpose buoy'),
      _ClassEntry('BCNSPP', 'Special-purpose beacon'),
      _ClassEntry('BOYISD', 'Isolated-danger buoy'),
      _ClassEntry('LIGHTS', 'Lights'),
      _ClassEntry('LITFLT', 'Light float'),
      _ClassEntry('LITVES', 'Lightvessel'),
      _ClassEntry('TOPMAR', 'Topmark'),
      _ClassEntry('FOGSIG', 'Fog signal'),
      _ClassEntry('DAYMAR', 'Daymark / daybeacon'),
      _ClassEntry('RDOSTA', 'Radio station'),
      _ClassEntry('RTPBCN', 'Racon / Ramark'),
      _ClassEntry('RADSTA', 'Shore radar (VTS)'),
      _ClassEntry('SISTAT', 'Traffic signal station'),
      _ClassEntry('SISTAW', 'Warning signal station'),
    ]),
    _ClassGroup('Depths and hazards', [
      _ClassEntry('SOUNDG', 'Spot soundings'),
      _ClassEntry('DEPARE', 'Depth areas (colour bands)'),
      _ClassEntry('DEPCNT', 'Depth contours'),
      _ClassEntry('DRGARE', 'Dredged area'),
      _ClassEntry('SWPARE', 'Swept area'),
      _ClassEntry('OBSTRN', 'Obstruction'),
      _ClassEntry('UWTROC', 'Underwater rock'),
      _ClassEntry('WRECKS', 'Wreck'),
      _ClassEntry('SBDARE', 'Nature of seabed'),
      _ClassEntry('WEDKLP', 'Weed / kelp'),
      _ClassEntry('SNDWAV', 'Sand waves'),
      _ClassEntry('MARCUL', 'Marine farm'),
    ]),
    _ClassGroup('Routing and traffic', [
      _ClassEntry('FAIRWY', 'Fairway'),
      _ClassEntry('RECTRC', 'Recommended track'),
      _ClassEntry('NAVLNE', 'Navigation line'),
      _ClassEntry('TSSLPT', 'TSS lane'),
      _ClassEntry('TSSBND', 'TSS boundary'),
      _ClassEntry('TSEZNE', 'TSS separation zone'),
      _ClassEntry('DWRTPT', 'Deep-water route part'),
      _ClassEntry('DWRTCL', 'Deep-water route centerline'),
      _ClassEntry('TWRTPT', 'Two-way route'),
      _ClassEntry('ACHARE', 'Anchorage area'),
      _ClassEntry('ACHBRT', 'Anchor berth'),
      _ClassEntry('FERYRT', 'Ferry route'),
      _ClassEntry('SUBTLN', 'Submarine transit lane'),
    ]),
    _ClassGroup('Coastline and land', [
      _ClassEntry('LNDARE', 'Land area'),
      _ClassEntry('COALNE', 'Coastline'),
      _ClassEntry('SLCONS', 'Shoreline construction'),
      _ClassEntry('LNDMRK', 'Conspicuous landmark'),
      _ClassEntry('LNDRGN', 'Land region (named)'),
      _ClassEntry('LNDELV', 'Land elevation'),
      _ClassEntry('RIVERS', 'Rivers'),
      _ClassEntry('LAKARE', 'Lake'),
      _ClassEntry('BUAARE', 'Built-up area'),
      _ClassEntry('BUISGL', 'Single building'),
    ]),
    _ClassGroup('Regulated / administrative', [
      _ClassEntry('RESARE', 'Restricted area'),
      _ClassEntry('EXEZNE', 'Military exercise zone'),
      _ClassEntry('MIPARE', 'Military practice area'),
      _ClassEntry('OSPARE', 'Offshore production area'),
      _ClassEntry('PRDARE', 'Production area'),
      _ClassEntry('PRCARE', 'Precautionary area'),
      _ClassEntry('DMPGRD', 'Dumping ground'),
      _ClassEntry('SPLARE', 'Seaplane landing'),
      _ClassEntry('CTNARE', 'Caution area'),
      _ClassEntry('TESARE', 'Territorial sea'),
      _ClassEntry('CTSARE', 'Contiguous zone'),
      _ClassEntry('FSHFAC', 'Fishing facility'),
      _ClassEntry('MAGVAR', 'Magnetic variation'),
      _ClassEntry('LOCMAG', 'Local magnetic anomaly'),
    ]),
    _ClassGroup('Infrastructure', [
      _ClassEntry('BRIDGE', 'Bridge'),
      _ClassEntry('DAMCON', 'Dam'),
      _ClassEntry('DYKCON', 'Dyke / levee'),
      _ClassEntry('GATCON', 'Gate / lock gate'),
      _ClassEntry('MORFAC', 'Mooring facility'),
      _ClassEntry('HRBFAC', 'Harbour facility'),
      _ClassEntry('SMCFAC', 'Small craft facility'),
      _ClassEntry('OFSPLF', 'Offshore platform'),
      _ClassEntry('SILTNK', 'Silo / tank'),
      _ClassEntry('TUNNEL', 'Tunnel'),
      _ClassEntry('CAUSWY', 'Causeway'),
      _ClassEntry('CANALS', 'Canal'),
      _ClassEntry('PIPSOL', 'Submarine pipeline'),
      _ClassEntry('PIPARE', 'Pipeline area'),
      _ClassEntry('CBLSUB', 'Submarine cable'),
      _ClassEntry('CBLOHD', 'Overhead cable'),
      _ClassEntry('PIPOHD', 'Overhead pipeline'),
      _ClassEntry('CONVYR', 'Conveyor'),
      _ClassEntry('PONTON', 'Pontoon'),
      _ClassEntry('PYLONS', 'Pylons'),
      _ClassEntry('PILPNT', 'Pile / piling'),
    ]),
    _ClassGroup('Administrative regions', [
      _ClassEntry('ADMARE', 'Administrative area'),
      _ClassEntry('COSARE', 'Coastguard surveillance'),
      _ClassEntry('CONZNE', 'Contiguous zone'),
      _ClassEntry('CUSZNE', 'Customs zone'),
      _ClassEntry('ISTZNE', 'Inshore traffic zone'),
      _ClassEntry('SEAARE', 'Named sea area'),
      _ClassEntry('UNSARE', 'Unsurveyed area'),
    ]),
    _ClassGroup('Metadata layers', [
      _ClassEntry('M_COVR', 'Data coverage'),
      _ClassEntry('M_QUAL', 'Data quality / CATZOC'),
      _ClassEntry('M_NSYS', 'Nav system boundary (IALA)'),
      _ClassEntry('M_NPUB', 'Nautical publication ref'),
      _ClassEntry('M_CSCL', 'Compilation scale'),
    ]),
  ];

  bool _matchesSearch(_ClassEntry e) {
    if (_search.isEmpty) return true;
    final q = _search.toLowerCase();
    return e.code.toLowerCase().contains(q) ||
        e.label.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final anyHidden = widget.hidden.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Chart Object Visibility',
                  style: Theme.of(context).textTheme.titleSmall),
            ),
            if (anyHidden)
              TextButton.icon(
                onPressed: () => widget.onChanged(<String>{}),
                icon: const Icon(Icons.visibility, size: 16),
                label: const Text('Show all'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Toggle OFF any S-57 object class you do not want drawn on the '
          'chart. Off-classes still tap through to the popover — only '
          'the ink is suppressed.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _searchCtrl,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search, size: 18),
            hintText: 'Filter (e.g. "buoy", "DEPARE", "restricted")',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => setState(() => _search = v.trim()),
        ),
        const SizedBox(height: 12),
        for (final group in _groups)
          _GroupCard(
            title: group.name,
            entries: group.entries.where(_matchesSearch).toList(),
            hidden: widget.hidden,
            onToggle: (code, visible) {
              final next = Set<String>.from(widget.hidden);
              if (visible) {
                next.remove(code);
              } else {
                next.add(code);
              }
              widget.onChanged(next);
            },
            onGroupAll: (visible) {
              final next = Set<String>.from(widget.hidden);
              for (final e in group.entries) {
                if (visible) {
                  next.remove(e.code);
                } else {
                  next.add(e.code);
                }
              }
              widget.onChanged(next);
            },
          ),
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.title,
    required this.entries,
    required this.hidden,
    required this.onToggle,
    required this.onGroupAll,
  });

  final String title;
  final List<_ClassEntry> entries;
  final Set<String> hidden;
  final void Function(String code, bool visible) onToggle;
  final void Function(bool visible) onGroupAll;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final anyHidden = entries.any((e) => hidden.contains(e.code));
    final allHidden = entries.every((e) => hidden.contains(e.code));
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(title),
        subtitle: allHidden
            ? const Text('all hidden',
                style: TextStyle(fontSize: 11, color: Colors.orange))
            : anyHidden
                ? const Text('some hidden',
                    style: TextStyle(fontSize: 11, color: Colors.grey))
                : null,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => onGroupAll(true),
                child: const Text('Show group'),
              ),
              TextButton(
                onPressed: () => onGroupAll(false),
                child: const Text('Hide group'),
              ),
              const SizedBox(width: 8),
            ],
          ),
          for (final e in entries)
            SwitchListTile(
              dense: true,
              title: Text('${e.label}  ·  ${e.code}',
                  style: const TextStyle(fontSize: 13)),
              value: !hidden.contains(e.code),
              onChanged: (v) => onToggle(e.code, v),
            ),
        ],
      ),
    );
  }
}

class _ClassGroup {
  const _ClassGroup(this.name, this.entries);
  final String name;
  final List<_ClassEntry> entries;
}

class _ClassEntry {
  const _ClassEntry(this.code, this.label);
  final String code;
  final String label;
}

/// Token entry for the route-planner API. Reads/writes the shared
/// [RoutePlannerAuthService] directly — token is global, not per-tool.
class _BearerTokenSection extends StatefulWidget {
  const _BearerTokenSection({required this.baseUrl});
  final String baseUrl;

  @override
  State<_BearerTokenSection> createState() => _BearerTokenSectionState();
}

class _BearerTokenSectionState extends State<_BearerTokenSection> {
  final _ctrl = TextEditingController();
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _ctrl.text = context.read<RoutePlannerAuthService>().token ?? '';
    _ctrl.addListener(() {
      final next = _ctrl.text != (context.read<RoutePlannerAuthService>().token ?? '');
      if (next != _dirty) setState(() => _dirty = next);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<RoutePlannerAuthService>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Bearer token',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
            const Spacer(),
            if (auth.hasToken)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.verified_user,
                    color: Color(0xFF88DD88), size: 14),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                obscureText: true,
                style: const TextStyle(fontFamily: 'Menlo'),
                decoration: InputDecoration(
                  hintText: auth.hasToken
                      ? 'Token set — paste new to replace'
                      : 'Paste bearer token',
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Paste',
              icon: const Icon(Icons.paste, size: 18),
              onPressed: () async {
                final data = await Clipboard.getData('text/plain');
                final t = data?.text?.trim();
                if (t != null && t.isNotEmpty) _ctrl.text = t;
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.login, size: 18),
                label: const Text('Sign in with Google'),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final ok = await auth.signInWithGoogle(widget.baseUrl);
                  if (!ok) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Could not open browser')),
                    );
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: (_ctrl.text.isEmpty && !auth.hasToken) || !_dirty
                  ? null
                  : () async {
                      await auth.setBearerToken(_ctrl.text);
                      if (!mounted) return;
                      setState(() => _dirty = false);
                    },
              child: const Text('Save'),
            ),
            if (auth.hasToken) ...[
              const SizedBox(width: 4),
              TextButton(
                onPressed: () async {
                  await auth.clear();
                  _ctrl.clear();
                  if (!mounted) return;
                  setState(() => _dirty = false);
                },
                child: const Text('Sign out',
                    style: TextStyle(color: Color(0xFFFF8888))),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
