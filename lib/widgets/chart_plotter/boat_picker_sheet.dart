import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_colors.dart';
import '../../models/boat.dart';
import '../../models/path_metadata.dart';
import '../../models/polar_entry.dart';
import '../../services/route_planner_boats_service.dart';
import '../../services/signalk_service.dart';
import 'boat_editor_sheet.dart';
import 'sailboatdata_search_sheet.dart';

/// Boat picker. Lists the caller's saved boats, offers add-via-search
/// or add-blank, and surfaces swipe-to-delete. Tap a row to select it
/// and pop the sheet.
Future<void> showBoatPickerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.cardBackgroundDark,
    isScrollControlled: true,
    builder: (ctx) => const _BoatPickerSheet(),
  );
}

class _BoatPickerSheet extends StatefulWidget {
  const _BoatPickerSheet();

  @override
  State<_BoatPickerSheet> createState() => _BoatPickerSheetState();
}

class _BoatPickerSheetState extends State<_BoatPickerSheet> {
  bool _refreshed = false;
  final TextEditingController _filterCtrl = TextEditingController();
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _filterCtrl.addListener(() {
      final next = _filterCtrl.text.trim().toLowerCase();
      if (next == _filter) return;
      setState(() => _filter = next);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_refreshed && mounted) {
        _refreshed = true;
        // Full server inventory + the caller's ownership oracle in
        // parallel. The list renders every boat; edit/delete only
        // surface on rows the caller owns.
        context.read<RoutePlannerBoatsService>().refreshAllBoats();
      }
    });
  }

  @override
  void dispose() {
    _filterCtrl.dispose();
    super.dispose();
  }

  Future<void> _addFromSearch() async {
    final saved = await showSailboatdataSearchSheet(context);
    if (!mounted || saved == null) return;
    context.read<RoutePlannerBoatsService>().setSelectedBoat(saved);
    Navigator.of(context).pop();
  }

  Future<void> _addBlank() async {
    final saved = await showBoatEditorSheet(context);
    if (!mounted || saved == null) return;
    context.read<RoutePlannerBoatsService>().setSelectedBoat(saved);
    Navigator.of(context).pop();
  }

  Future<void> _edit(Boat boat) async {
    final saved = await showBoatEditorSheet(context, existing: boat);
    if (!mounted || saved == null) return;
    // Editing doesn't change selection unless user picks this boat.
  }

  Future<bool> _confirmDelete(Boat boat) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBackgroundDark,
        title: Text('Delete "${boat.name}"?',
            style: const TextStyle(color: Colors.white)),
        content: const Text(
          'This removes the boat profile from the route planner. '
          'Its polar file is not deleted.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<RoutePlannerBoatsService>();
    final lengthMd = context
        .read<SignalKService>()
        .metadataStore
        .getWithFallback('design.length', (_) => 'length');
    final maxH = MediaQuery.sizeOf(context).height * 0.85;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  const Icon(Icons.directions_boat, color: Colors.white70),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Boats',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.white70),
                    tooltip: 'Refresh',
                    onPressed: svc.loadingBoats
                        ? null
                        : () => svc.refreshAllBoats(),
                  ),
                ],
              ),
            ),
            if (svc.lastError != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  svc.lastError!,
                  style: const TextStyle(color: Color(0xFFFF8888)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: TextField(
                controller: _filterCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Filter boats and polars',
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(Icons.search,
                      color: Colors.white54, size: 18),
                  suffixIcon: _filter.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close,
                              color: Colors.white54, size: 16),
                          onPressed: () => _filterCtrl.clear(),
                          tooltip: 'Clear filter',
                          visualDensity: VisualDensity.compact,
                        ),
                  filled: true,
                  fillColor: const Color(0xFF14142A),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Flexible(child: _list(svc, lengthMd)),
            const Divider(color: Colors.white12, height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              child: Column(
                children: [
                  // Primary: blank editor.
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add boat'),
                      onPressed: _addBlank,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Fallback: prefill from sailboatdata.
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.search, size: 16),
                      label: const Text('Find on sailboatdata…'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white54,
                      ),
                      onPressed: _addFromSearch,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(RoutePlannerBoatsService svc, PathMetadata? lengthMd) {
    if (svc.loadingBoats && svc.boats.isEmpty && svc.polars.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final allSaved = svc.boats;
    final allOrphans = svc.orphanedPolars;
    final savedBoats =
        _filter.isEmpty ? allSaved : allSaved.where(_boatMatches).toList();
    final orphans = _filter.isEmpty
        ? allOrphans
        : allOrphans.where(_polarMatches).toList();
    if (allSaved.isEmpty && allOrphans.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No boats or polars available.',
          style: TextStyle(color: Colors.white54),
          textAlign: TextAlign.center,
        ),
      );
    }
    if (savedBoats.isEmpty && orphans.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No matches for "${_filterCtrl.text}".',
          style: const TextStyle(color: Colors.white54),
          textAlign: TextAlign.center,
        ),
      );
    }
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        if (savedBoats.isNotEmpty) ...[
          const _SectionHeader('Your boats'),
          for (final boat in savedBoats)
            _savedBoatTile(svc, boat, lengthMd),
        ],
        if (orphans.isNotEmpty) ...[
          const _SectionHeader('From the polar library'),
          for (final p in orphans) _orphanPolarTile(svc, p),
        ],
      ],
    );
  }

  bool _boatMatches(Boat b) {
    final hay = '${b.name} ${b.type}'.toLowerCase();
    return hay.contains(_filter);
  }

  bool _polarMatches(PolarEntry p) {
    final hay = '${p.label} ${p.name} ${p.source}'.toLowerCase();
    return hay.contains(_filter);
  }

  Widget _savedBoatTile(
      RoutePlannerBoatsService svc, Boat boat, PathMetadata? lengthMd) {
    final isActive = svc.selectedBoatId == boat.id;
    final subParts = <String>[
      boat.type,
      if (boat.loaM != null)
        'LOA ${lengthMd?.format(boat.loaM!, decimals: 1) ?? '${boat.loaM!.toStringAsFixed(1)} m'}',
      if (boat.polarPath != null) 'polar set',
    ];
    final tile = ListTile(
      dense: true,
      leading: Icon(
        boat.isSail ? Icons.sailing : Icons.directions_boat_filled,
        color: isActive ? Colors.white : Colors.white70,
      ),
      title: Text(
        boat.name,
        style: TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        subParts.join(' · '),
        style: const TextStyle(color: Colors.white38, fontSize: 11),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isActive)
            const Icon(Icons.check, color: Colors.greenAccent),
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.white54, size: 18),
            onPressed: () => _edit(boat),
            tooltip: 'Edit',
          ),
        ],
      ),
      onTap: () {
        svc.setSelectedBoat(boat);
        Navigator.of(context).pop();
      },
    );
    return Dismissible(
      key: ValueKey('boat-${boat.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red.shade900,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDelete(boat),
      onDismissed: (_) async {
        await svc.deleteBoat(boat.id);
      },
      child: tile,
    );
  }

  /// Polar that isn't yet attached to any of your saved boats. Tapping
  /// it POSTs `/boats` with the polar's label + path, then selects
  /// the new boat.
  Widget _orphanPolarTile(RoutePlannerBoatsService svc, PolarEntry p) {
    return ListTile(
      dense: true,
      leading: const Icon(Icons.auto_awesome,
          color: Colors.white54, size: 20),
      title: Text(
        p.label.isNotEmpty ? p.label : p.name,
        style: const TextStyle(color: Colors.white70, fontSize: 14),
      ),
      subtitle: Text(
        '${p.source} polar · tap to add to your boats',
        style: const TextStyle(color: Colors.white38, fontSize: 11),
      ),
      trailing: const Icon(Icons.add, color: Colors.white54, size: 18),
      onTap: () async {
        final boat = await svc.adoptPolar(p);
        if (!mounted) return;
        if (boat != null) {
          Navigator.of(context).pop();
        }
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}
