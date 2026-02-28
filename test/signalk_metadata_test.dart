// SignalK Server Metadata Comparison Test
// Compares metadata/conversion behavior between two servers

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ServerConfig {
  final String name;
  final String host;
  final int port;
  final String username;
  final String password;
  String? token;

  ServerConfig({
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
  });

  String get baseUrl => 'http://$host:$port';
  String get wsUrl => 'ws://$host:$port';
}

class MetadataTestRunner {
  final ServerConfig server;
  late final HttpClient _httpClient;
  final List<Map<String, dynamic>> wsLog = [];
  WebSocket? _webSocket;
  final StringBuffer log = StringBuffer();

  MetadataTestRunner(this.server) {
    _httpClient = HttpClient();
    _httpClient.autoUncompress = true;
  }

  void _log(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final entry = '[$timestamp] [${server.name}] $message';
    print(entry);
    log.writeln(entry);
  }

  Future<Map<String, dynamic>?> _httpGet(String path) async {
    try {
      final headers = <String>[];
      if (server.token != null) {
        headers.addAll(['-H', 'Authorization: Bearer ${server.token}']);
      }
      final result = await Process.run('curl', [
        '-s',
        ...headers,
        '${server.baseUrl}$path',
      ]);

      if (result.exitCode == 0) {
        final body = result.stdout as String;
        if (body.isNotEmpty) {
          try {
            return jsonDecode(body) as Map<String, dynamic>;
          } catch (e) {
            _log('GET $path parse error: $e - body: ${body.substring(0, body.length > 100 ? 100 : body.length)}');
            return null;
          }
        }
      }
      _log('GET $path failed: ${result.stderr}');
      return null;
    } catch (e) {
      _log('GET $path error: $e');
      return null;
    }
  }

  Future<dynamic> _httpGetDynamic(String path) async {
    try {
      final headers = <String>[];
      if (server.token != null) {
        headers.addAll(['-H', 'Authorization: Bearer ${server.token}']);
      }
      final result = await Process.run('curl', [
        '-s',
        ...headers,
        '${server.baseUrl}$path',
      ]);

      if (result.exitCode == 0) {
        final body = result.stdout as String;
        if (body.isNotEmpty) {
          try {
            return jsonDecode(body);
          } catch (e) {
            _log('GET $path parse error: $e');
            return null;
          }
        }
      }
      _log('GET $path failed: ${result.stderr}');
      return null;
    } catch (e) {
      _log('GET $path error: $e');
      return null;
    }
  }

