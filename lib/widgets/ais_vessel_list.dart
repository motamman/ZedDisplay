import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../models/ais_favorite.dart';
import '../models/cpa_alert_state.dart' show CpaAlertConfig, CpaVesselAlert;
import '../services/ais_favorites_service.dart';
import '../services/cpa_alert_service.dart';
import '../utils/date_time_formatter.dart';
import '../utils/ship_type_utils.dart' as ship_type;

// ---------------------------------------------------------------------------
// Shared AIS vessel-list view.
//
// Both `ais_polar_chart.dart` (the AIS Polar Chart tool) and the chart
// plotter's new "AIS list" button render through this widget. Each host
// supplies a precomputed `List<AisVesselListItem>` plus a few callbacks
// and unit-formatter closures; the widget itself owns no AIS state.
//
// File-level helpers (extractMmsi, formatTimeSince, vesselFreshnessColor,
// freshnessOpacity, isStale, cpaColor, formatTcpa, buildVesselIcon,
// computeCpa) were lifted out of the polar chart so non-list paths
// inside that file can import them too — same source of truth for the
// freshness palette, stale threshold, mooring-buoy icon, etc.
// ---------------------------------------------------------------------------

/// Data shape for one row in the AIS vessel list. The list widget reads
/// these directly — no host-specific types leak in. `mmsi` is the host's
/// vessel id (typically the SignalK URN `urn:mrn:imo:mmsi:…` or a bare
/// MMSI string); display logic strips the prefix via [extractMmsi].
class AisVesselListItem {
  final String mmsi;
  final String? name;
  final int? aisShipType;
  final String? aisClass;
  final String? aisStatus;
  final String? navState;
  final double? headingTrue;
  final double? cog;
  final double? sogRaw;
  /// Range to own vessel in meters. `null` means the host doesn't have
  /// a valid own-vessel fix yet — the row hides the distance cell and
  /// sorts to the bottom of the Nearby tab rather than showing `0.0`.
  final double? distance;
  final double? cpa;
  final double? tcpa;
  final DateTime? timestamp;

  const AisVesselListItem({
    required this.mmsi,
    this.name,
    this.aisShipType,
    this.aisClass,
    this.aisStatus,
    this.navState,
    this.headingTrue,
    this.cog,
    this.sogRaw,
    this.distance,
    this.cpa,
    this.tcpa,
    this.timestamp,
  });
}

// ===== File-level helpers (used by both tabs and by the polar chart) =====

/// Extract MMSI digits from a SignalK URN.
///
///   `urn:mrn:imo:mmsi:368346080` → `368346080`
///   `368346080`                  → `368346080` (passthrough)
String extractMmsi(String vesselId) {
  if (vesselId.contains(':')) {
    return vesselId.split(':').last;
  }
  return vesselId;
}

/// Short "5s" / "12m" / "2h" age label.
String formatTimeSince(DateTime timestamp) =>
    DateTimeFormatter.formatElapsedShort(timestamp);

/// Plain freshness palette (green → orange → red) by data age.
///
/// < 3 min: green · 3–10 min: orange · > 10 min: red.
Color vesselFreshnessColor(DateTime? timestamp) {
  if (timestamp == null) return Colors.red;
  final ageMinutes = DateTime.now().difference(timestamp).inMinutes;
  if (ageMinutes < 3) return Colors.green;
  if (ageMinutes < 10) return Colors.orange;
  return Colors.red;
}

/// Alpha for ship-type-coloured rows. When `aisStatus` comes from
/// `sk-ais-status-plugin` we trust the server's classification;
/// otherwise we fall back to a timestamp-driven decay so a stale row
/// fades toward transparent.
double freshnessOpacity(DateTime? timestamp, {String? aisStatus}) {
  if (aisStatus != null) {
    switch (aisStatus) {
      case 'confirmed':
        return 1.0;
      case 'unconfirmed':
        return 0.5;
      case 'lost':
        return 0.2;
      default:
        return 0.2;
    }
  }
  if (timestamp == null) return 0.2;
  final ageMinutes = DateTime.now().difference(timestamp).inMinutes;
  if (ageMinutes < 3) return 1.0;
  if (ageMinutes < 7) return 0.6;
  if (ageMinutes < 10) return 0.3;
  return 0.2;
}

