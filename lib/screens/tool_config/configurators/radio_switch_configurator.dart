import 'package:flutter/material.dart';
import '../../../models/tool_config.dart';
import '../../../models/tool.dart';
import '../../../services/signalk_service.dart';
import '../base_tool_configurator.dart';

/// Configurator for the Radio Switch tool.
///
/// Lets the user build an arbitrary list of `label -> value` options. Each
/// option's value is typed (Text / Number / Bool) so it round-trips as the
/// correct JSON type, and is stored under customProperties['options'] as a
/// list of `{label, value, type}` maps.
/// Coerce a radio-option's edited text into the declared JSON type
/// ('number' → num, 'bool' → true/false, else trimmed text). Pure +
/// top-level so it's unit-testable. A non-parseable number falls back to the
/// trimmed text rather than throwing.
dynamic coerceRadioOptionValue(String text, String type) {
  final trimmed = text.trim();
  switch (type) {
    case 'number':
      return num.tryParse(trimmed) ?? trimmed;
    case 'bool':
      return trimmed.toLowerCase() == 'true';
    default:
      return trimmed;
  }
}

class RadioSwitchConfigurator extends ToolConfigurator {
  @override
  String get toolTypeId => 'radio_switch';

  @override
  Size get defaultSize => const Size(2, 3);

  /// Working copy of the options. Each entry holds the editable form fields:
  /// {'id': int, 'label': String, 'valueText': String, 'type': String}.
  final List<Map<String, dynamic>> _options = [];
  int _nextId = 0;

  Map<String, dynamic> _newOption({
    String label = '',
    String valueText = '',
    String type = 'string',
  }) =>
      {'id': _nextId++, 'label': label, 'valueText': valueText, 'type': type};

  @override
  void reset() {
    _options
      ..clear()
      ..add(_newOption());
  }

  @override
  void loadDefaults(SignalKService signalKService) => reset();

  @override
  void loadFromTool(Tool tool) {
    _options.clear();
    final raw = tool.config.style.customProperties?['options'];
    if (raw is List) {
      for (final o in raw) {
        if (o is Map) {
          final value = o['value'];
          var type = (o['type'] as String?) ??
              (value is bool
                  ? 'bool'
                  : value is num
                      ? 'number'
                      : 'string');
          // Clamp to a supported value — a stray persisted type would otherwise
          // assert the type dropdown (initialValue must match an item).
          if (type != 'string' && type != 'number' && type != 'bool') {
            type = 'string';
          }
          _options.add(_newOption(
            label: (o['label'] as String?) ?? '',
            valueText: value?.toString() ?? '',
            type: type,
          ));
        }
      }
    }
    if (_options.isEmpty) _options.add(_newOption());
  }

  @override
  ToolConfig getConfig() {
    final opts = _options
        .where((o) => (o['label'] as String).trim().isNotEmpty)
        .map((o) => {
              'label': (o['label'] as String).trim(),
              'value': coerceRadioOptionValue(o['valueText'] as String, o['type'] as String),
              'type': o['type'],
            })
        .toList();

    return ToolConfig(
      dataSources: const [],
      style: StyleConfig(
        customProperties: {'options': opts},
      ),
    );
  }

  @override
  String? validate() {
    final labelled =
        _options.where((o) => (o['label'] as String).trim().isNotEmpty).toList();
    if (labelled.isEmpty) {
      return 'Add at least one option with a label';
    }
    for (final o in labelled) {
      final type = o['type'] as String;
      final valueText = (o['valueText'] as String).trim();
      if (type == 'bool') continue; // bool is always valid (true/false)
      if (valueText.isEmpty) {
        return 'Option "${o['label']}" needs a value';
      }
      if (type == 'number' && num.tryParse(valueText) == null) {
        return 'Option "${o['label']}" value must be a number';
      }
    }
    return null;
  }

  @override
  Widget buildConfigUI(BuildContext context, SignalKService signalKService) {
    return StatefulBuilder(
      builder: (context, setState) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Radio Switch Options',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Each option becomes a radio button. Selecting one PUTs its '
                'value to the path; only one can be active at a time. The value '
                'is sent as the chosen type (Text, Number, or Bool).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              ..._options.map((o) => _buildOptionRow(context, setState, o)),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _options.add(_newOption())),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Option'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOptionRow(
    BuildContext context,
    StateSetter setState,
    Map<String, dynamic> o,
  ) {
    final type = o['type'] as String;
    return Padding(
      key: ValueKey(o['id']),
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label
          Expanded(
            flex: 3,
            child: TextFormField(
              initialValue: o['label'] as String,
              decoration: const InputDecoration(
                labelText: 'Label',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => o['label'] = v,
            ),
          ),
          const SizedBox(width: 8),
          // Value (bool uses a true/false dropdown; others a text field)
          Expanded(
            flex: 3,
            child: type == 'bool'
                ? DropdownButtonFormField<String>(
                    initialValue:
                        (o['valueText'] as String).trim().toLowerCase() == 'true'
                            ? 'true'
                            : 'false',
                    decoration: const InputDecoration(
                      labelText: 'Value',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'true', child: Text('true')),
                      DropdownMenuItem(value: 'false', child: Text('false')),
                    ],
                    onChanged: (v) => o['valueText'] = v ?? 'false',
                  )
                : TextFormField(
                    initialValue: o['valueText'] as String,
                    decoration: const InputDecoration(
                      labelText: 'Value',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    keyboardType: type == 'number'
                        ? const TextInputType.numberWithOptions(
                            decimal: true, signed: true)
                        : TextInputType.text,
                    onChanged: (v) => o['valueText'] = v,
                  ),
          ),
          const SizedBox(width: 8),
          // Type
          SizedBox(
            width: 104,
            child: DropdownButtonFormField<String>(
              initialValue: type,
              decoration: const InputDecoration(
                labelText: 'Type',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'string', child: Text('Text')),
                DropdownMenuItem(value: 'number', child: Text('Number')),
                DropdownMenuItem(value: 'bool', child: Text('Bool')),
              ],
              onChanged: (v) => setState(() {
                o['type'] = v ?? 'string';
                // Seed a sane default when switching into Bool.
                if (o['type'] == 'bool' &&
                    (o['valueText'] as String).trim().toLowerCase() != 'true') {
                  o['valueText'] = 'false';
                }
              }),
            ),
          ),
          // Delete
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove option',
            onPressed: () => setState(() {
              _options.remove(o);
              if (_options.isEmpty) _options.add(_newOption());
            }),
          ),
        ],
      ),
    );
  }
}
