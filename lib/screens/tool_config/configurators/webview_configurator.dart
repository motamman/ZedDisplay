import 'package:flutter/material.dart';
import '../../../models/tool_config.dart';
import '../../../models/tool.dart';
import '../../../services/signalk_service.dart';
import '../../../services/tool_config_service.dart';
import '../base_tool_configurator.dart';

/// Configurator for webview tool
class WebViewConfigurator extends ToolConfigurator {
  @override
  String get toolTypeId => 'webview';

  @override
  Size get defaultSize => const Size(4, 3);

  // WebView-specific state variables
  String url = '';
  List<Map<String, String>> signalKWebApps = [];
  bool loadingWebApps = false;

  @override
  void reset() {
    url = '';
    signalKWebApps = [];
    loadingWebApps = false;
  }

  @override
  void loadDefaults(SignalKService signalKService) {
    reset();
  }

  @override
  void loadFromTool(Tool tool) {
    final style = tool.config.style;
    if (style.customProperties != null) {
      url = style.customProperties!['url'] as String? ?? '';
    }
  }

  @override
  ToolConfig getConfig() {
    return ToolConfig(
      dataSources: const [],
      style: StyleConfig(
        customProperties: {
          'url': url,
        },
      ),
    );
  }

  @override
  String? validate() {
    if (url.trim().isEmpty) {
      return 'URL is required';
    }
    return null;
  }

  /// Load available SignalK webapps from the server
  Future<void> loadWebApps(SignalKService signalKService, StateSetter setState) async {
    setState(() => loadingWebApps = true);

    try {
      final webapps = await ToolConfigService.loadSignalKWebApps(signalKService);
      setState(() {
        signalKWebApps = webapps;
        loadingWebApps = false;
      });
    } catch (e) {
      setState(() => loadingWebApps = false);
      // Error will be handled by the UI layer
      rethrow;
    }
  }

  @override
  Widget buildConfigUI(BuildContext context, SignalKService signalKService) {
    return StatefulBuilder(
      builder: (context, setState) {
        // Load webapps on first display
        if (signalKWebApps.isEmpty && !loadingWebApps) {
          Future.microtask(() async {
            try {
              await loadWebApps(signalKService, setState);
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Failed to load SignalK webapps: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          });
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WebView Configuration',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),

              // URL Input
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Web Page URL',
                  border: OutlineInputBorder(),
                  hintText: 'Enter URL or select from SignalK webapps below',
                  helperText: 'Enter full URL or select from installed SignalK webapps',
                ),
                controller: TextEditingController(text: url),
                onChanged: (value) => url = value,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'URL is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // SignalK webapps section
              if (loadingWebApps)
                const Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 8),
                      Text(
                        'Loading SignalK webapps...',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                )
              else if (signalKWebApps.isNotEmpty) ...[
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Or select from SignalK webapps:',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        try {
                          await loadWebApps(signalKService, setState);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to load SignalK webapps: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Refresh'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: signalKWebApps.map((app) {
                    final isSelected = url == app['url'];
                    return FilterChip(
                      label: Text(app['name'] ?? 'Unknown'),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          url = selected ? app['url']! : '';
                        });
                      },
                      tooltip: app['description'],
                      avatar: isSelected ? const Icon(Icons.check, size: 16) : null,
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: 8),
              const Text(
                'Examples:\n'
                '• http://192.168.1.88:3000/@signalk/server-admin-ui\n'
                '• https://windy.com\n'
                '• http://192.168.1.88:3000/your-webapp',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        );
      },
    );
  }
}
