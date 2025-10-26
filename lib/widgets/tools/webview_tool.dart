import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';

/// WebView tool for embedding web pages in the dashboard
class WebViewTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const WebViewTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<WebViewTool> createState() => _WebViewToolState();
}

class _WebViewToolState extends State<WebViewTool> with AutomaticKeepAliveClientMixin {
  late final WebViewController _controller;
  bool _isLoading = true;
  String? _errorMessage;
  String? _currentUrl;
  bool _isLocked = false; // Lock mode for web interaction

  @override
  bool get wantKeepAlive => true; // Keep WebView alive when navigating away

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    // Get URL from config (stored in customProperties)
    _currentUrl = widget.config.style.customProperties?['url'] as String?;

    if (_currentUrl == null || _currentUrl!.isEmpty) {
      setState(() {
        _errorMessage = 'No URL configured';
        _isLoading = false;
      });
      return;
    }

    // Ensure URL has a protocol
    if (!_currentUrl!.startsWith('http://') && !_currentUrl!.startsWith('https://')) {
      _currentUrl = 'http://$_currentUrl';
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..enableZoom(true)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _errorMessage = null;
              });
            }
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          },
          onWebResourceError: (WebResourceError error) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _errorMessage = 'Failed to load page: ${error.description}';
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(_currentUrl!));
  }

  void _reload() {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    _controller.reload();
  }

  void _goBack() {
    _controller.goBack();
  }

  void _goForward() {
    _controller.goForward();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    if (_errorMessage != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_currentUrl == null || _currentUrl!.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.web, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No URL configured',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              'Edit this tool to set a web page URL',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        // WebView with full interaction enabled and gesture recognizers
        WebViewWidget(
          controller: _controller,
          gestureRecognizers: {
            Factory<VerticalDragGestureRecognizer>(
              () => VerticalDragGestureRecognizer(),
            ),
            Factory<HorizontalDragGestureRecognizer>(
              () => HorizontalDragGestureRecognizer(),
            ),
            Factory<ScaleGestureRecognizer>(
              () => ScaleGestureRecognizer(),
            ),
            Factory<TapGestureRecognizer>(
              () => TapGestureRecognizer(),
            ),
          },
        ),
        if (_isLoading)
          Container(
            color: Colors.black.withOpacity(0.1),
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          ),
        // Control bar at top
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 4,
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 20),
                  color: Colors.white,
                  onPressed: _goBack,
                  tooltip: 'Back',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.arrow_forward, size: 20),
                  color: Colors.white,
                  onPressed: _goForward,
                  tooltip: 'Forward',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  color: Colors.white,
                  onPressed: _reload,
                  tooltip: 'Reload',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                // Lock/Unlock button
                IconButton(
                  icon: Icon(
                    _isLocked ? Icons.lock : Icons.lock_open,
                    size: 20,
                  ),
                  color: _isLocked ? Colors.yellow : Colors.white,
                  onPressed: () {
                    setState(() {
                      _isLocked = !_isLocked;
                    });
                  },
                  tooltip: _isLocked ? 'Dashboard swipes blocked' : 'Dashboard swipes enabled',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _currentUrl!,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Lock indicator overlay
        if (_isLocked)
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.yellow.withOpacity(0.9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock, size: 14, color: Colors.black),
                  SizedBox(width: 4),
                  Text(
                    'Dashboard swipes disabled',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Builder for WebView tools
class WebViewToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'webview',
      name: 'Web Page',
      description: 'Embed a web page in the dashboard',
      category: ToolCategory.system,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: false,
        allowsMultiplePaths: false,
        minPaths: 0,
        maxPaths: 0,
        styleOptions: const ['url'],
      ),
    );
  }

  @override
  ToolConfig? getDefaultConfig(String vesselId) {
    return null;
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return WebViewTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
