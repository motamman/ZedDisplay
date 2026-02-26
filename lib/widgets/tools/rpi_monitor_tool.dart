import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/conversion_utils.dart';

/// Tool for monitoring Raspberry Pi system metrics
/// Requires signalk-rpi-monitor and signalk-rpi-uptime plugins
class RpiMonitorTool extends StatelessWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const RpiMonitorTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Get CPU metrics
    final cpuUtil = ConversionUtils.getRawValue(
      signalKService,
      'environment.rpi.cpu.utilisation',
    );
    final core1Util = ConversionUtils.getRawValue(
      signalKService,
      'environment.rpi.cpu.core.1.utilisation',
    );
    final core2Util = ConversionUtils.getRawValue(
      signalKService,
      'environment.rpi.cpu.core.2.utilisation',
    );
    final core3Util = ConversionUtils.getRawValue(
      signalKService,
      'environment.rpi.cpu.core.3.utilisation',
    );
    final core4Util = ConversionUtils.getRawValue(
      signalKService,
      'environment.rpi.cpu.core.4.utilisation',
    );

    // Get temperature metrics
    // Use raw Kelvin values for color thresholds, formatted values for display
    final cpuTempK = ConversionUtils.getRawValue(
      signalKService,
      'environment.rpi.cpu.temperature',
    );
    final cpuTempFormatted = cpuTempK != null
        ? ConversionUtils.formatValue(
            signalKService,
            'environment.rpi.cpu.temperature',
            cpuTempK,
          )
        : null;

    final gpuTempK = ConversionUtils.getRawValue(
      signalKService,
      'environment.rpi.gpu.temperature',
    );
    final gpuTempFormatted = gpuTempK != null
        ? ConversionUtils.formatValue(
            signalKService,
            'environment.rpi.gpu.temperature',
            gpuTempK,
          )
        : null;

    // Get uptime (in seconds)
    final uptimeSeconds = ConversionUtils.getRawValue(
      signalKService,
      'environment.rpi.uptime',
    );

    // Get memory and storage (if available)
    final memoryUtil = ConversionUtils.getRawValue(
      signalKService,
      'environment.rpi.memory.utilisation',
    );
    final storageUtil = ConversionUtils.getRawValue(
      signalKService,
      'environment.rpi.storage.utilisation',
    );

    // Check if we have any data
    final hasData = cpuUtil != null ||
        cpuTempK != null ||
        gpuTempK != null ||
        uptimeSeconds != null;

    // No data message
    if (!hasData) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(Icons.memory, color: theme.colorScheme.primary, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    'Raspberry Pi Monitor',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 48,
                        color: theme.disabledColor,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No RPi monitoring data available',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.disabledColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Install signalk-rpi-monitor and\nsignalk-rpi-uptime plugins',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.disabledColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Responsive layout for data sections
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 600;

            final leftColumn = _buildLeftColumn(
              theme: theme,
              cpuUtil: cpuUtil,
              core1Util: core1Util,
              core2Util: core2Util,
              core3Util: core3Util,
              core4Util: core4Util,
            );

            final rightColumn = _buildRightColumn(
              theme: theme,
              cpuTempK: cpuTempK,
              cpuTempFormatted: cpuTempFormatted,
              gpuTempK: gpuTempK,
              gpuTempFormatted: gpuTempFormatted,
              memoryUtil: memoryUtil,
              storageUtil: storageUtil,
              uptimeSeconds: uptimeSeconds,
            );

            if (isWide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: leftColumn),
                  const SizedBox(width: 16),
                  Expanded(child: rightColumn),
                ],
              );
            } else {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  leftColumn,
                  const SizedBox(height: 16),
                  rightColumn,
                ],
              );
            }
          },
        ),
      ),
    );
  }

  Widget _buildLeftColumn({
    required ThemeData theme,
    required double? cpuUtil,
    required double? core1Util,
    required double? core2Util,
    required double? core3Util,
    required double? core4Util,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Icon(Icons.memory, color: theme.colorScheme.primary, size: 20),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'RPi Monitor',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // CPU Section
        _buildSectionHeader('CPU', Icons.speed, Colors.blue, theme),
        const SizedBox(height: 8),

        if (cpuUtil != null)
          _buildMetricRow(
            'Overall',
            '${(cpuUtil * 100).toStringAsFixed(1)}%',
            cpuUtil,
            Colors.blue,
            theme,
          ),

        const SizedBox(height: 4),

        // CPU Cores
        Row(
          children: [
            if (core1Util != null)
              Expanded(
                child: _buildCoreCard('Core 1', core1Util, Colors.blue.shade300),
              ),
            if (core2Util != null) ...[
              const SizedBox(width: 4),
              Expanded(
                child: _buildCoreCard('Core 2', core2Util, Colors.blue.shade400),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            if (core3Util != null)
              Expanded(
                child: _buildCoreCard('Core 3', core3Util, Colors.blue.shade500),
              ),
            if (core4Util != null) ...[
              const SizedBox(width: 4),
              Expanded(
                child: _buildCoreCard('Core 4', core4Util, Colors.blue.shade600),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildRightColumn({
    required ThemeData theme,
    required double? cpuTempK,
    required String? cpuTempFormatted,
    required double? gpuTempK,
    required String? gpuTempFormatted,
    required double? memoryUtil,
    required double? storageUtil,
    required double? uptimeSeconds,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Temperature Section
        if (cpuTempK != null || gpuTempK != null) ...[
          _buildSectionHeader('Temperature', Icons.thermostat, Colors.orange, theme),
          const SizedBox(height: 8),

          Row(
            children: [
              if (cpuTempK != null && cpuTempFormatted != null)
                Expanded(
                  child: _buildTempCard(
                    'CPU',
                    cpuTempFormatted,
                    Icons.memory,
                    _getTempColor(cpuTempK),
                  ),
                ),
              if (gpuTempK != null && gpuTempFormatted != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTempCard(
                    'GPU',
                    gpuTempFormatted,
                    Icons.videocam,
                    _getTempColor(gpuTempK),
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 16),
        ],

        // Memory & Storage Section
        if (memoryUtil != null || storageUtil != null) ...[
          _buildSectionHeader('Resources', Icons.storage, Colors.purple, theme),
          const SizedBox(height: 8),

          if (memoryUtil != null)
            _buildMetricRow(
              'Memory',
              '${(memoryUtil * 100).toStringAsFixed(1)}%',
              memoryUtil,
              Colors.purple,
              theme,
            ),

          if (storageUtil != null) ...[
            const SizedBox(height: 4),
            _buildMetricRow(
              'Storage',
              '${(storageUtil * 100).toStringAsFixed(1)}%',
              storageUtil,
              Colors.purple,
              theme,
            ),
          ],

          const SizedBox(height: 16),
        ],

        // Uptime Section
        if (uptimeSeconds != null) ...[
          _buildSectionHeader('System', Icons.access_time, Colors.green, theme),
          const SizedBox(height: 8),
          _buildUptimeCard(uptimeSeconds, theme),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color, ThemeData theme) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricRow(
    String label,
    String value,
    double utilization,
    Color color,
    ThemeData theme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: _getUtilizationColor(utilization),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: utilization,
            backgroundColor: color.withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation(_getUtilizationColor(utilization)),
            minHeight: 6,
          ),
        ),
      ],
    );
  }

  Widget _buildCoreCard(String label, double utilization, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${(utilization * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: _getUtilizationColor(utilization),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTempCard(String label, String tempFormatted, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  tempFormatted,
                  style: TextStyle(
                    fontSize: 16,
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

  Widget _buildUptimeCard(double uptimeSeconds, ThemeData theme) {
    final duration = Duration(seconds: uptimeSeconds.toInt());
    final days = duration.inDays;
    final hours = duration.inHours % 24;
    final minutes = duration.inMinutes % 60;

    String uptimeText;
    if (days > 0) {
      uptimeText = '${days}d ${hours}h ${minutes}m';
    } else if (hours > 0) {
      uptimeText = '${hours}h ${minutes}m';
    } else {
      uptimeText = '${minutes}m';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.access_time, color: Colors.green, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Uptime',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.green,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  uptimeText,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getUtilizationColor(double utilization) {
    if (utilization < 0.5) return Colors.green;
    if (utilization < 0.75) return Colors.orange;
    return Colors.red;
  }

  Color _getTempColor(double tempK) {
    // Temperature thresholds in Kelvin
    // 60°C = 333.15 K, 75°C = 348.15 K
    if (tempK < 333.15) return Colors.green;  // < 60°C
    if (tempK < 348.15) return Colors.orange; // < 75°C
    return Colors.red;                         // >= 75°C
  }
}

/// Builder for RPi monitor tool
class RpiMonitorToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'rpi_monitor',
      name: 'RPi Monitor',
      description: 'Monitor Raspberry Pi system metrics - CPU, temperature, memory, storage, and uptime (requires signalk-rpi-monitor plugin)',
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
      dataSources: [], // No data sources needed - uses fixed paths
      style: StyleConfig(),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return RpiMonitorTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
