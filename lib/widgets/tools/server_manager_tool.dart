import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';

/// Tool for managing and monitoring the SignalK server
class ServerManagerTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const ServerManagerTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<ServerManagerTool> createState() => _ServerManagerToolState();
}

class _ServerManagerToolState extends State<ServerManagerTool> {
  WebSocketChannel? _wsChannel;
  StreamSubscription? _subscription;

  // Server statistics
  double _deltaRate = 0;
  int _numberOfPaths = 0;
  int _wsClients = 0;
  double _uptime = 0;
  Map<String, dynamic> _providerStats = {};

  // Plugins and webapps
  List<Map<String, dynamic>> _plugins = [];
  List<Map<String, dynamic>> _webapps = [];
  bool _loadingPlugins = false;
  bool _loadingWebapps = false;

  // Unit preferences
  List<Map<String, dynamic>> _availablePresets = [];
  String? _activePreset;
  bool _loadingPresets = false;

  @override
  void initState() {
    super.initState();
    _setupServerEventsListener();
    _loadPluginsAndWebapps();
    _loadUnitPresets();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _wsChannel?.sink.close();
    super.dispose();
  }

  void _setupServerEventsListener() async {
    if (!widget.signalKService.isConnected) return;

    try {
      // Create WebSocket connection for server events
      final protocol = widget.signalKService.useSecureConnection ? 'wss' : 'ws';
      final wsUrl = '$protocol://${widget.signalKService.serverUrl}/signalk/v1/stream?subscribe=none&serverevents=all';

      if (widget.signalKService.authToken != null) {
        final headers = <String, String>{
          'Authorization': 'Bearer ${widget.signalKService.authToken!.token}',
        };
        final socket = await WebSocket.connect(wsUrl, headers: headers);
        socket.pingInterval = const Duration(seconds: 30);
        _wsChannel = IOWebSocketChannel(socket);
      } else {
        _wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      }

      // Listen to server events
      _subscription = _wsChannel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message);

            // Check if this is a server statistics event
            if (data is Map && data['type'] == 'SERVERSTATISTICS') {
              final stats = data['data'] as Map<String, dynamic>?;
              if (stats != null && mounted) {
                setState(() {
                  _deltaRate = (stats['deltaRate'] as num?)?.toDouble() ?? 0;
                  _numberOfPaths = (stats['numberOfAvailablePaths'] as num?)?.toInt() ?? 0;
                  _wsClients = (stats['wsClients'] as num?)?.toInt() ?? 0;
                  _uptime = (stats['uptime'] as num?)?.toDouble() ?? 0;
                  _providerStats = stats['providerStatistics'] as Map<String, dynamic>? ?? {};
                });
              }
            }
          } catch (e) {
            debugPrint('Error parsing server event: $e');
          }
        },
        onError: (error) {
          debugPrint('Server events WebSocket error: $error');
        },
        onDone: () {
          debugPrint('Server events WebSocket disconnected');
        },
      );
    } catch (e) {
      debugPrint('Error setting up server events listener: $e');
    }
  }

  Future<void> _loadPluginsAndWebapps() async {
    await Future.wait([
      _loadPlugins(),
      _loadWebapps(),
    ]);
  }

  Future<void> _loadPlugins() async {
    if (!widget.signalKService.isConnected) return;

    if (mounted) {
      setState(() => _loadingPlugins = true);
    }

    try {
      final protocol = widget.signalKService.useSecureConnection ? 'https' : 'http';
      final url = '$protocol://${widget.signalKService.serverUrl}/signalk/v2/features';

      final headers = <String, String>{};
      if (widget.signalKService.authToken != null) {
        headers['Authorization'] = 'Bearer ${widget.signalKService.authToken!.token}';
      }

      final response = await http.get(Uri.parse(url), headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final plugins = data['plugins'] as List<dynamic>? ?? [];

        if (mounted) {
          setState(() {
            _plugins = plugins.cast<Map<String, dynamic>>();
            _loadingPlugins = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading plugins: $e');
      if (mounted) {
        setState(() => _loadingPlugins = false);
      }
    }
  }

  Future<void> _togglePlugin(String pluginId, bool currentlyEnabled) async {
    debugPrint('🔄 Toggling plugin: $pluginId, current state: $currentlyEnabled');

    if (!widget.signalKService.isConnected) {
      debugPrint('❌ Not connected to SignalK');
      return;
    }

    // Optimistically update UI immediately
    setState(() {
      final index = _plugins.indexWhere((p) => p['id'] == pluginId);
      if (index != -1) {
        // Create a new mutable map since JSON maps are unmodifiable
        _plugins[index] = Map<String, dynamic>.from(_plugins[index])
          ..['enabled'] = !currentlyEnabled;
      }
    });

    try {
      final protocol = widget.signalKService.useSecureConnection ? 'https' : 'http';
      final configUrl = '$protocol://${widget.signalKService.serverUrl}/skServer/plugins/$pluginId/config';

      final headers = <String, String>{
        'Content-Type': 'application/json',
      };

      // Use bearer token for authentication
      if (widget.signalKService.authToken != null) {
        headers['Authorization'] = 'Bearer ${widget.signalKService.authToken!.token}';
      }

      // Get current config
      debugPrint('📥 Getting config from: $configUrl');
      final getResponse = await http.get(Uri.parse(configUrl), headers: headers);
      debugPrint('📥 GET response: ${getResponse.statusCode}');

      if (getResponse.statusCode == 401) {
        // Revert optimistic update
        if (mounted) {
          setState(() {
            final index = _plugins.indexWhere((p) => p['id'] == pluginId);
            if (index != -1) {
              _plugins[index] = Map<String, dynamic>.from(_plugins[index])
                ..['enabled'] = currentlyEnabled;
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Not authorized. Token needs admin permissions.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      if (getResponse.statusCode == 200) {
        final config = jsonDecode(getResponse.body) as Map<String, dynamic>;

        // Toggle enabled state
        config['enabled'] = !currentlyEnabled;

        // Save updated config
        debugPrint('📤 Sending POST with enabled=${config['enabled']}');
        final postResponse = await http.post(
          Uri.parse(configUrl),
          headers: headers,
          body: jsonEncode(config),
        );
        debugPrint('📤 POST response: ${postResponse.statusCode}');

        if (mounted) {
          if (postResponse.statusCode == 200) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  currentlyEnabled
                      ? 'Plugin disabled. Server is restarting the plugin...'
                      : 'Plugin enabled. Server is starting the plugin...',
                ),
              ),
            );
            // Reload plugins after a short delay to confirm server state
            await Future.delayed(const Duration(milliseconds: 1500));
            _loadPlugins();
          } else if (postResponse.statusCode == 401) {
            // Revert optimistic update on auth failure
            setState(() {
              final index = _plugins.indexWhere((p) => p['id'] == pluginId);
              if (index != -1) {
                _plugins[index] = Map<String, dynamic>.from(_plugins[index])
                  ..['enabled'] = currentlyEnabled;
              }
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Not authorized. Token needs admin permissions.'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
              ),
            );
          } else {
            // Revert optimistic update on failure
            setState(() {
              final index = _plugins.indexWhere((p) => p['id'] == pluginId);
              if (index != -1) {
                _plugins[index] = Map<String, dynamic>.from(_plugins[index])
                  ..['enabled'] = currentlyEnabled;
              }
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to toggle plugin: ${postResponse.statusCode}')),
            );
          }
        }
      }
    } catch (e) {
      // Revert optimistic update on error
      if (mounted) {
        setState(() {
          final index = _plugins.indexWhere((p) => p['id'] == pluginId);
          if (index != -1) {
            _plugins[index] = Map<String, dynamic>.from(_plugins[index])
              ..['enabled'] = currentlyEnabled;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error toggling plugin: $e')),
        );
      }
    }
  }

  Future<void> _loadWebapps() async {
    if (!widget.signalKService.isConnected) return;

    if (mounted) {
      setState(() => _loadingWebapps = true);
    }

    try {
      final protocol = widget.signalKService.useSecureConnection ? 'https' : 'http';
      final url = '$protocol://${widget.signalKService.serverUrl}/signalk/v1/apps/list';

      final headers = <String, String>{};
      if (widget.signalKService.authToken != null) {
        headers['Authorization'] = 'Bearer ${widget.signalKService.authToken!.token}';
      }

      final response = await http.get(Uri.parse(url), headers: headers);

      if (response.statusCode == 200) {
        final webapps = jsonDecode(response.body) as List<dynamic>;

        if (mounted) {
          setState(() {
            _webapps = webapps.cast<Map<String, dynamic>>();
            _loadingWebapps = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading webapps: $e');
      if (mounted) {
        setState(() => _loadingWebapps = false);
      }
    }
  }

  Future<void> _loadUnitPresets() async {
    if (!widget.signalKService.isConnected) return;

    setState(() => _loadingPresets = true);

    final protocol = widget.signalKService.useSecureConnection ? 'https' : 'http';
    final headers = <String, String>{};
    if (widget.signalKService.authToken != null) {
      headers['Authorization'] = 'Bearer ${widget.signalKService.authToken!.token}';
    }

    try {
      // Fetch available presets
      final presetsResponse = await http.get(
        Uri.parse('$protocol://${widget.signalKService.serverUrl}/signalk/v1/unitpreferences/presets'),
        headers: headers,
      );

      // Try user-specific preferences first, then fall back to global config
      String? activePreset;

      // Try user applicationData first (user-specific preference)
      final userResponse = await http.get(
        Uri.parse('$protocol://${widget.signalKService.serverUrl}/signalk/v1/applicationData/user/unitpreferences/1.0.0'),
        headers: headers,
      );
      if (userResponse.statusCode == 200) {
        final userConfig = jsonDecode(userResponse.body);
        activePreset = userConfig['activePreset'] as String?;
      }

      // Fall back to global config if no user preference
      if (activePreset == null || activePreset.isEmpty) {
        final configResponse = await http.get(
          Uri.parse('$protocol://${widget.signalKService.serverUrl}/signalk/v1/unitpreferences/config'),
          headers: headers,
        );
        if (configResponse.statusCode == 200) {
          final config = jsonDecode(configResponse.body);
          activePreset = config['activePreset'] as String?;
        }
      }

      if (mounted) {
        setState(() {
          if (presetsResponse.statusCode == 200) {
            final data = jsonDecode(presetsResponse.body) as Map<String, dynamic>;
            // Combine builtIn and custom presets
            final builtIn = (data['builtIn'] as List?)?.cast<Map<String, dynamic>>() ?? [];
            final custom = (data['custom'] as List?)?.cast<Map<String, dynamic>>() ?? [];
            _availablePresets = [...builtIn, ...custom];
          }
          _activePreset = activePreset;
          _loadingPresets = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading unit presets: $e');
      if (mounted) setState(() => _loadingPresets = false);
    }
  }

  Future<void> _setActivePreset(String presetName) async {
    if (!widget.signalKService.isConnected) return;

    final previousPreset = _activePreset;
    setState(() => _activePreset = presetName); // Optimistic update

    final protocol = widget.signalKService.useSecureConnection ? 'https' : 'http';
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (widget.signalKService.authToken != null) {
      headers['Authorization'] = 'Bearer ${widget.signalKService.authToken!.token}';
    }

    try {
      // Save to user's applicationData (user-specific preference)
      final response = await http.post(
        Uri.parse('$protocol://${widget.signalKService.serverUrl}/signalk/v1/applicationData/user/unitpreferences/1.0.0'),
        headers: headers,
        body: jsonEncode({'activePreset': presetName}),
      );

      if (response.statusCode == 200) {
        // Refresh conversions to apply new preset
        await widget.signalKService.loadConversions();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Unit preset changed to "$presetName"')),
          );
        }
      } else if (response.statusCode == 401) {
        setState(() => _activePreset = previousPreset); // Revert
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Not authorized to change unit preferences'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        setState(() => _activePreset = previousPreset); // Revert
      }
    } catch (e) {
      setState(() => _activePreset = previousPreset); // Revert
      debugPrint('Error setting unit preset: $e');
    }
  }

  Future<void> _restartServer() async {
    if (!widget.signalKService.isConnected) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restart Server'),
        content: const Text('Are you sure you want to restart the SignalK server?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('RESTART'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final protocol = widget.signalKService.useSecureConnection ? 'https' : 'http';
      final url = '$protocol://${widget.signalKService.serverUrl}/skServer/restart';

      final headers = <String, String>{};
      if (widget.signalKService.authToken != null) {
        headers['Authorization'] = 'Bearer ${widget.signalKService.authToken!.token}';
      }

      final response = await http.put(Uri.parse(url), headers: headers);

      if (mounted) {
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Server restarting...')),
          );
        } else if (response.statusCode == 401) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Not authorized to restart server')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to restart: ${response.statusCode}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  String _formatUptime(double seconds) {
    final duration = Duration(seconds: seconds.toInt());
    final days = duration.inDays;
    final hours = duration.inHours % 24;
    final minutes = duration.inMinutes % 60;

    if (days > 0) {
      return '${days}d ${hours}h ${minutes}m';
    } else if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SizedBox(
            height: constraints.maxHeight,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            // Header with restart button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Server Status',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _restartServer,
                  icon: const Icon(Icons.restart_alt, size: 16),
                  label: const Text('Restart', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Server Statistics
            _buildStatisticsSection(theme),

            const SizedBox(height: 8),

            // Unit Preferences
            _buildUnitPreferencesSection(theme),

            const SizedBox(height: 8),

                  // Providers section - full width
                  SizedBox(
                    height: 120,
                    child: _buildScrollableProvidersSection(theme),
                  ),

                  const SizedBox(height: 8),

                  // Plugins and Webapps - half width each, below providers
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Plugins Section - left half
                        Expanded(
                          child: _buildScrollablePluginsSection(theme),
                        ),

                        const SizedBox(width: 8),

                        // Webapps Section - right half
                        Expanded(
                          child: _buildScrollableWebappsSection(theme),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatisticsSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Statistics',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Uptime',
                _formatUptime(_uptime),
                Icons.access_time,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildStatCard(
                'Delta Rate',
                '${_deltaRate.toStringAsFixed(1)}/s',
                Icons.speed,
                Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Paths',
                _numberOfPaths.toString(),
                Icons.route,
                Colors.purple,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _buildStatCard(
                'Clients',
                _wsClients.toString(),
                Icons.people,
                Colors.orange,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnitPreferencesSection(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.teal.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(6),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.straighten, size: 14, color: Colors.teal),
                const SizedBox(width: 8),
                const Text(
                  'Unit Preferences',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_loadingPresets)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  InkWell(
                    onTap: _loadUnitPresets,
                    child: const Icon(Icons.refresh, size: 14),
                  ),
              ],
            ),
          ),
          // Dropdown
          Padding(
            padding: const EdgeInsets.all(8),
            child: _availablePresets.isEmpty
                ? Text(
                    _loadingPresets ? 'Loading...' : 'No presets available',
                    style: const TextStyle(fontSize: 11),
                  )
                : DropdownButton<String>(
                    value: _activePreset,
                    isExpanded: true,
                    underline: const SizedBox(),
                    items: _availablePresets
                        .map((preset) => DropdownMenuItem(
                              value: preset['name'] as String?,
                              child: Text(
                                preset['displayName'] as String? ?? preset['name'] as String? ?? 'Unknown',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null && value != _activePreset) {
                        _setActivePreset(value);
                      }
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollableProvidersSection(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha:0.3)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha:0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(6),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.dns, size: 14, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Data Providers (${_providerStats.length})',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Scrollable list
          Expanded(
            child: _providerStats.isEmpty
                ? const Center(
                    child: Text('No providers', style: TextStyle(fontSize: 10)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(6),
                    itemCount: _providerStats.length,
                    itemBuilder: (context, index) {
                      final entry = _providerStats.entries.elementAt(index);
                      final stats = entry.value as Map<String, dynamic>;
                      final deltaRate = (stats['deltaRate'] as num?)?.toDouble() ?? 0;
                      final deltaCount = (stats['deltaCount'] as num?)?.toInt() ?? 0;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha:0.05),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Text(
                                  entry.key,
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 60,
                                child: Text(
                                  '${deltaRate.toStringAsFixed(1)}/s',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: theme.textTheme.bodySmall?.color,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                              const SizedBox(width: 12),
                              SizedBox(
                                width: 70,
                                child: Text(
                                  '$deltaCount deltas',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: theme.textTheme.bodySmall?.color,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollablePluginsSection(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha:0.3)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          // Compact header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha:0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(6),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.extension, size: 14, color: Colors.green),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Plugins (${_plugins.length})',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_loadingPlugins)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  InkWell(
                    onTap: _loadPlugins,
                    child: const Icon(Icons.refresh, size: 14),
                  ),
              ],
            ),
          ),
          // Scrollable list
          Expanded(
            child: _plugins.isEmpty && !_loadingPlugins
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('No plugins loaded', style: TextStyle(fontSize: 10)),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(6),
                    itemCount: _plugins.length,
                    itemBuilder: (context, index) {
                      final plugin = _plugins[index];
                      final id = plugin['id'] as String? ?? 'Unknown';
                      final name = plugin['name'] as String? ?? id;
                      final enabled = plugin['enabled'] as bool? ?? false;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Container(
                          decoration: BoxDecoration(
                            color: enabled
                                ? Colors.green.withValues(alpha:0.1)
                                : Colors.grey.withValues(alpha:0.05),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: InkWell(
                                    onTap: () => _togglePlugin(id, enabled),
                                    child: Text(
                                      name,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: enabled ? FontWeight.w500 : FontWeight.normal,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Transform.scale(
                                  scale: 0.8,
                                  child: Switch(
                                    value: enabled,
                                    onChanged: (_) => _togglePlugin(id, enabled),
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollableWebappsSection(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha:0.3)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          // Compact header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha:0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(6),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.web, size: 14, color: Colors.purple),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Webapps (${_webapps.length})',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_loadingWebapps)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  InkWell(
                    onTap: _loadWebapps,
                    child: const Icon(Icons.refresh, size: 14),
                  ),
              ],
            ),
          ),
          // Scrollable list
          Expanded(
            child: _webapps.isEmpty && !_loadingWebapps
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('No webapps found', style: TextStyle(fontSize: 10)),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(6),
                    itemCount: _webapps.length,
                    itemBuilder: (context, index) {
                      final webapp = _webapps[index];
                      final name = webapp['name'] as String? ?? 'Unknown';
                      final version = webapp['version'] as String? ?? '';

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha:0.05),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(fontSize: 11),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                version,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: theme.textTheme.bodySmall?.color,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

}

/// Builder for server manager tool
class ServerManagerToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'server_manager',
      name: 'Server Status',
      description: 'Monitor and manage the SignalK server - view statistics, restart server, manage plugins and webapps',
      category: ToolCategory.system,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: false,
        allowsMultiplePaths: false,
        minPaths: 0,
        maxPaths: 0,
        styleOptions: const [],
      ),
    );
  }

  @override
  ToolConfig? getDefaultConfig(String vesselId) {
    return ToolConfig(
      vesselId: vesselId,
      dataSources: [], // No data sources needed
      style: StyleConfig(),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return ServerManagerTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