/// Vessels older than [kStaleAfterMinutes] (or marked `lost` / `remove`
/// by the AIS-status plugin) are considered stale. Both hosts display
/// a red ✕ overlay on stale rows.
const int kStaleAfterMinutes = 10;
bool isStale(DateTime? timestamp, {String? aisStatus}) {
  if (aisStatus != null) {
    return aisStatus == 'lost' || aisStatus == 'remove';
  }
  if (timestamp == null) return true;
  return DateTime.now().difference(timestamp).inMinutes >= kStaleAfterMinutes;
}

/// CPA chip colour — red below alarm, orange below warn, else `defaultColor`.
Color cpaColor(
  double cpaMeters, {
  required double alarmThresholdMeters,
  required double warnThresholdMeters,
  Color defaultColor = Colors.white,
}) {
  if (cpaMeters < alarmThresholdMeters) return Colors.red;
  if (cpaMeters < warnThresholdMeters) return Colors.orange;
  return defaultColor;
}

/// Human-friendly TCPA: `45s` / `4.2m` / `1.5h`.
String formatTcpa(double tcpaSeconds) {
  if (tcpaSeconds < 60) return '${tcpaSeconds.toStringAsFixed(0)}s';
  if (tcpaSeconds < 3600) {
    return '${(tcpaSeconds / 60).toStringAsFixed(1)}m';
  }
  return '${(tcpaSeconds / 3600).toStringAsFixed(1)}h';
}

/// Mooring-buoy SVG template — `TYPE_COLOR` is swapped for the row's
/// type-coloured fill at render time.
const String _mooringBuoySvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'
    '<defs><clipPath id="c"><circle cx="50" cy="50" r="45"/></clipPath></defs>'
    '<circle cx="50" cy="50" r="45" fill="TYPE_COLOR" stroke="#888" stroke-width="1.5"/>'
    '<rect x="0" y="38" width="100" height="24" fill="#1565C0" clip-path="url(#c)"/>'
    '<circle cx="50" cy="50" r="45" fill="none" stroke="#666" stroke-width="1"/>'
    '</svg>';

/// Row leading icon: mooring buoy SVG when navState is `moored`,
/// otherwise the ship-type Material icon from `ship_type_utils`.
Widget buildVesselIcon({
  required int? aisShipType,
  required String? navState,
  double? sogRaw,
  required Color color,
  required double size,
  List<Shadow>? shadows,
}) {
  if (navState == 'moored') {
    final hex =
        '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
    final svg = _mooringBuoySvg.replaceAll('TYPE_COLOR', hex);
    return SvgPicture.string(svg, width: size, height: size);
  }
  final icon = ship_type.shipTypeIcon(aisShipType, navState, sogMs: sogRaw);
  return Icon(icon, color: color, size: size, shadows: shadows);
}

