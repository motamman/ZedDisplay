import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/signalk_service.dart';

/// Abstract base class for all native plugin configurators.
///
/// Provides common functionality for fetching and saving plugin configuration
/// to the SignalK server. Subclasses implement the UI for their specific plugin.
abstract class BasePluginConfigurator extends StatefulWidget {
  final SignalKService signalKService;
  final String pluginId;
  final Map<String, dynamic> initialConfig;
  final VoidCallback? onSaved;

  const BasePluginConfigurator({
    super.key,
    required this.signalKService,
    required this.pluginId,
    required this.initialConfig,
    this.onSaved,
  });
}

/// Abstract state class for plugin configurators.
///
/// Provides:
/// - [currentConfig] getter that subclasses must implement
/// - [saveConfig] method to persist changes to the server
/// - [isSaving] state for UI feedback
/// - Helper methods for common UI patterns
abstract class BasePluginConfiguratorState<T extends BasePluginConfigurator>
    extends State<T> {
  bool _isSaving = false;
  String? _errorMessage;

  /// Whether the configurator is currently saving
  bool get isSaving => _isSaving;

  /// Error message from last operation, if any
  String? get errorMessage => _errorMessage;

  /// Returns the current configuration state.
  /// Subclasses must implement this to provide their config data.
  Map<String, dynamic> get currentConfig;

  /// Saves the current configuration to the SignalK server.
  ///
  /// Posts to /skServer/plugins/{pluginId}/config with the structure:
  /// ```json
  /// {
  ///   "enabled": true,
  ///   "configuration": { ... }
  /// }
  /// ```
  Future<bool> saveConfig() async {
    if (_isSaving) return false;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final protocol =
          widget.signalKService.useSecureConnection ? 'https' : 'http';
      final url =
          '$protocol://${widget.signalKService.serverUrl}/skServer/plugins/${widget.pluginId}/config';

      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (widget.signalKService.authToken != null) {
        headers['Authorization'] =
            'Bearer ${widget.signalKService.authToken!.token}';
      }

      // First get current config to preserve enabled state and other fields
      final getResponse = await http.get(Uri.parse(url), headers: headers);

      if (getResponse.statusCode == 401) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'Not authorized. Admin permissions required.';
        });
        return false;
      }

      Map<String, dynamic> configToSave;
      if (getResponse.statusCode == 200) {
        configToSave = jsonDecode(getResponse.body) as Map<String, dynamic>;
        configToSave['configuration'] = currentConfig;
      } else {
        // If we can't get current config, create a new one
        configToSave = {
          'enabled': true,
          'configuration': currentConfig,
        };
      }

      // Save the config
      final postResponse = await http.post(
        Uri.parse(url),
        headers: headers,
        body: jsonEncode(configToSave),
      );

      if (postResponse.statusCode == 200) {
        if (mounted) {
          setState(() => _isSaving = false);
          widget.onSaved?.call();
        }
        return true;
      } else if (postResponse.statusCode == 401) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'Not authorized. Admin permissions required.';
        });
        return false;
      } else {
        setState(() {
          _isSaving = false;
          _errorMessage = 'Failed to save: ${postResponse.statusCode}';
        });
        return false;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'Error: $e';
        });
      }
      return false;
    }
  }

  /// Builds a standard save button with loading state
  Widget buildSaveButton({String label = 'Save Configuration'}) {
    return ElevatedButton.icon(
      onPressed: _isSaving ? null : _handleSave,
      icon: _isSaving
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.save),
      label: Text(label),
    );
  }

  Future<void> _handleSave() async {
    final success = await saveConfig();
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuration saved successfully')),
      );
    } else if (!success && mounted && _errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_errorMessage!),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Builds an error banner if there's an error message
  Widget? buildErrorBanner() {
    if (_errorMessage == null) return null;
    return MaterialBanner(
      content: Text(_errorMessage!),
      backgroundColor: Colors.red.shade100,
      actions: [
        TextButton(
          onPressed: () => setState(() => _errorMessage = null),
          child: const Text('DISMISS'),
        ),
      ],
    );
  }
}

/// Mixin that provides form field builders for common JSON Schema types.
///
/// Use these helpers to quickly build forms from plugin schemas:
/// - [buildTextField] for string inputs
/// - [buildNumberField] for numeric inputs
/// - [buildSwitchField] for boolean toggles
/// - [buildDropdownField] for enum selections
/// - [buildSection] for grouping related fields
mixin PluginConfigFormBuilders<T extends BasePluginConfigurator>
    on BasePluginConfiguratorState<T> {
  /// Builds a text input field
  Widget buildTextField({
    required String label,
    required String? value,
    required ValueChanged<String> onChanged,
    String? hint,
    String? helperText,
    bool obscure = false,
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helperText,
          border: const OutlineInputBorder(),
        ),
        obscureText: obscure,
        maxLines: maxLines,
        onChanged: onChanged,
      ),
    );
  }

  /// Builds a numeric input field
  Widget buildNumberField({
    required String label,
    required num? value,
    required ValueChanged<num?> onChanged,
    String? hint,
    String? helperText,
    num? min,
    num? max,
    bool allowDecimals = true,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        initialValue: value?.toString() ?? '',
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          helperText: helperText,
          border: const OutlineInputBorder(),
        ),
        keyboardType: TextInputType.numberWithOptions(decimal: allowDecimals),
        onChanged: (text) {
          if (text.isEmpty) {
            onChanged(null);
          } else {
            final parsed = allowDecimals ? double.tryParse(text) : int.tryParse(text);
            if (parsed != null) {
              if (min != null && parsed < min) return;
              if (max != null && parsed > max) return;
              onChanged(parsed);
            }
          }
        },
      ),
    );
  }

  /// Builds a boolean switch field
  Widget buildSwitchField({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    String? subtitle,
  }) {
    return SwitchListTile(
      title: Text(label),
      subtitle: subtitle != null ? Text(subtitle) : null,
      value: value,
      onChanged: onChanged,
    );
  }

  /// Builds a dropdown selection field
  Widget buildDropdownField<V>({
    required String label,
    required V? value,
    required List<DropdownMenuItem<V>> items,
    required ValueChanged<V?> onChanged,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DropdownButtonFormField<V>(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        initialValue: value,
        hint: hint != null ? Text(hint) : null,
        items: items,
        onChanged: onChanged,
      ),
    );
  }

  /// Builds a section header with optional divider
  Widget buildSection({
    required String title,
    String? description,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        if (description != null) ...[
          const SizedBox(height: 4),
          Text(
            description,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }
}
