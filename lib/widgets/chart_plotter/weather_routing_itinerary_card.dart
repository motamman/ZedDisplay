import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/path_metadata.dart';
import '../../models/weather_route_result.dart';
import '../../services/signalk_service.dart';
import 'weather_routing_overlay.dart';

/// Single itinerary leg card, matching the dark-theme card rendered by
/// the route planner's web UI (`populateItinerary()` at
/// route-planner.html:2165-2282). A 3px left-accent border coloured by
/// tack / motoring / arrival, head row with index + local-time, mode
/// badge pill, 2-column key/value grid in the body, coords footer.
class WeatherRoutingItineraryCard extends StatelessWidget {
  const WeatherRoutingItineraryCard({
    super.key,
    required this.index,
    required this.waypoint,
    required this.next,
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final WeatherRouteWaypoint waypoint;
  /// The waypoint at index+1, or null on the last waypoint. Forward-looking
  /// fields (SOG/COG/Wind/TWA/Current) are sampled from `next` so the card
  /// describes the leg the vessel is *about to start*, matching the
  /// outgoing-leg `kind` accent. Time / Waves / Depth / Coords stay at
  /// `waypoint` (those are point samples, not leg-attributed). On the last
  /// waypoint `next` is null and forward-looking fields fall back to
  /// `waypoint`'s own values (= arrival conditions), which is the right
  /// reading for the ARRIVAL card.
  final WeatherRouteWaypoint? next;
  final WeatherRouteLegKind kind;
  final bool selected;
  final VoidCallback onTap;

  // Web UI palette.
  static const _bgColor = Color(0xFF14142A);
  static const _borderColor = Color(0xFF2A2A44);
  static const _labelColor = Color(0xFF888888);
  static const _valueColor = Color(0xFFCCFFCC);
  static const _goodColor = Color(0xFF44FF44);
  static const _badColor = Color(0xFFFF6666);
  static const _warnColor = Color(0xFFDDCC00);
  static const _coordColor = Color(0xFF666666);

  static const _mono = 'Menlo';

  @override
  Widget build(BuildContext context) {
    // Every numeric value routes through MetadataStore via the
    // project's canonical pattern: `store.get(path) ??
    // store.getByCategory(category)` + `formatOrRaw(value, decimals:
    // N, siSuffix: 'X')`. `get(path)` already does the categoryLookup
    // chain via the server's findCategoryForPath; `?? getByCategory`
    // is the last-ditch "any entry of this kind" fallback for paths
    // the server doesn't publish (the route-planner waypoint case).
    // Categories ('speed', 'depth', 'angle', 'height') are the ones
    // actually used elsewhere in this codebase — invented names like
    // 'shortHeight' or 'duration' don't exist in the server's
    // _defaultCategories vocabulary and silently return null.
    final store = context.read<SignalKService>().metadataStore;
    final speedMd = store.get('navigation.speedOverGround')
        ?? store.getByCategory('speed');
    final depthMd = store.get('environment.depth.belowSurface')
        ?? store.getByCategory('depth');
    final waveMd = store.get('environment.water.waves.height')
        ?? store.getByCategory('height');
    final angleMd = store.get('navigation.courseOverGroundTrue')
        ?? store.getByCategory('angle');
    // No 'duration' / 'time' category exists in this codebase. Direct
    // path lookup may still hit if the server publishes it via meta
    // delta; otherwise formatOrRaw falls back to the SI suffix.
    final periodMd = store.get('environment.water.waves.period');

    final accent = colorForLegKind(kind);
    final bg = selected ? _tintedBg(kind) : _bgColor;
    final borderColor = selected ? accent : _borderColor;
    // Flutter won't paint a rounded border with non-uniform side colours,
    // so the left-accent "stripe" is a separate child inside a Row instead
    // of a coloured left BorderSide.
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 3, color: accent),
                Expanded(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _head(),
                        const SizedBox(height: 4),
                        _grid(speedMd, depthMd, waveMd, angleMd, periodMd),
                        const SizedBox(height: 3),
                        Text(
                          '${waypoint.lat.toStringAsFixed(4)}, ${waypoint.lon.toStringAsFixed(4)}',
                          style: const TextStyle(
                            color: _coordColor,
                            fontSize: 10,
                            fontFamily: _mono,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _head() {
    final time = waypoint.time;
    final hh = time != null
        ? time.toLocal().hour.toString().padLeft(2, '0')
        : '--';
    final mm = time != null
        ? time.toLocal().minute.toString().padLeft(2, '0')
        : '--';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          children: [
            Text(
              '${index + 1}.',
              style: const TextStyle(
                color: _labelColor,
                fontWeight: FontWeight.bold,
                fontFamily: _mono,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$hh:$mm',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontFamily: _mono,
                fontSize: 13,
              ),
            ),
          ],
        ),
        _modeBadge(),
      ],
    );
  }

  Widget _modeBadge() {
    final label = _modeLabel(kind);
    final (bg, fg) = _badgeColors(kind);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontFamily: _mono,
          letterSpacing: 0.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _grid(PathMetadata? speedMd, PathMetadata? depthMd,
      PathMetadata? waveMd, PathMetadata? angleMd, PathMetadata? periodMd) {
    final kvs = <(String, String, Color?)>[];
    // `fwd` = the waypoint at the *end* of the upcoming leg (i.e. wp[i+1]).
    // For the last waypoint there is no upcoming leg — fall back to wp[i]
    // itself so the ARRIVAL card still has data (representing the conditions
    // the vessel arrives in).
    final fwd = next ?? waypoint;

    // Route-planner ships angles in degrees; SignalK angle metadata
    // expects SI radians. Convert at the call site so the metadata
    // formula and symbol apply correctly (e.g. user with degrees preset
    // sees degrees, with mils preset sees mils).
    double degToRad(double d) => d * math.pi / 180.0;

    // Speed Over Ground — forward-looking.
    if (fwd.sogMs != null) {
      kvs.add(('SOG',
          speedMd.formatOrRaw(fwd.sogMs!, decimals: 1, siSuffix: 'm/s'),
          null));
    }
    // Course Over Ground — forward-looking. Cardinal label is sector,
    // independent of the user's display unit.
    if (fwd.cogDeg != null) {
      kvs.add(('COG',
          '${_cardinal(fwd.cogDeg!)} ${angleMd.formatOrRaw(degToRad(fwd.cogDeg!), decimals: 0, siSuffix: 'rad')}',
          null));
    }
    // Wind — speed and direction both via metadata.
    if (fwd.windMs != null && fwd.windDirDeg != null) {
      final spd = speedMd.formatOrRaw(fwd.windMs!, decimals: 0, siSuffix: 'm/s');
      final dir = angleMd.formatOrRaw(degToRad(fwd.windDirDeg!), decimals: 0, siSuffix: 'rad');
      final pos = fwd.twaDeg != null
          ? ' · ${_pointOfSail(fwd.twaDeg!)}'
          : '';
      kvs.add(('Wind',
          '$spd from ${_cardinal(fwd.windDirDeg!)} ($dir)$pos',
          null));
    }
    // TWA — forward-looking.
    if (fwd.twaDeg != null) {
      kvs.add(('TWA',
          angleMd.formatOrRaw(degToRad(fwd.twaDeg!), decimals: 0, siSuffix: 'rad'),
          null));
    }
    // Current — forward-looking. Speed and direction both via metadata;
    // fair/foul classification compares current set against the
    // forward-looking COG so the relation describes the upcoming leg.
    if (fwd.currentMs != null &&
        fwd.currentMs! > 0.05 &&
        fwd.currentDirDeg != null) {
      final setDir = fwd.currentDirDeg!;
      final cardinal = _cardinal(setDir);
      final spd = speedMd.formatOrRaw(fwd.currentMs!, decimals: 2, siSuffix: 'm/s');
      final dir = angleMd.formatOrRaw(degToRad(setDir), decimals: 0, siSuffix: 'rad');
      final relation = _currentRelation(fwd.cogDeg, setDir);
      Color? colour;
      switch (relation) {
        case 'fair':
          colour = _goodColor;
          break;
        case 'foul':
          colour = _badColor;
          break;
        case 'cross':
          colour = _warnColor;
          break;
      }
      kvs.add(('Current',
          '$spd from $cardinal ($dir) · $relation',
          colour));
    }
    // Waves — sampled AT the waypoint. SWH via own wave-height metadata
    // (not aliased to depth: a user can prefer different display units
    // for each). Period uses path lookup only — no project category.
    // Direction goes through angle metadata like every other compass
    // bearing in the card.
    if (waypoint.swhM != null) {
      final parts = <String>[
        waveMd.formatOrRaw(waypoint.swhM!, decimals: 1, siSuffix: 'm'),
      ];
      if (waypoint.mwpS != null) {
        parts.add(periodMd.formatOrRaw(waypoint.mwpS!, decimals: 0, siSuffix: 's'));
      }
      if (waypoint.mwdDeg != null) {
        parts.add(
            'from ${_cardinal(waypoint.mwdDeg!)} ${angleMd.formatOrRaw(degToRad(waypoint.mwdDeg!), decimals: 0, siSuffix: 'rad')}');
      }
      kvs.add(('Waves', parts.join(' · '), null));
    }
    // Depth — sampled AT the waypoint.
    if (waypoint.depthM != null) {
      kvs.add(('Depth',
          depthMd.formatOrRaw(waypoint.depthM!, decimals: 1, siSuffix: 'm'),
          null));
    }

    if (kvs.isEmpty) {
      return const SizedBox.shrink();
    }

    // Render as a two-column wrapping layout.
    return Wrap(
      spacing: 14,
      runSpacing: 2,
      children: kvs
          .map((e) => _kv(e.$1, e.$2, colour: e.$3))
          .toList(growable: false),
    );
  }

  Widget _kv(String k, String v, {Color? colour}) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontFamily: _mono, fontSize: 11),
        children: [
          TextSpan(
            text: '$k ',
            style: const TextStyle(color: _labelColor),
          ),
          TextSpan(
            text: v,
            style: TextStyle(
              color: colour ?? _valueColor,
              fontWeight: colour != null ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  static Color _tintedBg(WeatherRouteLegKind k) {
    // Matches the route-planner's active-card tint alphas (18-22%).
    switch (k) {
      case WeatherRouteLegKind.starboardTack:
        return const Color(0x382E7D32);
      case WeatherRouteLegKind.portTack:
        return const Color(0x38D32F2F);
      case WeatherRouteLegKind.motoring:
        return const Color(0x2EFFCC44);
      case WeatherRouteLegKind.arrival:
        return const Color(0x338888FF);
    }
  }

  static (Color bg, Color fg) _badgeColors(WeatherRouteLegKind k) {
    switch (k) {
      case WeatherRouteLegKind.starboardTack:
        return (const Color(0xFF1A3A1A), const Color(0xFF88FF88));
      case WeatherRouteLegKind.portTack:
        return (const Color(0xFF3A1A1A), const Color(0xFFFF8888));
      case WeatherRouteLegKind.motoring:
        return (const Color(0xFF3A2A0A), const Color(0xFFFFCC44));
      case WeatherRouteLegKind.arrival:
        return (const Color(0xFF1A1A3A), const Color(0xFFAAAAFF));
    }
  }

  static String _modeLabel(WeatherRouteLegKind k) {
    switch (k) {
      case WeatherRouteLegKind.starboardTack:
        return 'SAIL · STBD';
      case WeatherRouteLegKind.portTack:
        return 'SAIL · PORT';
      case WeatherRouteLegKind.motoring:
        return 'MOTORING';
      case WeatherRouteLegKind.arrival:
        return 'ARRIVAL';
    }
  }
}

// ---------- helpers shared with the compose/result tabs ----------

const _cardinals = [
  'N', 'NNE', 'NE', 'ENE',
  'E', 'ESE', 'SE', 'SSE',
  'S', 'SSW', 'SW', 'WSW',
  'W', 'WNW', 'NW', 'NNW',
];

String _cardinal(double deg) {
  var d = deg % 360;
  if (d < 0) d += 360;
  final idx = ((d / 22.5) + 0.5).floor() % 16;
  return _cardinals[idx];
}

String _pointOfSail(double twaDeg) {
  final a = twaDeg.abs();
  if (a < 30) return 'in irons';
  if (a < 60) return 'close hauled';
  if (a < 85) return 'close reach';
  if (a < 100) return 'beam reach';
  if (a < 160) return 'broad reach';
  return 'downwind';
}

/// Returns 'fair', 'foul', or 'cross' based on the relative angle between
/// the course over ground and the current's SET (direction it's going,
/// which is how the server reports `current_dir_deg`).
String _currentRelation(double? cogDeg, double setDeg) {
  if (cogDeg == null) return 'cross';
  var rel = (setDeg - cogDeg) % 360;
  if (rel < 0) rel += 360;
  if (rel > 180) rel = 360 - rel;
  if (rel < 60) return 'fair';
  if (rel > 120) return 'foul';
  return 'cross';
}
