import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/app_colors.dart';
import '../../models/boat.dart';
import '../../models/boat_polar_specs.dart';
import '../../models/path_metadata.dart';
import '../../services/route_planner_boats_service.dart';
import '../../services/signalk_service.dart';

/// Opens the polar-from-specs form. Returns the new polar's server
/// path on success, `null` on cancel/error.
Future<String?> showPolarGeneratorSheet(
  BuildContext context, {
  String? defaultName,
  BoatDraft? seedFromBoatDraft,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.cardBackgroundDark,
    isScrollControlled: true,
    builder: (ctx) => _PolarGeneratorSheet(
      defaultName: defaultName,
      seedFromBoatDraft: seedFromBoatDraft,
    ),
  );
}

class _PolarGeneratorSheet extends StatefulWidget {
  const _PolarGeneratorSheet({this.defaultName, this.seedFromBoatDraft});
  final String? defaultName;
  final BoatDraft? seedFromBoatDraft;

  @override
  State<_PolarGeneratorSheet> createState() => _PolarGeneratorSheetState();
}

class _PolarGeneratorSheetState extends State<_PolarGeneratorSheet> {
  late TextEditingController _nameCtrl;
  late TextEditingController _loaCtrl;
  late TextEditingController _lwlCtrl;
  late TextEditingController _beamCtrl;
  late TextEditingController _draftCtrl;
  late TextEditingController _displacementCtrl;
  late TextEditingController _ballastCtrl;
  late TextEditingController _saUpwindCtrl;
  late TextEditingController _saDownwindCtrl;
  late TextEditingController _mastCtrl;
  String _rigType = 'sloop';
  String _keelType = 'fin';
  String _hullType = 'monohull';
  bool _overwrite = false;
  bool _submitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final seed = widget.seedFromBoatDraft;
    final md = _lengthMd();
    _nameCtrl = TextEditingController(text: widget.defaultName ?? '');
    _loaCtrl = TextEditingController(text: _siToDisplay(seed?.loaM, md));
    _lwlCtrl = TextEditingController();
    _beamCtrl = TextEditingController(text: _siToDisplay(seed?.beamM, md));
    _draftCtrl = TextEditingController(text: _siToDisplay(seed?.draughtM, md));
    _displacementCtrl = TextEditingController(
      text: seed?.displacementKg == null
          ? ''
          : seed!.displacementKg!.toStringAsFixed(0),
    );
    _ballastCtrl = TextEditingController();
    _saUpwindCtrl = TextEditingController();
    _saDownwindCtrl = TextEditingController();
    _mastCtrl = TextEditingController();
    if (seed?.rigType != null &&
        BoatPolarSpecs.rigTypes.contains(seed!.rigType)) {
      _rigType = seed.rigType!;
    }
    if (seed?.keelType != null &&
        BoatPolarSpecs.keelTypes.contains(seed!.keelType)) {
      _keelType = seed.keelType!;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _loaCtrl.dispose();
    _lwlCtrl.dispose();
    _beamCtrl.dispose();
    _draftCtrl.dispose();
    _displacementCtrl.dispose();
    _ballastCtrl.dispose();
    _saUpwindCtrl.dispose();
    _saDownwindCtrl.dispose();
    _mastCtrl.dispose();
    super.dispose();
  }