  Future<bool> authenticate() async {
    _log('Authenticating...');
    try {
      // Use Process to call curl for more reliable authentication
      final result = await Process.run('curl', [
        '-s',
        '-X', 'POST',
        '-H', 'Content-Type: application/json',
        '-d', jsonEncode({
          'username': server.username,
          'password': server.password,
        }),
        '${server.baseUrl}/signalk/v1/auth/login',
      ]);

      if (result.exitCode == 0) {
        final body = result.stdout as String;
        try {
          final data = jsonDecode(body) as Map<String, dynamic>;
          server.token = data['token'] as String?;
          if (server.token != null) {
            _log('Authentication successful, token obtained');
            return true;
          }
        } catch (e) {
          _log('Failed to parse auth response: $body');
        }
      }
      _log('Authentication failed: ${result.stdout}');
      return false;
    } catch (e) {
      _log('Authentication error: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> fetchAllMetadata() async {
    _log('Fetching all metadata endpoints...');
    final metadata = <String, dynamic>{};

    // Fetch unit preferences endpoints
    final endpoints = [
      '/signalk/v1/unitpreferences/config',
      '/signalk/v1/unitpreferences/categories',
      '/signalk/v1/unitpreferences/definitions',
      '/signalk/v1/unitpreferences/default-categories',
    ];

    for (final endpoint in endpoints) {
      final data = await _httpGetDynamic(endpoint);
      final key = endpoint.split('/').last;
      metadata[key] = data;
      _log('  $endpoint: ${data != null ? "OK" : "FAILED"}');
    }

    // Fetch active preset config to get preset name
    final config = metadata['config'] as Map<String, dynamic>?;
    if (config != null && config['activePreset'] != null) {
      final presetName = config['activePreset'];
      final presetData = await _httpGet('/signalk/v1/unitpreferences/presets/$presetName');
      metadata['activePresetDetails'] = presetData;
      _log('  /signalk/v1/unitpreferences/presets/$presetName: ${presetData != null ? "OK" : "FAILED"}');
    }

    // Fetch vessel data with metadata
    final vesselData = await _httpGet('/signalk/v1/api/vessels/self');
    metadata['vessels_self'] = vesselData;
    _log('  /signalk/v1/api/vessels/self: ${vesselData != null ? "OK" : "FAILED"}');

    // Also get full API data
    final fullApi = await _httpGet('/signalk/v1/api');
    metadata['full_api'] = fullApi;
    _log('  /signalk/v1/api: ${fullApi != null ? "OK" : "FAILED"}');

    return metadata;
  }

  Future<List<String>> getNumericPaths() async {
    _log('Getting all numeric paths...');
    final paths = <String>[];

    // Get all paths from the server
    final vesselData = await _httpGet('/signalk/v1/api/vessels/self');
    if (vesselData != null) {
      _extractPaths(vesselData, 'vessels.self', paths);
    }

    _log('Found ${paths.length} paths');
    return paths;
  }

  void _extractPaths(dynamic data, String currentPath, List<String> paths) {
    if (data is Map<String, dynamic>) {
      // Check if this is a leaf node with a value
      if (data.containsKey('value')) {
        final value = data['value'];
        if (value is num) {
          paths.add(currentPath);
        }
      }
      // Recurse into children
      for (final entry in data.entries) {
        if (entry.key != 'value' && entry.key != 'meta' && entry.key != '\$source' && entry.key != 'timestamp') {
          _extractPaths(entry.value, '$currentPath.${entry.key}', paths);
        }
      }
    }
  }

  Future<void> connectWebSocket(List<String> pathsToSubscribe) async {
    _log('Connecting WebSocket with sendMeta=all...');
    try {
      final wsUri = '${server.wsUrl}/signalk/v1/stream?subscribe=none&sendMeta=all&token=${server.token}';
      _webSocket = await WebSocket.connect(wsUri);
      _log('WebSocket connected');

      // Listen for messages
      _webSocket!.listen(
        (data) {
          final message = jsonDecode(data as String) as Map<String, dynamic>;
          final timestamp = DateTime.now().toIso8601String();

          // Log meta changes
          if (message.containsKey('updates')) {
            final updates = message['updates'] as List<dynamic>;
            for (final update in updates) {
              if (update is Map<String, dynamic> && update.containsKey('meta')) {
                final meta = update['meta'] as List<dynamic>;
                for (final m in meta) {
                  wsLog.add({
                    'timestamp': timestamp,
                    'type': 'meta',
                    'data': m,
                  });
                  _log('META: ${jsonEncode(m)}');
                }
              }
              if (update is Map<String, dynamic> && update.containsKey('values')) {
                final values = update['values'] as List<dynamic>;
                for (final v in values) {
                  if (v is Map<String, dynamic> && v.containsKey('meta')) {
                    wsLog.add({
                      'timestamp': timestamp,
                      'type': 'value_with_meta',
                      'data': v,
                    });
                    _log('VALUE_META: ${jsonEncode(v)}');
                  }
                }
              }
            }
          }
        },
        onError: (error) {
          _log('WebSocket error: $error');
        },
        onDone: () {
          _log('WebSocket closed');
        },
      );

      // Subscribe to all paths
      _log('Subscribing to ${pathsToSubscribe.length} paths...');
      final subscriptions = pathsToSubscribe.map((path) => {
        'path': path.replaceFirst('vessels.self.', ''),
        'period': 1000,
        'format': 'delta',
        'policy': 'instant',
        'minPeriod': 1000,
      }).toList();

      final subscribeMessage = jsonEncode({
        'context': 'vessels.self',
        'subscribe': subscriptions,
      });

      _webSocket!.add(subscribeMessage);
      _log('Subscription message sent');
    } catch (e) {
      _log('WebSocket connection error: $e');
    }
  }

  Future<void> closeWebSocket() async {
    if (_webSocket != null) {
      await _webSocket!.close();
      _webSocket = null;
      _log('WebSocket disconnected');
    }
  }

  void close() {
    _httpClient.close();
  }
}

Future<void> main() async {
  final outputDir = Directory('test/metadata_test_output');
  if (!outputDir.existsSync()) {
    outputDir.createSync(recursive: true);
  }

  final servers = [
    ServerConfig(
      name: 'localhost',
      host: 'localhost',
      port: 3000,
      username: 'maurice',
      password: 'Z3nn0r@~',
    ),
    ServerConfig(
      name: 'remote',
      host: 'zennora-brain-test',
      port: 3000,
      username: 'maurice',
      password: '0Nt7@Tda76r&',
    ),
  ];

  final runners = servers.map((s) => MetadataTestRunner(s)).toList();

  print('=' * 60);
  print('SignalK Server Metadata Comparison Test');
  print('=' * 60);
  print('');

  // Phase 1: Authenticate with both servers
  print('Phase 1: Authentication');
  print('-' * 40);
  final authResults = await Future.wait(
    runners.map((r) => r.authenticate()),
  );

  for (var i = 0; i < runners.length; i++) {
    if (!authResults[i]) {
      print('Failed to authenticate with ${servers[i].name}');
      return;
    }
  }
  print('');

  // Phase 2: Initial REST API Metadata Capture
  print('Phase 2: Initial REST API Metadata Capture');
  print('-' * 40);
  final initialMetadata = await Future.wait(
    runners.map((r) => r.fetchAllMetadata()),
  );

  // Save initial metadata
  for (var i = 0; i < runners.length; i++) {
    final file = File('${outputDir.path}/${servers[i].name}_initial.json');
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(initialMetadata[i]),
    );
    print('Saved ${file.path}');
  }
  print('');

  // Phase 3: Get all numeric paths
  print('Phase 3: Getting numeric paths');
  print('-' * 40);
  final allPaths = await Future.wait(
    runners.map((r) => r.getNumericPaths()),
  );

  // Combine unique paths from both servers
  final combinedPaths = <String>{};
  for (final pathList in allPaths) {
    combinedPaths.addAll(pathList);
  }
  print('Combined unique paths: ${combinedPaths.length}');
  print('');

  // Phase 4: WebSocket connection with meta monitoring
  print('Phase 4: WebSocket Connection with sendMeta=all');
  print('-' * 40);
  await Future.wait(
    runners.map((r) => r.connectWebSocket(combinedPaths.toList())),
  );
  print('');

  // Phase 5: Monitor for 5 minutes
  print('Phase 5: Monitoring for 5 minutes');
  print('-' * 40);
  print('Please toggle display unit preferences on each server...');
  print('');

  const monitorDuration = Duration(minutes: 5);
  final startTime = DateTime.now();

  // Show countdown
  await for (final _ in Stream.periodic(const Duration(seconds: 30))) {
    final elapsed = DateTime.now().difference(startTime);
    final remaining = monitorDuration - elapsed;
    if (remaining.isNegative) break;
    print('Monitoring... ${remaining.inMinutes}m ${remaining.inSeconds % 60}s remaining');
  }

  print('');

  // Phase 6: Close WebSockets
  print('Phase 6: Closing WebSocket connections');
  print('-' * 40);
  await Future.wait(
    runners.map((r) => r.closeWebSocket()),
  );
  print('');

  // Phase 7: Final REST API Metadata Capture
  print('Phase 7: Final REST API Metadata Capture');
  print('-' * 40);
  final finalMetadata = await Future.wait(
    runners.map((r) => r.fetchAllMetadata()),
  );

  // Save final metadata
  for (var i = 0; i < runners.length; i++) {
    final file = File('${outputDir.path}/${servers[i].name}_final.json');
    file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(finalMetadata[i]),
    );
    print('Saved ${file.path}');
  }
  print('');

