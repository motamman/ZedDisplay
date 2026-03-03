import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/historical_data.dart';
import '../services/historical_data_service.dart';
import '../services/signalk_service.dart';
import '../widgets/historical_line_chart.dart';

/// Screen for displaying historical data charts with up to 3 data series
class HistoricalChartScreen extends StatefulWidget {
  const HistoricalChartScreen({super.key});

  @override
  State<HistoricalChartScreen> createState() => _HistoricalChartScreenState();
}

class _HistoricalChartScreenState extends State<HistoricalChartScreen> {
  HistoricalDataService? _historicalService;
  List<ChartDataSeries> _chartSeries = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Configuration
  final List<String> _selectedPaths = [];
  String _selectedDuration = '1h';
  final List<String> _availablePaths = [];
  final Set<String> _pathsWithHistory = {}; // Paths that have historical data

  final Map<String, String> _durationOptions = {
    '15m': '15 minutes',
    '30m': '30 minutes',
    '1h': '1 hour',
    '2h': '2 hours',
    '6h': '6 hours',
    '12h': '12 hours',
    '1d': '1 day',
    '2d': '2 days',
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final signalkService = context.read<SignalKService>();

    if (_historicalService == null && signalkService.isConnected) {
      _historicalService = HistoricalDataService(
        serverUrl: signalkService.serverUrl,
        useSecureConnection: signalkService.useSecureConnection,
        authToken: signalkService.authToken,
      );
      _loadAvailablePaths();
    }
  }

  Future<void> _loadAvailablePaths() async {
    final signalkService = context.read<SignalKService>();

    // Get all paths with numeric values from SignalK live data
    final numericPaths = <String>[];
    for (final entry in signalkService.latestData.entries) {
      final path = entry.key;
      final value = entry.value.value;

      // Skip source-specific paths (contain ::)
      if (path.contains('::')) continue;

      // Only include paths with numeric values
      if (value is num) {
        numericPaths.add(path);
      }
    }
    numericPaths.sort();

    // Fetch paths that have historical data (for badge indicator)
    Set<String> historyPaths = {};
    if (_historicalService != null) {
      try {
        final paths = await _historicalService!.getAvailablePaths();
        historyPaths = paths.toSet();
      } catch (e) {
        debugPrint('Error loading history paths: $e');
      }
    }

    if (mounted) {
      setState(() {
        _availablePaths.clear();
        _availablePaths.addAll(numericPaths);
        _pathsWithHistory.clear();
        _pathsWithHistory.addAll(historyPaths);
      });
    }
  }

  Future<void> _fetchHistoricalData() async {
    if (_historicalService == null) {
      setState(() {
        _errorMessage = 'Historical data service not initialized';
      });
      return;
    }

    if (_selectedPaths.isEmpty) {
      setState(() {
        _errorMessage = 'Please select at least one data path';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _historicalService!.fetchHistoricalData(
        paths: _selectedPaths,
        duration: _selectedDuration,
        resolution: 60000, // 1 minute buckets
      );

      final series = <ChartDataSeries>[];
      final signalKService = context.read<SignalKService>();
      for (final path in _selectedPaths) {
        final chartSeries = ChartDataSeries.fromHistoricalData(
          response,
          path,
          signalKService: signalKService,
        );
        if (chartSeries != null) {
          series.add(chartSeries);
        }
      }

      setState(() {
        _chartSeries = series;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error fetching data: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historical Charts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchHistoricalData,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildConfigurationPanel(),
          Expanded(
            child: _buildChartArea(),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigurationPanel() {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chart Configuration',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            _buildPathSelector(),
            const SizedBox(height: 16),
            _buildDurationSelector(),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _fetchHistoricalData,
                icon: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.show_chart),
                label: Text(_isLoading ? 'Loading...' : 'Load Chart'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPathSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Select Data Paths (max 3):',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(width: 8),
            // Legend for history indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 12, color: Colors.green.shade700),
                  const SizedBox(width: 4),
                  Text(
                    'has history',
                    style: TextStyle(fontSize: 10, color: Colors.green.shade700),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Text(
              '${_selectedPaths.length}/3',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _availablePaths.map((path) {
            final isSelected = _selectedPaths.contains(path);
            final canSelect = _selectedPaths.length < 3 || isSelected;
            final hasHistory = _pathsWithHistory.contains(path);

            return FilterChip(
              avatar: hasHistory
                  ? Icon(
                      Icons.history,
                      size: 16,
                      color: isSelected ? Colors.white : Colors.green.shade700,
                    )
                  : null,
              label: Text(_formatPathLabel(path)),
              selected: isSelected,
              onSelected: canSelect
                  ? (selected) {
                      setState(() {
                        if (selected) {
                          _selectedPaths.add(path);
                        } else {
                          _selectedPaths.remove(path);
                        }
                      });
                    }
                  : null,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildDurationSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Time Duration:',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _selectedDuration,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
          ),
          items: _durationOptions.entries.map((entry) {
            return DropdownMenuItem(
              value: entry.key,
              child: Text(entry.value),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _selectedDuration = value;
              });
            }
          },
        ),
      ],
    );
  }

  Widget _buildChartArea() {
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchHistoricalData,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_chartSeries.isEmpty && !_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.show_chart,
              size: 64,
              color: Theme.of(context).disabledColor,
            ),
            const SizedBox(height: 16),
            Text(
              'Select paths and duration, then tap "Load Chart"',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: HistoricalLineChart(
        series: _chartSeries,
        title: 'Last ${_durationOptions[_selectedDuration]}',
        showLegend: true,
        showGrid: true,
      ),
    );
  }

  String _formatPathLabel(String path) {
    final parts = path.split('.');
    if (parts.length > 2) {
      return parts.sublist(parts.length - 2).join('.');
    }
    return path;
  }
}
