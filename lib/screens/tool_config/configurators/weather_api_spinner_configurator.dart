import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../models/tool_config.dart';
import '../../../models/tool.dart';
import '../../../services/signalk_service.dart';
import '../base_tool_configurator.dart';

/// Weather provider info from SignalK Weather API
class WeatherProvider {
  final String id;
  final String name;
  final String? description;

  WeatherProvider({
    required this.id,
    required this.name,
    this.description,
  });

  factory WeatherProvider.fromJson(String id, Map<String, dynamic> json) {
    return WeatherProvider(
      id: id,
      name: json['name'] as String? ?? id,
      description: json['description'] as String?,
    );
  }
}

/// Configurator for Weather API Spinner tool
class WeatherApiSpinnerConfigurator extends ToolConfigurator {
  @override
  String get toolTypeId => 'weather_api_spinner';

  @override
  Size get defaultSize => const Size(4, 4);

  // Weather API Spinner-specific state
  String? selectedProvider;
  List<WeatherProvider> availableProviders = [];
  bool loadingProviders = false;
  String? loadError;
  bool showWeatherAnimation = true;

  @override
  void reset() {
    selectedProvider = null;
    availableProviders = [];
    loadingProviders = false;
    loadError = null;
    showWeatherAnimation = true;
  }

  @override
  void loadDefaults(SignalKService signalKService) {
    reset();
  }

  @override
  void loadFromTool(Tool tool) {
    final style = tool.config.style;
    if (style.customProperties != null) {
      final provider = style.customProperties!['provider'];
      selectedProvider = (provider is String && provider.isNotEmpty) ? provider : null;
      showWeatherAnimation = style.customProperties!['showWeatherAnimation'] as bool? ?? true;
    }
  }

  @override
  ToolConfig getConfig() {
    return ToolConfig(
      dataSources: const [],
      style: StyleConfig(
        customProperties: {
          'provider': selectedProvider ?? '',
          'showWeatherAnimation': showWeatherAnimation,
        },
      ),
    );
  }

  @override
  String? validate() {
    // Provider is optional - empty means use default/first available
    return null;
  }

  /// Fetch available weather providers from SignalK
  Future<void> loadProviders(SignalKService signalKService, StateSetter setState) async {
    setState(() {
      loadingProviders = true;
      loadError = null;
    });

    try {
      final serverUrl = signalKService.serverUrl;
      final useSecure = serverUrl.startsWith('wss://') || serverUrl.startsWith('https://');
      final host = serverUrl.replaceAll(RegExp(r'^wss?://|^https?://'), '').split('/').first;
      final scheme = useSecure ? 'https' : 'http';

      final url = '$scheme://$host/signalk/v2/api/weather/_providers';

      if (kDebugMode) {
        print('WeatherApiSpinnerConfigurator: Fetching providers from $url');
      }

      final response = await http.get(
        Uri.parse(url),
        headers: signalKService.authToken != null
            ? {'Authorization': 'Bearer ${signalKService.authToken!.token}'}
            : null,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (kDebugMode) {
          print('WeatherApiSpinnerConfigurator: Response: $data');
        }

        final providers = <WeatherProvider>[];

        if (data is Map<String, dynamic>) {
          // Format: { "provider-id": { "name": "...", "description": "..." }, ... }
          for (final entry in data.entries) {
            if (entry.value is Map<String, dynamic>) {
              providers.add(WeatherProvider.fromJson(
                entry.key,
                entry.value as Map<String, dynamic>,
              ));
            } else {
              // Simple format: { "provider-id": "Provider Name" }
              providers.add(WeatherProvider(
                id: entry.key,
                name: entry.value?.toString() ?? entry.key,
              ));
            }
          }
        } else if (data is List) {
          // Format: [ { "id": "...", "name": "..." }, ... ]
          for (final item in data) {
            if (item is Map<String, dynamic>) {
              final id = item['id'] as String? ?? '';
              if (id.isNotEmpty) {
                providers.add(WeatherProvider(
                  id: id,
                  name: item['name'] as String? ?? id,
                  description: item['description'] as String?,
                ));
              }
            }
          }
        }

        setState(() {
          availableProviders = providers;
          loadingProviders = false;
        });

        if (kDebugMode) {
          print('WeatherApiSpinnerConfigurator: Loaded ${providers.length} providers');
        }
      } else if (response.statusCode == 404) {
        setState(() {
          loadError = 'Weather API not available on this server';
          loadingProviders = false;
        });
      } else {
        setState(() {
          loadError = 'Failed to load providers: ${response.statusCode}';
          loadingProviders = false;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('WeatherApiSpinnerConfigurator error: $e');
      }
      setState(() {
        loadError = 'Error loading providers: $e';
        loadingProviders = false;
      });
    }
  }

  @override
  Widget buildConfigUI(BuildContext context, SignalKService signalKService) {
    return StatefulBuilder(
      builder: (context, setState) {
        // Load providers on first display
        if (availableProviders.isEmpty && !loadingProviders && loadError == null) {
          Future.microtask(() => loadProviders(signalKService, setState));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Weather Provider',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Select which weather data provider to use. Leave empty to use the default provider.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),

            if (loadingProviders)
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 8),
                    Text(
                      'Loading weather providers...',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              )
            else if (loadError != null)
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.error_outline, color: Colors.red.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              loadError!,
                              style: TextStyle(color: Colors.red.shade700),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () => loadProviders(signalKService, setState),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              // Auto/Default option
              RadioListTile<String?>(
                title: const Text('Auto (Default Provider)'),
                subtitle: const Text('Use the first available weather provider'),
                value: null,
                groupValue: selectedProvider,
                onChanged: (value) {
                  setState(() => selectedProvider = value);
                },
              ),

              if (availableProviders.isNotEmpty) ...[
                const Divider(),
                ...availableProviders.map((provider) {
                  return RadioListTile<String?>(
                    title: Text(provider.name),
                    subtitle: provider.description != null
                        ? Text(provider.description!)
                        : Text(
                            provider.id,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                    value: provider.id,
                    groupValue: selectedProvider,
                    onChanged: (value) {
                      setState(() => selectedProvider = value);
                    },
                  );
                }),
              ] else if (!loadingProviders && loadError == null)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'No weather providers found. The Weather API may not have any providers configured.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 8),
              // Refresh button
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => loadProviders(signalKService, setState),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Refresh Providers'),
                ),
              ),
            ],

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),

            // Animation settings
            Text(
              'Display Options',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),

            SwitchListTile(
              title: const Text('Weather Animation'),
              subtitle: const Text('Show animated weather effects (rain, snow, etc.)'),
              value: showWeatherAnimation,
              onChanged: (value) {
                setState(() => showWeatherAnimation = value);
              },
            ),
          ],
        );
      },
    );
  }
}
