import 'package:flutter/material.dart';

import '../../models/weather_route_result.dart';
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
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final WeatherRouteWaypoint waypoint;
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
                        _grid(),
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

  Widget _grid() {
    final kvs = <(String, String, Color?)>[];

    // Speed Over Ground — knots.
    if (waypoint.sogMs != null) {
      kvs.add(('SOG', '${(waypoint.sogMs! / _msPerKt).toStringAsFixed(1)} kt', null));
    }
    // Course Over Ground.
    if (waypoint.cogDeg != null) {
      kvs.add(('COG',
          '${_cardinal(waypoint.cogDeg!)} ${waypoint.cogDeg!.round()}°', null));
    }
    // Wind.
    if (waypoint.windMs != null && waypoint.windDirDeg != null) {
      final spd = (waypoint.windMs! / _msPerKt).round();
      final dir = waypoint.windDirDeg!.round();
      final pos = waypoint.twaDeg != null
          ? ' · ${_pointOfSail(waypoint.twaDeg!)}'
          : '';
      kvs.add(('Wind',
          '$spd kt from ${_cardinal(waypoint.windDirDeg!)} ($dir°)$pos',
          null));
    }
    // TWA.
    if (waypoint.twaDeg != null) {
      kvs.add(('TWA', '${waypoint.twaDeg!.round()}°', null));
    }
    // Current (only when > 0.05 m/s ≈ 0.1 kt, matching the web UI).
    if (waypoint.currentMs != null &&
        waypoint.currentMs! > 0.05 &&
        waypoint.currentDirDeg != null) {
      final setDir = waypoint.currentDirDeg!;
      final cardinal = _cardinal(setDir);
      final spd = (waypoint.currentMs! / _msPerKt).toStringAsFixed(2);
      final relation = _currentRelation(waypoint.cogDeg, setDir);
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
          '$spd kt from $cardinal (${setDir.round()}°) · $relation',
          colour));
    }
    // Waves.
    if (waypoint.swhM != null) {
      final parts = <String>['${waypoint.swhM!.toStringAsFixed(1)} m'];
      if (waypoint.mwpS != null) {
        parts.add('${waypoint.mwpS!.round()} s');
      }
      if (waypoint.mwdDeg != null) {
        parts.add('from ${_cardinal(waypoint.mwdDeg!)} ${waypoint.mwdDeg!.round()}°');
      }
      kvs.add(('Waves', parts.join(' · '), null));
    }
    // Depth.
    if (waypoint.depthM != null) {
      kvs.add(('Depth', '${waypoint.depthM!.toStringAsFixed(1)} m', null));
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

const double _msPerKt = 0.51444;
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

/// Shared utility exposed to the result tab so its stat summary can reuse
/// the same unit conversion as the cards.
double msToKt(double ms) => ms / _msPerKt;
const double metersPerNm = 1852.0;
