import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import '../../plugin_configurators/plugin_configurator_registry.dart';
import '../../services/signalk_service.dart';

/// Host widget for plugin configuration.
///
/// This tool checks if a native Flutter configurator exists for the plugin.
/// If yes, it displays the native configurator.
/// If no, it falls back to a WebView showing the SignalK admin UI.
///
/// Native configurators provide a better user experience:
/// - Faster loading
/// - Consistent app theming
/// - Custom validation
/// - Offline capability
///
/// Use the /build-plugin-config skill to generate native configurators.
class PluginConfigTool extends StatefulWidget {
  final SignalKService signalKService;
  final String pluginId;
  final String pluginName;
  final Map<String, dynamic>? initialConfig;

  const PluginConfigTool({
    super.key,
    required this.signalKService,
    required this.pluginId,
    required this.pluginName,
    this.initialConfig,
  });

  @override
  State<PluginConfigTool> createState() => _PluginConfigToolState();
}

class _PluginConfigToolState extends State<PluginConfigTool> {
  Map<String, dynamic>? _config;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    // If we have initial config and a native configurator, use it directly
    if (widget.initialConfig != null &&
        PluginConfiguratorRegistry.hasConfigurator(widget.pluginId)) {
      setState(() {
        _config = widget.initialConfig;
        _loading = false;
      });
      return;
    }

    // Otherwise fetch config from server
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final protocol =
          widget.signalKService.useSecureConnection ? 'https' : 'http';
      final url =
          '$protocol://${widget.signalKService.serverUrl}/skServer/plugins/${widget.pluginId}/config';

      final headers = <String, String>{};
      if (widget.signalKService.authToken != null) {
        headers['Authorization'] =
            'Bearer ${widget.signalKService.authToken!.token}';
      }

      final response = await http.get(Uri.parse(url), headers: headers);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _config = data['configuration'] as Map<String, dynamic>? ?? {};
            _loading = false;
          });
        }
      } else if (response.statusCode == 401) {
        if (mounted) {
          setState(() {
            _error = 'Not authorized. Admin permissions required.';
            _loading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'Failed to load config: ${response.statusCode}';
            _loading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error loading config: $e';
          _loading = false;
        });
      }
    }
  }

  String _buildPluginConfigUrl() {
    final protocol =
        widget.signalKService.useSecureConnection ? 'https' : 'http';
    return '$protocol://${widget.signalKService.serverUrl}/admin/#/serverConfiguration/plugins/${widget.pluginId}';
  }

  void _handleSaved() {
    // Reload config after save to show updated values
    _loadConfig();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuration saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.pluginName),
        actions: [
          // Show indicator if using native configurator
          if (PluginConfiguratorRegistry.hasConfigurator(widget.pluginId))
            const Tooltip(
              message: 'Native configurator',
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.bolt, color: Colors.amber),
              ),
            ),
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadConfig,
            tooltip: 'Reload configuration',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadConfig,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // Check if we have a native configurator
    if (PluginConfiguratorRegistry.hasConfigurator(widget.pluginId)) {
      return PluginConfiguratorRegistry.getConfigurator(
        pluginId: widget.pluginId,
        signalKService: widget.signalKService,
        initialConfig: _config ?? {},
        onSaved: _handleSaved,
      )!;
    }

    // Fall back to WebView
    return _WebViewFallback(
      url: _buildPluginConfigUrl(),
      authToken: widget.signalKService.authToken?.token,
      serverUrl: widget.signalKService.serverUrl,
    );
  }
}

/// WebView fallback for plugins without native configurators.
class _WebViewFallback extends StatefulWidget {
  final String url;
  final String? authToken;
  final String serverUrl;

  const _WebViewFallback({
    required this.url,
    this.authToken,
    required this.serverUrl,
  });

  @override
  State<_WebViewFallback> createState() => _WebViewFallbackState();
}

class _WebViewFallbackState extends State<_WebViewFallback> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (url) {
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            debugPrint('WebView error: ${error.description}');
          },
        ),
      );

    // Set auth cookie if user is authenticated
    if (widget.authToken != null) {
      final cookieManager = WebViewCookieManager();
      final uri = Uri.parse(widget.url);
      final domain = uri.host;

      await cookieManager.setCookie(
        WebViewCookie(
          name: 'JAUTHENTICATION',
          value: widget.authToken!,
          domain: domain,
          path: '/',
        ),
      );
    }

    await _controller.loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_isLoading)
          const Center(
            child: CircularProgressIndicator(),
          ),
      ],
    );
  }
}
