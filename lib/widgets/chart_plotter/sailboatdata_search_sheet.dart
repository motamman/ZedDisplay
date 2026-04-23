import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/app_colors.dart';
import '../../models/boat.dart';
import '../../models/path_metadata.dart';
import '../../models/sailboatdata_hit.dart';
import '../../services/route_planner_boats_service.dart';
import '../../services/signalk_service.dart';
import 'boat_editor_sheet.dart';

/// Search sailboatdata, pick a hit, hand off to the boat editor with
/// the prefilled draft. Returns the saved [Boat] on success,
/// `null` if the user cancels at any step.
Future<Boat?> showSailboatdataSearchSheet(BuildContext context) {
  return showModalBottomSheet<Boat>(
    context: context,
    backgroundColor: AppColors.cardBackgroundDark,
    isScrollControlled: true,
    builder: (ctx) => const _SailboatdataSearchSheet(),
  );
}

class _SailboatdataSearchSheet extends StatefulWidget {
  const _SailboatdataSearchSheet();

  @override
  State<_SailboatdataSearchSheet> createState() =>
      _SailboatdataSearchSheetState();
}

class _SailboatdataSearchSheetState extends State<_SailboatdataSearchSheet> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  SailboatdataSearchResult? _result;
  String? _error;
  bool _picking = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _runSearch(q);
    });
  }

  Future<void> _runSearch(String q) async {
    final svc = context.read<RoutePlannerBoatsService>();
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await svc.searchSailboatdata(q);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _result = result;
      if (result == null) _error = svc.lastError ?? 'Search failed';
    });
  }

  Future<void> _pickHit(SailboatdataHit hit) async {
    if (_picking) return;
    setState(() => _picking = true);
    final svc = context.read<RoutePlannerBoatsService>();
    final payload = await svc.fromExternalSailboatdata(hit.id);
    if (!mounted) return;
    setState(() => _picking = false);
    if (payload == null) {
      setState(() => _error = svc.lastError ?? 'Prefill failed');
      return;
    }
    final saved = await showBoatEditorSheet(
      context,
      initial: payload.draft,
      externalPrefill: payload.external,
    );
    if (!mounted) return;
    if (saved != null) Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.9;
    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxH),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: Colors.white70),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Search sailboatdata.com',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  onChanged: _onChanged,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Catalina 36, Tartan 37, …',
                    hintStyle: const TextStyle(color: Colors.white38),
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0xFF14142A),
                    border: const OutlineInputBorder(),
                    suffixIcon: _loading
                        ? const Padding(
                            padding: EdgeInsets.all(10),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFFFF8888)),
                  ),
                ),
              Flexible(child: _buildHits()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHits() {
    final result = _result;
    if (result == null) {
      return const SizedBox(height: 24);
    }
    if (result.hits.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'No matches.',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    final lengthMd = context
        .read<SignalKService>()
        .metadataStore
        .getWithFallback('design.length', (_) => 'length');
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: result.hits.length,
      separatorBuilder: (_, _) => const Divider(
        color: Colors.white12,
        height: 1,
      ),
      itemBuilder: (_, i) => _HitTile(
        hit: result.hits[i],
        lengthMd: lengthMd,
        onTap: () => _pickHit(result.hits[i]),
      ),
    );
  }
}

class _HitTile extends StatelessWidget {
  const _HitTile({required this.hit, required this.lengthMd, required this.onTap});

  final SailboatdataHit hit;
  final PathMetadata? lengthMd;
  final VoidCallback onTap;

  String _length(double? si) {
    if (si == null) return '—';
    if (lengthMd != null) return lengthMd!.format(si, decimals: 1);
    return '${si.toStringAsFixed(1)} m';
  }

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[
      if (hit.builder != null) hit.builder!,
      if (hit.firstBuilt != null) '${hit.firstBuilt}',
      'LOA ${_length(hit.loaM)}',
      if (hit.keelType != null) 'keel: ${hit.keelType}',
    ];
    return ListTile(
      dense: true,
      title: Text(
        hit.title,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      subtitle: Text(
        subtitleParts.join(' · '),
        style: const TextStyle(color: Colors.white54, fontSize: 11),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.white38),
      onTap: onTap,
    );
  }
}
