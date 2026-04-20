import 'package:flutter/material.dart';
import '../../config/app_colors.dart';
import '../../services/signalk_service.dart';
import '../../utils/cpa_utils.dart';

/// Route state passed from chart plotter tool to the route panel.
class ChartRouteState {
  final List<List<double>>? routeCoords;
  final List<String>? waypointNames;
  final int? routePointIndex;
  final int? routePointTotal;
  final String? activeRouteId;

  const ChartRouteState({
    this.routeCoords,
    this.waypointNames,
    this.routePointIndex,
    this.routePointTotal,
    this.activeRouteId,
  });

  bool get hasActiveRoute => routeCoords != null;
}

/// Callbacks for route actions.
class ChartRouteCallbacks {
  final Future<void> Function(String routeId, {bool reverse}) activateRoute;
  final Future<void> Function() reverseRoute;
  final Future<void> Function() clearCourse;
  final Future<void> Function(int pointIndex) skipToWaypoint;
  final VoidCallback showRouteManager; // refresh after edit/delete
  final void Function(int index, double lon, double lat)? onWaypointDrag;
  final void Function(int index, String name)? onWaypointRenamed;
  final void Function(int index)? onWaypointDeleted;
  final void Function(int afterIndex, double lon, double lat, String name)? onWaypointAdded;
  final Future<void> Function()? saveRouteToServer;

  const ChartRouteCallbacks({
    required this.activateRoute,
    required this.reverseRoute,
    required this.clearCourse,
    required this.skipToWaypoint,
    required this.showRouteManager,
    this.onWaypointDrag,
    this.onWaypointRenamed,
    this.onWaypointDeleted,
    this.onWaypointAdded,
    this.saveRouteToServer,
  });
}

/// Shows the route manager bottom sheet.
///
/// If a route is active, shows the active route panel with waypoint list.
/// Otherwise, shows the list of available routes from the server.
void showRouteManagerSheet(
  BuildContext context, {
  required SignalKService signalKService,
  required ChartRouteState routeState,
  required ChartRouteCallbacks callbacks,
  required List<String> navPaths, // [pos, hdg, cog, sog, depth, brg, xte, dtw]
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => DraggableScrollableSheet(
      initialChildSize: 0.45,
      maxChildSize: 0.7,
      minChildSize: 0.2,
      snap: true,
      snapSizes: const [0.2, 0.45],
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.cardBackgroundDark,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: routeState.hasActiveRoute
            ? _ActiveRoutePanel(
                signalKService: signalKService,
                routeState: routeState,
                callbacks: callbacks,
                navPaths: navPaths,
                sheetCtx: sheetCtx,
                scrollController: scrollController,
              )
            : _RouteListPanel(
                signalKService: signalKService,
                callbacks: callbacks,
                sheetCtx: sheetCtx,
                scrollController: scrollController,
              ),
      ),
    ),
  );
}

/// Shows the waypoint edit dialog (rename or delete).
void showWaypointEditDialog(
  BuildContext context, {
  required int index,
  required List<List<double>>? routeCoords,
  required List<String>? waypointNames,
  required VoidCallback onChanged,
  required Future<void> Function()? saveRouteToServer,
}) {
  if (routeCoords == null || index < 0 || index >= routeCoords.length) return;
  final currentName = (waypointNames != null && index < waypointNames.length)
      ? waypointNames[index]
      : '';
  final controller = TextEditingController(text: currentName);
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.cardBackgroundDark,
      title: Text('Waypoint ${index + 1}', style: const TextStyle(color: Colors.white)),
      content: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          hintText: 'Waypoint name',
          hintStyle: TextStyle(color: Colors.white38),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.green)),
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(ctx);
            routeCoords.removeAt(index);
            waypointNames?.removeAt(index);
            onChanged();
            saveRouteToServer?.call();
          },
          child: const Text('Delete Waypoint', style: TextStyle(color: Colors.red)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(ctx);
            if (waypointNames != null && index < waypointNames.length) {
              waypointNames[index] = controller.text;
            }
            saveRouteToServer?.call();
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

/// Shows the add waypoint dialog.
void showAddWaypointDialog(
  BuildContext context, {
  required int afterIndex,
  required double lon,
  required double lat,
  required List<List<double>>? routeCoords,
  required List<String>? waypointNames,
  required VoidCallback onChanged,
  required Future<void> Function()? saveRouteToServer,
}) {
  if (routeCoords == null) return;
  final controller = TextEditingController();
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.cardBackgroundDark,
      title: const Text('Add Waypoint', style: TextStyle(color: Colors.white)),
      content: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          hintText: 'Waypoint name (optional)',
          hintStyle: TextStyle(color: Colors.white38),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.green)),
        ),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(ctx);
            final insertAt = afterIndex + 1;
            routeCoords.insert(insertAt, [lon, lat]);
            waypointNames?.insert(insertAt, controller.text);
            onChanged();
            saveRouteToServer?.call();
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Route list (no active route)
// ---------------------------------------------------------------------------