  // Save WebSocket logs
  for (var i = 0; i < runners.length; i++) {
    final file = File('${outputDir.path}/${servers[i].name}_websocket.log');
    file.writeAsStringSync(runners[i].log.toString());
    print('Saved ${file.path}');

    final wsLogFile = File('${outputDir.path}/${servers[i].name}_websocket_meta.json');
    wsLogFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(runners[i].wsLog),
    );
    print('Saved ${wsLogFile.path}');
  }
  print('');

  // Phase 8: Generate comparison report
  print('Phase 8: Generating Comparison Report');
  print('-' * 40);

  final report = StringBuffer();
  report.writeln('# SignalK Server Metadata Comparison Report');
  report.writeln('');
  report.writeln('Generated: ${DateTime.now().toIso8601String()}');
  report.writeln('');
  report.writeln('## Servers Compared');
  report.writeln('');
  report.writeln('| Server | URL |');
  report.writeln('|--------|-----|');
  for (final server in servers) {
    report.writeln('| ${server.name} | ${server.baseUrl} |');
  }
  report.writeln('');

  // Compare active preset configuration
  report.writeln('## 1. Active Preset Configuration');
  report.writeln('');
  for (var i = 0; i < servers.length; i++) {
    final config = initialMetadata[i]['config'];
    report.writeln('### ${servers[i].name}');
    report.writeln('```json');
    report.writeln(const JsonEncoder.withIndent('  ').convert(config));
    report.writeln('```');
    report.writeln('');
  }

  // Compare unit definitions availability
  report.writeln('## 2. Unit Definitions Availability');
  report.writeln('');
  report.writeln('| Server | Definitions Count | Has Definitions |');
  report.writeln('|--------|------------------|-----------------|');
  for (var i = 0; i < servers.length; i++) {
    final definitions = initialMetadata[i]['definitions'];
    final count = definitions is Map ? definitions.length : 0;
    final hasDefinitions = definitions != null && count > 0;
    report.writeln('| ${servers[i].name} | $count | $hasDefinitions |');
  }
  report.writeln('');

  // Compare categories
  report.writeln('## 3. Categories');
  report.writeln('');
  for (var i = 0; i < servers.length; i++) {
    final categories = initialMetadata[i]['categories'];
    report.writeln('### ${servers[i].name}');
    report.writeln('```json');
    report.writeln(const JsonEncoder.withIndent('  ').convert(categories));
    report.writeln('```');
    report.writeln('');
  }

  // Compare default categories
  report.writeln('## 4. Default Categories (Path Patterns)');
  report.writeln('');
  for (var i = 0; i < servers.length; i++) {
    final defaultCats = initialMetadata[i]['default-categories'];
    final count = defaultCats is List ? defaultCats.length : (defaultCats is Map ? defaultCats.length : 0);
    report.writeln('### ${servers[i].name} ($count entries)');
    report.writeln('```json');
    report.writeln(const JsonEncoder.withIndent('  ').convert(defaultCats));
    report.writeln('```');
    report.writeln('');
  }

  // Compare WebSocket meta delivery
  report.writeln('## 5. WebSocket Meta Delivery');
  report.writeln('');
  report.writeln('| Server | Meta Messages Received |');
  report.writeln('|--------|----------------------|');
  for (var i = 0; i < runners.length; i++) {
    report.writeln('| ${servers[i].name} | ${runners[i].wsLog.length} |');
  }
  report.writeln('');

  // Sample meta messages
  report.writeln('### Sample Meta Messages');
  report.writeln('');
  for (var i = 0; i < runners.length; i++) {
    report.writeln('#### ${servers[i].name}');
    if (runners[i].wsLog.isEmpty) {
      report.writeln('No meta messages received.');
    } else {
      report.writeln('```json');
      final sample = runners[i].wsLog.take(5).toList();
      report.writeln(const JsonEncoder.withIndent('  ').convert(sample));
      report.writeln('```');
    }
    report.writeln('');
  }

  // Differences in metadata between initial and final
  report.writeln('## 6. Metadata Changes During Monitoring');
  report.writeln('');
  for (var i = 0; i < servers.length; i++) {
    report.writeln('### ${servers[i].name}');
    final initial = initialMetadata[i]['config'];
    final final_ = finalMetadata[i]['config'];
    if (jsonEncode(initial) == jsonEncode(final_)) {
      report.writeln('No changes detected in config.');
    } else {
      report.writeln('Config changed:');
      report.writeln('**Initial:**');
      report.writeln('```json');
      report.writeln(const JsonEncoder.withIndent('  ').convert(initial));
      report.writeln('```');
      report.writeln('**Final:**');
      report.writeln('```json');
      report.writeln(const JsonEncoder.withIndent('  ').convert(final_));
      report.writeln('```');
    }
    report.writeln('');
  }

  // Look for displayUnits in vessels/self data
  report.writeln('## 7. DisplayUnits in Vessel Data');
  report.writeln('');
  for (var i = 0; i < servers.length; i++) {
    report.writeln('### ${servers[i].name}');
    final vesselData = initialMetadata[i]['vessels_self'];
    final displayUnits = <String, dynamic>{};
    _findDisplayUnits(vesselData, '', displayUnits);
    if (displayUnits.isEmpty) {
      report.writeln('No displayUnits found in vessel data.');
    } else {
      report.writeln('Found ${displayUnits.length} paths with displayUnits:');
      report.writeln('```json');
      report.writeln(const JsonEncoder.withIndent('  ').convert(displayUnits));
      report.writeln('```');
    }
    report.writeln('');
  }

  // Save report
  final reportFile = File('${outputDir.path}/comparison_report.md');
  reportFile.writeAsStringSync(report.toString());
  print('Saved ${reportFile.path}');
  print('');

  // Clean up
  for (final runner in runners) {
    runner.close();
  }

  print('=' * 60);
  print('Test Complete!');
  print('=' * 60);
  print('');
  print('Output files saved to: ${outputDir.path}');
}

void _findDisplayUnits(dynamic data, String path, Map<String, dynamic> results) {
  if (data is Map<String, dynamic>) {
    if (data.containsKey('meta') && data['meta'] is Map) {
      final meta = data['meta'] as Map<String, dynamic>;
      if (meta.containsKey('displayUnits')) {
        results[path] = meta['displayUnits'];
      }
    }
    for (final entry in data.entries) {
      if (entry.key != 'value' && entry.key != 'meta' && entry.key != '\$source' && entry.key != 'timestamp') {
        final newPath = path.isEmpty ? entry.key : '$path.${entry.key}';
        _findDisplayUnits(entry.value, newPath, results);
      }
    }
  }
}
