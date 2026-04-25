import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/app_colors.dart';
import '../../models/boat.dart';
import '../../models/path_metadata.dart';
import '../../models/sailboatdata_hit.dart';
import '../../services/route_planner_boats_service.dart';
import '../../services/signalk_service.dart';
import 'polar_generator_sheet.dart';

/// Create / edit a [Boat]. Pass [existing] to edit, or [initial] to
/// seed from a sailboatdata prefill. Pops with the saved `Boat` on
/// success, `null` if the user cancels.
Future<Boat?> showBoatEditorSheet(
  BuildContext context, {
  Boat? existing,
  BoatDraft? initial,
  ExternalBoatPrefill? externalPrefill,
}) {
  return showModalBottomSheet<Boat>(
    context: context,
    backgroundColor: AppColors.cardBackgroundDark,
    isScrollControlled: true,
    builder: (ctx) => _BoatEditorSheet(
      existing: existing,
      initial: initial,
      externalPrefill: externalPrefill,
    ),
  );
}

class _BoatEditorSheet extends StatefulWidget {
  const _BoatEditorSheet({
    this.existing,
    this.initial,
    this.externalPrefill,
  });

  final Boat? existing;
  final BoatDraft? initial;
  final ExternalBoatPrefill? externalPrefill;

  @override
  State<_BoatEditorSheet> createState() => _BoatEditorSheetState();
}

class _BoatEditorSheetState extends State<_BoatEditorSheet> {
  late final BoatDraft _draft;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _loaCtrl;
  late final TextEditingController _beamCtrl;
  late final TextEditingController _draughtCtrl;
  late final TextEditingController _airDraftCtrl;
  late final TextEditingController _displacementCtrl;
  late final TextEditingController _motorSpeedCtrl;
  bool _saving = false;
  String? _errorMessage;

  static const _rigTypes = <String>[
    'sloop', 'cutter', 'ketch', 'yawl', 'cat', 'schooner', 'other',
  ];
  static const _keelTypes = <String>[
    'fin', 'bulb', 'wing', 'full', 'centerboard', 'swing', 'other',
  ];

  @override
  void initState() {
    super.initState();
    final seed = widget.initial ??
        (widget.existing != null ? BoatDraft.fromBoat(widget.existing!) : BoatDraft(type: 'sail'));
    _draft = seed;
    _nameCtrl = TextEditingController(text: _draft.name ?? '');
    _loaCtrl = TextEditingController(text: _siToDisplay(_draft.loaM, _lengthMd()));
    _beamCtrl = TextEditingController(text: _siToDisplay(_draft.beamM, _lengthMd()));
    _draughtCtrl = TextEditingController(text: _siToDisplay(_draft.draughtM, _lengthMd()));
    _airDraftCtrl = TextEditingController(text: _siToDisplay(_draft.airDraftM, _lengthMd()));
    _displacementCtrl = TextEditingController(
        text: _draft.displacementKg == null
            ? ''
            : _draft.displacementKg!.toStringAsFixed(0));
    _motorSpeedCtrl = TextEditingController(
        text: _siToDisplay(_draft.motorSpeedMs, _speedMd()));
    // Pull the caller's polar list once on open so the picker isn't
    // empty on first render.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final svc = context.read<RoutePlannerBoatsService>();
      if (svc.polars.isEmpty) svc.refreshPolars();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _loaCtrl.dispose();
    _beamCtrl.dispose();
    _draughtCtrl.dispose();
    _airDraftCtrl.dispose();
    _displacementCtrl.dispose();
    _motorSpeedCtrl.dispose();
    super.dispose();
  }

  PathMetadata? _lengthMd() {
    return context
        .read<SignalKService>()
        .metadataStore
        .getWithFallback('design.length', (_) => 'length');
  }

  PathMetadata? _speedMd() {
    return context
        .read<SignalKService>()
        .metadataStore
        .getWithFallback('environment.wind.speedTrue', (_) => 'speed');
  }

  String _siToDisplay(double? si, PathMetadata? md) {
    if (si == null) return '';
    if (md != null) {
      final v = md.convert(si);
      if (v != null) return v.toStringAsFixed(2);
    }
    return si.toStringAsFixed(2);
  }