/// CPA / TCPA from two vessels' kinematics, all in SI units. Returns
/// `null` when the closing speed is zero (parallel courses) or any
/// required input is missing. TCPA can be negative (CPA already
/// passed); callers decide whether to surface or hide.
({double cpaM, double tcpaS})? computeCpa({
  required double? ownLat,
  required double? ownLon,
  required double? ownCogRad,
  required double? ownSogMs,
  required double? otherLat,
  required double? otherLon,
  required double? otherCogRad,
  required double? otherSogMs,
}) {
  if (ownLat == null || ownLon == null || ownCogRad == null || ownSogMs == null) {
    return null;
  }
  if (otherLat == null ||
      otherLon == null ||
      otherCogRad == null ||
      otherSogMs == null) {
    return null;
  }
  // Local tangent-plane approximation around the own vessel — fine for
  // the ~nm ranges AIS traffic lives at. North is +y, East is +x.
  const earthR = 6371000.0;
  final lat0 = ownLat * math.pi / 180;
  final dxOther = (otherLon - ownLon) * math.pi / 180 * earthR * math.cos(lat0);
  final dyOther = (otherLat - ownLat) * math.pi / 180 * earthR;

  // Velocity in tangent plane: vx = sog * sin(cog), vy = sog * cos(cog).
  final ownVx = ownSogMs * math.sin(ownCogRad);
  final ownVy = ownSogMs * math.cos(ownCogRad);
  final otherVx = otherSogMs * math.sin(otherCogRad);
  final otherVy = otherSogMs * math.cos(otherCogRad);

  // Relative position / velocity (other → own frame).
  final rx = dxOther;
  final ry = dyOther;
  final vx = otherVx - ownVx;
  final vy = otherVy - ownVy;
  final v2 = vx * vx + vy * vy;
  if (v2 < 1e-6) return null; // parallel and equal speed → no closing.

  // tcpa minimises |r + v*t|² → tcpa = -(r·v)/|v|².
  final tcpa = -(rx * vx + ry * vy) / v2;
  final cpaX = rx + vx * tcpa;
  final cpaY = ry + vy * tcpa;
  final cpa = math.sqrt(cpaX * cpaX + cpaY * cpaY);
  return (cpaM: cpa, tcpaS: tcpa);
}

// ===== The widget =====

/// Tabbed AIS vessel list — Nearby and Favorites.
///
/// Pure renderer over caller-supplied data. The host owns sourcing
/// vessels, computing distance / CPA, and providing unit formatters;
/// this widget owns layout, tab state, the freshness palette, and the
/// favorites-tab management UI (add / remove / clear-all).
class AisVesselList extends StatefulWidget {
  const AisVesselList({
    super.key,
    required this.vessels,
    required this.lastPositionUpdate,
    required this.cpaAlertService,
    required this.colorByShipType,
    required this.formatDistance,
    required this.formatSpeed,
    required this.formatAngleSymbol,
    required this.onTap,
    required this.onLongPress,
  });

  /// Vessel rows for the Nearby tab. Already sorted by the host (or
  /// the widget will sort by ascending [AisVesselListItem.distance]
  /// internally — see build).
  final List<AisVesselListItem> vessels;

  /// "Last update: 5s ago" text in the Nearby header. Null hides it.
  final DateTime? lastPositionUpdate;

  /// Drives the alert-row tint, the dismiss-on-swipe action, and the
  /// header's Clear-All button. Null disables those features.
  final CpaAlertService? cpaAlertService;

  /// When true, leading icons use [ship_type.shipTypeColor]; when
  /// false, they use [vesselFreshnessColor] directly.
  final bool colorByShipType;

  /// Host-supplied formatters. Distance in meters; speed in m/s;
  /// angle symbol returned verbatim. Keeps the widget agnostic of
  /// whichever MetadataStore wiring the host uses.
  ///
  /// `formatDistance` accepts an optional `decimals` so the CPA chip
  /// can use a tighter precision (2dp) than the row subtitle (1dp).
  final String Function(double meters, {int decimals}) formatDistance;
  final String Function(double metersPerSecond) formatSpeed;
  final String Function() formatAngleSymbol;

  /// Called when the user taps a Nearby row, or a Favorites row that
  /// matches a currently-visible vessel. The `mmsi` is the host's
  /// vessel id (URN or bare MMSI), suitable for re-keying state.
  final void Function(String mmsi) onTap;

  /// Long-press on either tab. The `displayName` is `name` if known,
  /// else the bare MMSI digits.
  final void Function(String mmsi, String displayName) onLongPress;

  @override
  State<AisVesselList> createState() => _AisVesselListState();
}

class _AisVesselListState extends State<AisVesselList> {
  int _tabIndex = 0; // 0 = Nearby, 1 = Favorites