  PathMetadata? _lengthMd() => context
      .read<SignalKService>()
      .metadataStore
      .getWithFallback('design.length', (_) => 'length');
  String _lengthSymbol() => _lengthMd()?.symbol ?? 'm';

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
    return md?.convertToSI(v) ?? v;
  }

  double? _parse(TextEditingController ctrl) {
    final t = ctrl.text.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Name required.');
      return;
    }
    final md = _lengthMd();
    final loa = _displayToSi(_loaCtrl.text, md);
    final lwl = _displayToSi(_lwlCtrl.text, md);
    final beam = _displayToSi(_beamCtrl.text, md);
    final draft = _displayToSi(_draftCtrl.text, md);
    final disp = _parse(_displacementCtrl);
    final saUp = _parse(_saUpwindCtrl);
    final missing = <String>[];
    if (loa == null) missing.add('LOA');
    if (lwl == null) missing.add('LWL');
    if (beam == null) missing.add('Beam');
    if (draft == null) missing.add('Draft');
    if (disp == null) missing.add('Displacement');
    if (saUp == null) missing.add('Sail area (upwind)');
    if (missing.isNotEmpty) {
      setState(
          () => _errorMessage = 'Missing required: ${missing.join(", ")}');
      return;
    }

    final specs = BoatPolarSpecs(
      loaM: loa!,
      lwlM: lwl!,
      beamM: beam!,
      draftM: draft!,
      displacementKg: disp!,
      ballastKg: _parse(_ballastCtrl),
      sailAreaUpwindM2: saUp!,
      sailAreaDownwindM2: _parse(_saDownwindCtrl) ?? 0.0,
      mastHeightM: _displayToSi(_mastCtrl.text, md),
      rigType: _rigType,
      keelType: _keelType,
      hullType: _hullType,
    );

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    final svc = context.read<RoutePlannerBoatsService>();
    final path = await svc.generatePolarFromSpecs(
      name: name,
      specs: specs,
      overwrite: _overwrite,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (path == null) {
      setState(() => _errorMessage = svc.lastError ?? 'Generation failed');
      return;
    }
    Navigator.of(context).pop(path);
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
                const Row(
                  children: [
                    Icon(Icons.auto_awesome, color: Colors.white70),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Generate polar from specs',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _textField(_nameCtrl, 'Polar name *'),
                const SizedBox(height: 16),
                const _SectionLabel('Hull'),
                _num('LOA *', _loaCtrl, _lengthSymbol()),
                _num('LWL *', _lwlCtrl, _lengthSymbol()),
                _num('Beam *', _beamCtrl, _lengthSymbol()),
                _num('Draft *', _draftCtrl, _lengthSymbol()),
                _num('Displacement *', _displacementCtrl, 'kg'),
                _num('Ballast', _ballastCtrl, 'kg'),
                const SizedBox(height: 8),
                const _SectionLabel('Rig'),
                _num('Sail area upwind *', _saUpwindCtrl, 'm²'),
                _num('Sail area downwind', _saDownwindCtrl, 'm²'),
                _num('Mast height', _mastCtrl, _lengthSymbol()),
                const SizedBox(height: 8),
                _enumDropdown(
                    label: 'Rig type',
                    value: _rigType,
                    items: BoatPolarSpecs.rigTypes,
                    onChanged: (v) =>
                        setState(() => _rigType = v ?? _rigType)),
                const SizedBox(height: 6),
                _enumDropdown(
                    label: 'Keel type',
                    value: _keelType,
                    items: BoatPolarSpecs.keelTypes,
                    onChanged: (v) =>
                        setState(() => _keelType = v ?? _keelType)),
                const SizedBox(height: 6),
                _enumDropdown(
                    label: 'Hull type',
                    value: _hullType,
                    items: BoatPolarSpecs.hullTypes,
                    onChanged: (v) =>
                        setState(() => _hullType = v ?? _hullType)),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: _overwrite,
                  onChanged: (v) => setState(() => _overwrite = v),
                  title: const Text('Overwrite existing polar with the same name',
                      style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 8),
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
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _submit,
                        child: _submitting
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              )
                            : const Text('Generate'),
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

  Widget _num(String label, TextEditingController ctrl, String suffix) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
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

  Widget _enumDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF14142A),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          Text(label,
              style:
                  const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                dropdownColor: AppColors.cardBackgroundDark,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                items: [
                  for (final it in items)
                    DropdownMenuItem(value: it, child: Text(it)),
                ],
                onChanged: onChanged,
              ),
            ),
          ),
        ],
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
