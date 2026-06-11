import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/string_extensions.dart';
import '../../utils/color_extensions.dart';
import '../../config/ui_constants.dart';
import 'common/control_tool_layout.dart';
import '../common/widget_empty_states.dart';

/// Config-driven radio-button switch for a single SignalK path.
///
/// The user defines a list of options in the configurator, each a
/// `label -> value` pair where the value can be a string, number, or bool.
/// Options render as mutually-exclusive radio buttons: selecting one PUTs that
/// option's value to the path, so exactly one value can ever be active at a
/// time. The currently-selected radio reflects whichever option's value matches
/// the path's live value.
class RadioSwitchTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const RadioSwitchTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<RadioSwitchTool> createState() => _RadioSwitchToolState();
}

class _RadioSwitchToolState extends State<RadioSwitchTool> with AutomaticKeepAliveClientMixin {
  bool _isSending = false;
  int? _pendingIndex; // optimistic selection while a PUT is in flight

  @override
  bool get wantKeepAlive => true;

  /// Options stored by the configurator under customProperties['options'] as
  /// a list of `{label, value, type}` maps. Returns an empty list when unset.
  List<Map<String, dynamic>> get _options {
    final raw = widget.config.style.customProperties?['options'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
  }

  /// Compare a live SignalK value against a configured option value.
  /// Numbers compare numerically; everything else falls back to a
  /// case-insensitive string compare so "On"/"on"/true all behave sanely.
  bool _valuesMatch(dynamic live, dynamic option) {
    if (live == null || option == null) return false;
    if (live is num && option is num) return live == option;
    if (live is bool && option is bool) return live == option;
    return live.toString().toLowerCase() == option.toString().toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.config.dataSources.isEmpty || _options.isEmpty) {
      return const WidgetEmptyState();
    }

    final dataSource = widget.config.dataSources.first;
    final style = widget.config.style;
    final options = _options;

    final activeColor = style.primaryColor?.toColor(fallback: Colors.green) ?? Colors.green;
    final inactiveColor = style.secondaryColor?.toColor(fallback: Colors.grey) ?? Colors.grey;

    // Read the pinned source if it has reported; otherwise fall back to the
    // latest value from any source so the selection always reflects real state.
    final dataPoint = widget.signalKService.getValue(dataSource.path, source: dataSource.source)
        ?? widget.signalKService.getValue(dataSource.path);
    final liveValue = dataPoint?.value;

    // Index of the option whose value matches the live path value.
    int? selectedIndex;
    for (var i = 0; i < options.length; i++) {
      if (_valuesMatch(liveValue, options[i]['value'])) {
        selectedIndex = i;
        break;
      }
    }
    final effectiveIndex = _pendingIndex ?? selectedIndex;

    final label = dataSource.label ?? dataSource.path.toReadableLabel();
    final selectedLabel = (effectiveIndex != null && effectiveIndex < options.length)
        ? (options[effectiveIndex]['label'] as String? ?? '')
        : '—';

    return ControlToolLayout(
      label: label,
      showLabel: style.showLabel == true,
      valueWidget: style.showValue == true
          ? Text(
              selectedLabel,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: effectiveIndex != null ? activeColor : inactiveColor,
              ),
            )
          : null,
      controlWidget: RadioGroup<int>(
        groupValue: effectiveIndex,
        onChanged: (index) {
          if (_isSending || index == null) return;
          _select(index, options[index], dataSource.path, dataSource.source);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < options.length; i++)
              RadioListTile<int>(
                value: i,
                dense: true,
                contentPadding: EdgeInsets.zero,
                activeColor: activeColor,
                title: Text(
                  options[i]['label'] as String? ?? '',
                  style: const TextStyle(fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
      path: dataSource.path,
      isSending: _isSending,
    );
  }

  Future<void> _select(int index, Map<String, dynamic> option, String path,
      String? source) async {
    setState(() {
      _pendingIndex = index;
      _isSending = true;
    });

    try {
      // PUT the configured value as-is. These are enum/state values
      // (string, number, or bool), NOT unit-bearing measurements, so they are
      // sent without MetadataStore conversion. Forward the configured source so
      // multi-source paths route to the right PUT handler (cf. SwitchTool).
      await widget.signalKService.sendPutRequest(path, option['value'], source: source);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${path.toReadableLabel()} set to ${option['label']}'),
            duration: UIConstants.snackBarShort,
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to set value: $e'),
            duration: UIConstants.snackBarNormal,
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
          _pendingIndex = null; // fall back to the live-value match
        });
      }
    }
  }
}

/// Builder for radio switch tools
class RadioSwitchToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'radio_switch',
      name: 'Radio Switch',
      description: 'Mutually-exclusive radio buttons that PUT a chosen value '
          '(string, number, or bool) to a single SignalK path',
      category: ToolCategory.controls,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsSecondaryColor: true,
        allowsMultiplePaths: false,
        minPaths: 1,
        maxPaths: 1,
        styleOptions: const [
          'primaryColor',    // Selected color
          'secondaryColor',  // Unselected color
          'showLabel',
          'showValue',       // Show selected option's label
        ],
        allowsUnitSelection: false,
        allowsTTL: false,
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return RadioSwitchTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
