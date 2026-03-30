import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';

/// Inactivity timeout before interactive mode auto-disengages.
const _inactivityTimeout = Duration(seconds: 10);

/// WebView tool for embedding web pages in the dashboard.
///
/// Long-press to enter interactive mode (full gesture control for the webview,
/// dashboard swiping disabled). After 10 seconds of no touch, interactive mode
/// auto-disengages and dashboard swiping resumes.
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
  bool _refreshVisible = true;
  Timer? _refreshFadeTimer;

  // Interactive mode — long-press to enable, auto-disables after inactivity
  bool _interactiveMode = false;
  Timer? _inactivityTimer;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  @override
  void dispose() {
    _refreshFadeTimer?.cancel();
    _inactivityTimer?.cancel();
    super.dispose();
  }

  void _initializeWebView() {
    _currentUrl = widget.config.style.customProperties?['url'] as String?;

    if (_currentUrl == null || _currentUrl!.isEmpty) {
      setState(() {
        _errorMessage = 'No URL configured';
        _isLoading = false;
      });
      return;
    }

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
              setState(() => _isLoading = false);
              _startRefreshFadeTimer();
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
      );

    _setAuthCookieAndLoad();
  }

  Future<void> _setAuthCookieAndLoad() async {
    final token = widget.signalKService.authToken?.token;
    if (token != null) {
      final uri = Uri.parse(_currentUrl!);
      final cookieManager = WebViewCookieManager();
      await cookieManager.setCookie(
        WebViewCookie(
          name: 'JAUTHENTICATION',
          value: token,
          domain: uri.host,
          path: '/',
        ),
      );
    }
    await _controller.loadRequest(Uri.parse(_currentUrl!));
  }

  void _reload() {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _refreshVisible = true;
    });
    _controller.reload();
  }

  void _startRefreshFadeTimer() {
    _refreshFadeTimer?.cancel();
    setState(() => _refreshVisible = true);
    _refreshFadeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _refreshVisible = false);
    });
  }

  void _showRefresh() {
    _startRefreshFadeTimer();
  }

  // --------------- Interactive mode ---------------

  void _enterInteractiveMode() {
    setState(() => _interactiveMode = true);
    _resetInactivityTimer();
  }

  void _exitInteractiveMode() {
    _inactivityTimer?.cancel();
    if (mounted) setState(() => _interactiveMode = false);
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_inactivityTimeout, _exitInteractiveMode);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

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
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.web, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No URL configured',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Edit this tool to set a web page URL',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // Gesture recognizers: full set when interactive, minimal when not
    final recognizers = <Factory<OneSequenceGestureRecognizer>>{
      Factory<TapGestureRecognizer>(() => TapGestureRecognizer()),
      Factory<LongPressGestureRecognizer>(() => LongPressGestureRecognizer()
        ..onLongPress = _enterInteractiveMode),
    };
    if (_interactiveMode) {
      recognizers.addAll({
        Factory<VerticalDragGestureRecognizer>(
          () => VerticalDragGestureRecognizer(),
        ),
        Factory<HorizontalDragGestureRecognizer>(
          () => HorizontalDragGestureRecognizer(),
        ),
        Factory<ScaleGestureRecognizer>(
          () => ScaleGestureRecognizer(),
        ),
      });
    }

    return Listener(
      // Any pointer activity resets the inactivity timer
      onPointerDown: (_) {
        if (_interactiveMode) _resetInactivityTimer();
      },
      onPointerMove: (_) {
        if (_interactiveMode) _resetInactivityTimer();
      },
      child: Container(
        decoration: _interactiveMode
            ? BoxDecoration(
                border: Border.all(color: Colors.green, width: 2),
              )
            : null,
        child: Stack(
          children: [
            WebViewWidget(
              key: ValueKey('webview_interactive_$_interactiveMode'),
              controller: _controller,
              gestureRecognizers: recognizers,
            ),
            if (_isLoading)
              Container(
                color: Colors.black.withValues(alpha: 0.1),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
            // Tap zone to reveal refresh button
            Positioned(
              top: 0,
              right: 0,
              width: 48,
              height: 48,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _showRefresh,
              ),
            ),
            // Floating refresh button
            Positioned(
              top: _interactiveMode ? 6 : 4,
              right: _interactiveMode ? 6 : 4,
              child: AnimatedOpacity(
                opacity: _refreshVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: GestureDetector(
                  onTap: _reload,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.refresh, size: 18, color: Colors.white70),
                  ),
                ),
              ),
            ),
            // Interactive mode hint (shown briefly when not interactive)
            if (!_interactiveMode && !_isLoading)
              Positioned(
                bottom: 4,
                left: 0,
                right: 0,
                child: Center(
                  child: AnimatedOpacity(
                    opacity: _refreshVisible ? 0.7 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Long-press for map control',
                        style: TextStyle(fontSize: 9, color: Colors.white60),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
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
        allowsDataSources: false,
        allowsUnitSelection: false,
        allowsVisibilityToggles: false,
        allowsTTL: false,
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