  @override
  Widget build(BuildContext context) {
    // Listen to the CPA alert service (when supplied) so a Dismissible
    // swipe — which calls `dismissAlert` — actually rebuilds the list.
    // Without this the dismissed Dismissible stays in the tree and
    // Flutter trips its "still part of the tree" assertion.
    final alertService = widget.cpaAlertService;
    if (alertService == null) return _buildBody(context);
    return ListenableBuilder(
      listenable: alertService,
      builder: (innerCtx, _) => _buildBody(innerCtx),
    );
  }

  Widget _buildBody(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 8, right: 8),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Nearby', style: TextStyle(fontSize: 12)),
                  selected: _tabIndex == 0,
                  onSelected: (_) => setState(() => _tabIndex = 0),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label:
                      const Text('Favorites', style: TextStyle(fontSize: 12)),
                  selected: _tabIndex == 1,
                  onSelected: (_) => setState(() => _tabIndex = 1),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
          Expanded(
            child: _tabIndex == 0
                ? _buildNearby(context, isDark)
                : _buildFavorites(context, isDark),
          ),
        ],
      ),
    );
  }

  // ===== Nearby tab =====

  Widget _buildNearby(BuildContext context, bool isDark) {
    if (widget.vessels.isEmpty) {
      return Center(
        child: Text(
          'No vessels in range',
          style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
        ),
      );
    }

    // Watch favorites so a star toggle from the detail sheet reflows
    // tinting / counts on this list too.
    context.watch<AISFavoritesService>();

    // Null distance (host has no own-vessel fix) sorts to the bottom.
    final sorted = List<AisVesselListItem>.from(widget.vessels)
      ..sort((a, b) {
        final ad = a.distance;
        final bd = b.distance;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      });

    String lastUpdateText = 'No data';
    final ts = widget.lastPositionUpdate;
    if (ts != null) {
      final elapsed = DateTime.now().difference(ts);
      if (elapsed.inSeconds < 60) {
        lastUpdateText = '${elapsed.inSeconds}s ago';
      } else if (elapsed.inMinutes < 60) {
        lastUpdateText = '${elapsed.inMinutes}m ago';
      } else {
        lastUpdateText = '${elapsed.inHours}h ago';
      }
    }

    final Map<String, CpaVesselAlert> alerts =
        widget.cpaAlertService?.vesselAlerts ??
            const <String, CpaVesselAlert>{};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding:
              const EdgeInsets.only(top: 4, bottom: 4, left: 12, right: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Last update: $lastUpdateText',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ),
              if (widget.cpaAlertService != null && alerts.isNotEmpty)
                SizedBox(
                  height: 24,
                  child: TextButton.icon(
                    onPressed: () =>
                        widget.cpaAlertService!.dismissAllAlerts(),
                    icon: Icon(
                      Icons.delete_outline,
                      size: 14,
                      color: isDark ? Colors.white60 : Colors.black45,
                    ),
                    label: Text(
                      'Clear All',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white60 : Colors.black45,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: sorted.length,
            itemBuilder: (context, index) =>
                _buildNearbyRow(context, isDark, sorted[index], alerts),
          ),
        ),
      ],
    );
  }

  Widget _buildNearbyRow(
    BuildContext context,
    bool isDark,
    AisVesselListItem vessel,
    Map<String, CpaVesselAlert> alerts,
  ) {
    final cpa = vessel.cpa;
    final tcpa = vessel.tcpa;

    final typeColor = widget.colorByShipType
        ? ship_type.shipTypeColor(vessel.aisShipType,
            aisClass: vessel.aisClass)
        : vesselFreshnessColor(vessel.timestamp);
    final opacity = widget.colorByShipType
        ? freshnessOpacity(vessel.timestamp, aisStatus: vessel.aisStatus)
        : 1.0;
    final displayColor = typeColor.withValues(alpha: opacity);
    final stale = isStale(vessel.timestamp, aisStatus: vessel.aisStatus);

    final iconWidget = Transform.rotate(
      angle: (vessel.headingTrue ?? vessel.cog ?? 0.0) * math.pi / 180,
      child: buildVesselIcon(
        aisShipType: vessel.aisShipType,
        navState: vessel.navState,
        sogRaw: vessel.sogRaw,
        color: displayColor,
        size: 20,
      ),
    );

    // `vesselAlerts` keys by the same id the host hands us; the polar
    // chart and chart plotter agree on URN-or-bare strings.
    final hasAlert = alerts.containsKey(vessel.mmsi);

    final tile = ListTile(
      dense: true,
      onTap: () => widget.onTap(vessel.mmsi),
      onLongPress: () =>
          widget.onLongPress(vessel.mmsi, vessel.name ?? extractMmsi(vessel.mmsi)),
      leading: stale
          ? Stack(
              alignment: Alignment.center,
              children: [
                iconWidget,
                const Icon(Icons.close, color: Colors.red, size: 16),
              ],
            )
          : iconWidget,
      title: Row(
        children: [
          Expanded(
            child: Text(
              vessel.name ?? extractMmsi(vessel.mmsi),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: displayColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (vessel.timestamp != null)
            Text(
              formatTimeSince(vessel.timestamp!),
              style: TextStyle(
                fontSize: 10,
                color: typeColor.withValues(alpha: opacity * 0.7),
              ),
            ),
        ],
      ),
      subtitle: Row(
        children: [
          if (vessel.distance != null) ...[
            Text(
              widget.formatDistance(vessel.distance!, decimals: 1),
              style: const TextStyle(fontSize: 11),
            ),
            const SizedBox(width: 8),
          ],
          if (vessel.cog != null)
            Text(
              'COG ${vessel.cog!.toStringAsFixed(0)}${widget.formatAngleSymbol()}',
              style: const TextStyle(fontSize: 11),
            ),
          const SizedBox(width: 8),
          if (vessel.sogRaw != null)
            Text(
              'SOG ${widget.formatSpeed(vessel.sogRaw!)}',
              style: const TextStyle(fontSize: 11),
            ),
        ],
      ),
      trailing: cpa != null ? _buildCpaChip(cpa, tcpa) : null,
    );

    if (!hasAlert) return tile;

    return Dismissible(
      key: Key('cpa_dismiss_${vessel.mmsi}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        widget.cpaAlertService?.dismissAlert(vessel.mmsi);
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: Colors.red.shade700,
        child: const Icon(Icons.delete, color: Colors.white, size: 20),
      ),
      child: tile,
    );
  }

  Widget _buildCpaChip(double cpa, double? tcpa) {
    // Fall back to permissive thresholds if no CPA service is wired —
    // chip stays neutral white instead of misleading red.
    final config = widget.cpaAlertService?.config ?? const CpaAlertConfig();
    final color = cpaColor(
      cpa,
      alarmThresholdMeters: config.alarmThresholdMeters,
      warnThresholdMeters: config.warnThresholdMeters,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'CPA ${widget.formatDistance(cpa, decimals: 2)}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          if (tcpa != null && tcpa.isFinite && tcpa > 0)
            Text(
              'TCPA ${formatTcpa(tcpa)}',
              style: TextStyle(fontSize: 10, color: color),
            ),
        ],
      ),
    );
  }

  // ===== Favorites tab =====

  Widget _buildFavorites(BuildContext context, bool isDark) {
    final favService = context.watch<AISFavoritesService>();
    final favorites = favService.favorites;

    // Cache the in-range lookup once per build so the per-row check
    // is O(1). Key is the bare MMSI digits (matches `AISFavorite.mmsi`).
    final byMmsi = <String, AisVesselListItem>{};
    for (final v in widget.vessels) {
      byMmsi[extractMmsi(v.mmsi)] = v;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding:
              const EdgeInsets.only(top: 4, bottom: 4, left: 12, right: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${favorites.length} favorite${favorites.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ),
              SizedBox(
                height: 24,
                child: TextButton.icon(
                  onPressed: () => _showManualAddFavoriteDialog(context),
                  icon: Icon(
                    Icons.add,
                    size: 14,
                    color: isDark ? Colors.white60 : Colors.black45,
                  ),
                  label: Text(
                    'Add',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white60 : Colors.black45,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
              if (favorites.isNotEmpty)
                SizedBox(
                  height: 24,
                  child: TextButton.icon(
                    onPressed: () => favService.clearAll(),
                    icon: Icon(
                      Icons.delete_outline,
                      size: 14,
                      color: isDark ? Colors.white60 : Colors.black45,
                    ),
                    label: Text(
                      'Clear All',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white60 : Colors.black45,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: favorites.isEmpty
              ? Center(
                  child: Text(
                    'No favorites yet',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: favorites.length,
                  itemBuilder: (context, index) {
                    final fav = favorites[index];
                    final inRangeVessel = byMmsi[fav.mmsi];
                    return _buildFavoriteRow(
                      context: context,
                      isDark: isDark,
                      fav: fav,
                      inRangeVessel: inRangeVessel,
                      favService: favService,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFavoriteRow({
    required BuildContext context,
    required bool isDark,
    required AISFavorite fav,
    required AisVesselListItem? inRangeVessel,
    required AISFavoritesService favService,
  }) {
    final inRange = inRangeVessel != null;
    return ListTile(
      dense: true,
      onLongPress: inRange
          ? () => widget.onLongPress(inRangeVessel.mmsi, fav.name)
          : null,
      onTap: () {
        if (inRange) {
          widget.onTap(inRangeVessel.mmsi);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Not in range'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      },
      leading: const Icon(Icons.favorite, size: 18, color: Colors.red),
      title: Row(
        children: [
          Expanded(
            child: Text(
              fav.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: inRange
                    ? (isDark ? Colors.white : Colors.black87)
                    : (isDark ? Colors.white38 : Colors.black38),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      subtitle: Row(
        children: [
          Text(
            fav.mmsi,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
          if (fav.notes != null && fav.notes!.isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                fav.notes!,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white38 : Colors.black38,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (inRange) ...[
            if (inRangeVessel.distance != null) ...[
              const SizedBox(width: 8),
              Text(
                widget.formatDistance(inRangeVessel.distance!, decimals: 1),
                style: const TextStyle(fontSize: 11),
              ),
            ],
            if (inRangeVessel.sogRaw != null) ...[
              const SizedBox(width: 6),
              Text(
                'SOG ${widget.formatSpeed(inRangeVessel.sogRaw!)}',
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ],
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!inRange)
            Text(
              'Not in range',
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () => favService.removeFavorite(fav.mmsi),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  // ===== Manual "Add favorite" dialog =====
  //
  // Lifted verbatim from `ais_polar_chart._showManualAddFavoriteDialog`
  // — fully self-contained (no host state) so it stays here with the
  // favorites tab that uses it.
  void _showManualAddFavoriteDialog(BuildContext outerContext) {
    final mmsiController = TextEditingController();
    final nameController = TextEditingController();
    final notesController = TextEditingController();
    String? mmsiError;
    String? nameError;

    showDialog(
      context: outerContext,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Favorite Vessel'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: mmsiController,
                    decoration: InputDecoration(
                      labelText: 'MMSI (9 digits)',
                      errorText: mmsiError,
                    ),
                    keyboardType: TextInputType.number,
                    maxLength: 9,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: 'Vessel Name',
                      errorText: nameError,
                    ),
                    onChanged: (_) {
                      if (nameError != null) {
                        setDialogState(() => nameError = null);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    final mmsi = mmsiController.text.trim();
                    final name = nameController.text.trim();
                    if (!RegExp(r'^\d{9}$').hasMatch(mmsi)) {
                      setDialogState(() {
                        mmsiError = 'Must be exactly 9 digits';
                        nameError = null;
                      });
                      return;
                    }
                    if (name.isEmpty) {
                      setDialogState(() {
                        mmsiError = null;
                        nameError = 'Required';
                      });
                      return;
                    }
                    final favService =
                        outerContext.read<AISFavoritesService>();
                    favService.addFavorite(
                      AISFavorite(
                        mmsi: mmsi,
                        name: name,
                        notes: notesController.text.trim().isEmpty
                            ? null
                            : notesController.text.trim(),
                      ),
                    );
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