class _RouteListPanel extends StatelessWidget {
  final SignalKService signalKService;
  final ChartRouteCallbacks callbacks;
  final BuildContext sheetCtx;
  final ScrollController scrollController;

  const _RouteListPanel({
    required this.signalKService,
    required this.callbacks,
    required this.sheetCtx,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: signalKService.getResources('routes'),
      builder: (context, snapshot) {
        final routes = snapshot.data;
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            Center(child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
            )),
            const Text('Routes', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (!snapshot.hasData)
              const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ))
            else if (routes == null || routes.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No routes on server', style: TextStyle(color: Colors.white54)),
              )
            else
              ...routes.entries.map((entry) {
                final id = entry.key;
                final data = entry.value as Map<String, dynamic>;
                final name = data['name'] as String? ?? id;
                final desc = data['description'] as String?;
                final distM = data['distance'] as num?;
                final distMeta = signalKService.metadataStore.getByCategory('distance');
                final distStr = distM != null
                    ? '${(distMeta?.convert(distM.toDouble()) ?? distM).toStringAsFixed(1)} ${distMeta?.symbol ?? 'm'}'
                    : null;
                final feature = data['feature'] as Map?;
                final coords = (feature?['geometry'] as Map?)?['coordinates'] as List?;
                final wptCount = coords?.length ?? 0;

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.route, color: Colors.white54),
                  title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    [if (distStr != null) distStr, '$wptCount waypoints', if (desc != null) desc] // ignore: use_null_aware_elements
                        .join(' · '),
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Transform.flip(
                          flipX: true,
                          child: const Icon(Icons.play_arrow, color: Colors.red, size: 22),
                        ),
                        tooltip: 'Activate reversed',
                        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                        onPressed: () {
                          Navigator.of(sheetCtx).pop();
                          callbacks.activateRoute(id, reverse: true);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.play_arrow, color: Colors.green, size: 22),
                        tooltip: 'Activate forward',
                        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                        onPressed: () {
                          Navigator.of(sheetCtx).pop();
                          callbacks.activateRoute(id);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.white38, size: 18),
                        tooltip: 'Edit route',
                        constraints: const BoxConstraints.tightFor(width: 32, height: 36),
                        onPressed: () => _showEditDialog(context, sheetCtx, id, name, data),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 18),
                        tooltip: 'Delete route',
                        constraints: const BoxConstraints.tightFor(width: 32, height: 36),
                        onPressed: () => _showDeleteDialog(context, sheetCtx, id, name),
                      ),
                    ],
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  void _showEditDialog(BuildContext context, BuildContext sheetCtx, String routeId, String currentName, Map<String, dynamic> routeData) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackgroundDark,
        title: const Text('Rename Route', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Route name',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.green)),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(sheetCtx);
              Navigator.pop(ctx);
              routeData['name'] = controller.text;
              await signalKService.putResource('routes', routeId, routeData);
              nav.pop();
              callbacks.showRouteManager();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, BuildContext sheetCtx, String routeId, String name) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackgroundDark,
        title: const Text('Delete Route', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete "$name"?\n\nThis cannot be undone.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final nav = Navigator.of(sheetCtx);
              Navigator.pop(ctx);
              await signalKService.deleteResource('routes', routeId);
              nav.pop();
              callbacks.showRouteManager();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Active route panel
// ---------------------------------------------------------------------------

class _ActiveRoutePanel extends StatelessWidget {
  final SignalKService signalKService;
  final ChartRouteState routeState;
  final ChartRouteCallbacks callbacks;
  final List<String> navPaths;
  final BuildContext sheetCtx;
  final ScrollController scrollController;

  // Path indices matching chart_plotter_tool.dart order
  static const _dsCog = 2;
  static const _dsBearing = 5;
  static const _dsXte = 6;
  static const _dsDtw = 7;

  String _path(int index) => index < navPaths.length ? navPaths[index] : '';

  const _ActiveRoutePanel({
    required this.signalKService,
    required this.routeState,
    required this.callbacks,
    required this.navPaths,
    required this.sheetCtx,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Center(child: Container(
          width: 40, height: 4,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: Colors.grey[600], borderRadius: BorderRadius.circular(2)),
        )),
        Row(children: [
          const Icon(Icons.route, color: Colors.green, size: 24),
          const SizedBox(width: 8),
          const Expanded(child: Text('Active Route',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
          IconButton(
            icon: const Icon(Icons.swap_horiz, color: Colors.orange),
            tooltip: 'Reverse route',
            onPressed: () {
              Navigator.of(sheetCtx).pop();
              callbacks.reverseRoute();
            },
          ),
          IconButton(
            icon: const Icon(Icons.stop_circle_outlined, color: Colors.red),
            tooltip: 'Deactivate route',
            onPressed: () {
              Navigator.of(sheetCtx).pop();
              callbacks.clearCourse();
            },
          ),
        ]),
        const SizedBox(height: 4),
        Text(
          'Waypoint ${(routeState.routePointIndex ?? 0) + 1} of ${routeState.routePointTotal ?? routeState.routeCoords?.length ?? 0}',
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
        // DTW / BRG / XTE
        Builder(builder: (_) {
          final store = signalKService.metadataStore;
          final distMeta = store.get(_path(_dsDtw)) ?? store.getByCategory('distance');
          final brgMeta = store.get(_path(_dsBearing)) ?? store.get(_path(_dsCog));
          final xteMeta = store.get(_path(_dsXte)) ?? store.getByCategory('distance');

          String fmt(String path, dynamic meta, {int dec = 1}) {
            final d = signalKService.getValue(path);
            if (d?.value == null || d!.value is! num) return '--';
            final raw = (d.value as num).toDouble();
            if (meta != null) return meta.format(raw, decimals: dec) as String;
            return raw.toStringAsFixed(dec);
          }

          return Row(children: [
            Text('DTW: ${fmt(_path(_dsDtw), distMeta)}',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(width: 16),
            Text('BRG: ${fmt(_path(_dsBearing), brgMeta, dec: 0)}',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(width: 16),
            Text('XTE: ${fmt(_path(_dsXte), xteMeta)}',
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ]);
        }),
        const Divider(color: Colors.white24, height: 20),
        // Waypoint list
        if (routeState.routeCoords != null)
          ...List.generate(routeState.routeCoords!.length, (i) {
            final isActive = i == routeState.routePointIndex;
            final isPast = routeState.routePointIndex != null && i < routeState.routePointIndex!;
            final name = (routeState.waypointNames != null && i < routeState.waypointNames!.length && routeState.waypointNames![i].isNotEmpty)
                ? routeState.waypointNames![i]
                : 'WPT ${i + 1}';
            String? legDist;
            if (i > 0) {
              final distMeta = signalKService.metadataStore.getByCategory('distance');
              final prev = routeState.routeCoords![i - 1];
              final cur = routeState.routeCoords![i];
              final m = CpaUtils.calculateDistance(prev[1], prev[0], cur[1], cur[0]);
              final v = distMeta?.convert(m) ?? m;
              legDist = '${v.toStringAsFixed(1)} ${distMeta?.symbol ?? 'm'}';
            }
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                isActive ? Icons.flag : isPast ? Icons.check_circle : Icons.circle_outlined,
                color: isActive ? Colors.green : isPast ? Colors.white24 : Colors.white54,
                size: 20,
              ),
              title: Text(name, style: TextStyle(
                color: isActive ? Colors.green : isPast ? Colors.white38 : Colors.white,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              )),
              subtitle: legDist != null
                  ? Text(legDist, style: TextStyle(
                      color: isPast ? Colors.white24 : Colors.white38, fontSize: 11))
                  : null,
              trailing: !isPast && !isActive && routeState.routePointIndex != null && i > routeState.routePointIndex!
                  ? IconButton(
                      icon: const Icon(Icons.near_me, size: 18, color: Colors.white54),
                      tooltip: 'Skip to this waypoint',
                      onPressed: () => callbacks.skipToWaypoint(i),
                    )
                  : null,
            );
          }),
      ],
    );
  }
}