  double? _displayToSi(String text, PathMetadata? md) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final v = double.tryParse(t);
    if (v == null) return null;
    if (md != null) return md.convertToSI(v) ?? v;
    return v;
  }

  String _lengthSymbol() => _lengthMd()?.symbol ?? 'm';
  String _speedSymbol() => _speedMd()?.symbol ?? 'm/s';

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Name is required.');
      return;
    }
    final type = _draft.type ?? 'sail';

    _draft.name = name;
    _draft.type = type;
    _draft.loaM = _displayToSi(_loaCtrl.text, _lengthMd());
    _draft.beamM = _displayToSi(_beamCtrl.text, _lengthMd());
    _draft.draughtM = _displayToSi(_draughtCtrl.text, _lengthMd());
    _draft.airDraftM = _displayToSi(_airDraftCtrl.text, _lengthMd());
    final disp = _displacementCtrl.text.trim();
    _draft.displacementKg = disp.isEmpty ? null : double.tryParse(disp);
    _draft.motorSpeedMs = _displayToSi(_motorSpeedCtrl.text, _speedMd());

    setState(() {
      _saving = true;
      _errorMessage = null;
    });
    final svc = context.read<RoutePlannerBoatsService>();
    final Boat? saved = widget.existing == null
        ? await svc.createBoat(_draft)
        : await svc.patchBoat(widget.existing!.id, _draft.toBoatSpecJson());
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved == null) {
      setState(() => _errorMessage = svc.lastError ?? 'Save failed');
      return;
    }
    Navigator.of(context).pop(saved);
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.directions_boat, color: Colors.white70),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.existing == null
                            ? 'New boat'
                            : 'Edit "${widget.existing!.name}"',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (widget.externalPrefill != null)
                      Chip(
                        label: Text(
                          'from ${widget.externalPrefill!.source ?? 'external'}',
                          style: const TextStyle(fontSize: 10),
                        ),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: Colors.white12,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _textField(_nameCtrl, 'Name *'),
                const SizedBox(height: 12),
                const _SectionLabel('Type'),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'sail', label: Text('Sail')),
                    ButtonSegment(value: 'power', label: Text('Power')),
                  ],
                  selected: {_draft.type ?? 'sail'},
                  onSelectionChanged: (s) =>
                      setState(() => _draft.type = s.first),
                ),
                const SizedBox(height: 12),
                _numberRow('LOA', _loaCtrl, _lengthSymbol()),
                _numberRow('Beam', _beamCtrl, _lengthSymbol()),
                _numberRow('Draught', _draughtCtrl, _lengthSymbol()),
                _numberRow('Air draft', _airDraftCtrl, _lengthSymbol()),
                _numberRow('Displacement', _displacementCtrl, 'kg'),
                _numberRow('Motor speed', _motorSpeedCtrl, _speedSymbol()),
                const SizedBox(height: 8),
                const _SectionLabel('Rig'),
                _dropdown(
                  value: _draft.rigType,
                  items: _rigTypes,
                  onChanged: (v) => setState(() => _draft.rigType = v),
                  hint: 'Rig type',
                ),
                const SizedBox(height: 8),
                const _SectionLabel('Keel'),
                _dropdown(
                  value: _draft.keelType,
                  items: _keelTypes,
                  onChanged: (v) => setState(() => _draft.keelType = v),
                  hint: 'Keel type',
                ),
                const SizedBox(height: 12),
                _polarPicker(),
                if (widget.externalPrefill != null) ...[
                  const SizedBox(height: 16),
                  const _SectionLabel('Source'),
                  _externalInfo(widget.externalPrefill!),
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Color(0xFFFF8888)),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : Text(widget.existing == null
                                ? 'Create'
                                : 'Save changes'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _numberRow(String label, TextEditingController ctrl, String suffix) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(
            decimal: true, signed: false),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
        ],
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54),
          suffixText: suffix,
          suffixStyle: const TextStyle(color: Colors.white54),
          isDense: true,
          filled: true,
          fillColor: const Color(0xFF14142A),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _textField(TextEditingController ctrl, String label) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        isDense: true,
        filled: true,
        fillColor: const Color(0xFF14142A),
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _dropdown({
    required String? value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required String hint,
  }) {
    final effective = items.contains(value) ? value : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF14142A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white24),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: effective,
          isExpanded: true,
          dropdownColor: AppColors.cardBackgroundDark,
          hint: Text(hint, style: const TextStyle(color: Colors.white38)),
          style: const TextStyle(color: Colors.white, fontSize: 14),
          items: [
            for (final it in items)
              DropdownMenuItem(value: it, child: Text(it)),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _polarPicker() {
    final svc = context.watch<RoutePlannerBoatsService>();
    final polars = svc.polars;
    // Current selection may not be in the list yet (just generated,
    // list not yet refreshed, etc.) — synthesise a placeholder option
    // so the dropdown still shows the path.
    final current = _draft.polarPath;
    final items = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('None (server default)'),
      ),
      for (final p in polars)
        DropdownMenuItem<String?>(value: p.path, child: Text(p.label)),
      if (current != null && polars.every((p) => p.path != current))
        DropdownMenuItem<String?>(
          value: current,
          child: Text(current),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('Polar'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF14142A),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white24),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: current,
              isExpanded: true,
              dropdownColor: AppColors.cardBackgroundDark,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              items: items,
              onChanged: (v) => setState(() => _draft.polarPath = v),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            TextButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white70,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: svc.loadingPolars ? null : () => svc.refreshPolars(),
            ),
            const Spacer(),
            OutlinedButton.icon(
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('Generate from specs…'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
              ),
              onPressed: _openPolarGenerator,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openPolarGenerator() async {
    final newPath = await showPolarGeneratorSheet(
      context,
      defaultName: _nameCtrl.text.trim(),
      seedFromBoatDraft: _draft,
    );
    if (!mounted || newPath == null) return;
    setState(() => _draft.polarPath = newPath);
  }

  Widget _externalInfo(ExternalBoatPrefill ext) {
    String? r(double? x, {int decimals = 1}) =>
        x?.toStringAsFixed(decimals);
    final rows = <Widget>[
      if (ext.builder != null) _kv('Builder', ext.builder!),
      if (ext.firstBuilt != null) _kv('First built', '${ext.firstBuilt}'),
      if (ext.saTotalM2 != null) _kv('Sail area', '${r(ext.saTotalM2)} m²'),
      if (ext.balDispRatio != null)
        _kv('Ballast/disp', '${r(ext.balDispRatio)}'),
      if (ext.saDispRatio != null) _kv('SA/disp', '${r(ext.saDispRatio)}'),
      if (ext.permalink != null)
        Text(ext.permalink!,
            style: const TextStyle(color: Colors.white38, fontSize: 11)),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF14142A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFF2A2A44)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12),
          children: [
            TextSpan(
                text: '$k: ',
                style: const TextStyle(color: Colors.white54)),
            TextSpan(
                text: v, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
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
  }
}
