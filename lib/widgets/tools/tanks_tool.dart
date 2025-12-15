import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/string_extensions.dart';
import '../../utils/conversion_utils.dart';

/// Tank display widget showing up to 5 tank levels
class TanksTool extends StatelessWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const TanksTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  /// Colors for tank types by ID
  static const Map<String, Color> tankTypeColors = {
    'diesel': Color(0xFFE91E63), // Pink
    'petrol': Color(0xFFFF5722), // Deep Orange
    'gasoline': Color(0xFFFF5722), // Deep Orange (same as petrol)
    'propane': Color(0xFF2E7D32), // Dark Green
    'freshWater': Color(0xFF2196F3), // Blue
    'blackWater': Color(0xFF5D4037), // Brown
    'wasteWater': Color(0xFF795548), // Brown lighter
    'liveWell': Color(0xFF4CAF50), // Green
    'lubrication': Color(0xFF9C27B0), // Purple
    'ballast': Color(0xFF607D8B), // Blue Grey
  };

  /// Get color for a tank based on configured type
  Color _getTankColor(int index) {
    // Get tank type from config
    final tankTypes = config.style.customProperties?['tankTypes'] as List?;
    if (tankTypes != null && index < tankTypes.length) {
      final typeId = tankTypes[index]?.toString();
      if (typeId != null && tankTypeColors.containsKey(typeId)) {
        return tankTypeColors[typeId]!;
      }
    }

    // Fallback: try to derive from path
    if (index < config.dataSources.length) {
      final path = config.dataSources[index].path.toLowerCase();
      for (final entry in tankTypeColors.entries) {
        if (path.contains(entry.key.toLowerCase())) {
          return entry.value;
        }
      }
    }

    // Default color
    return Colors.blue;
  }

  /// Get label for a tank
  String _getTankLabel(DataSource dataSource) {
    if (dataSource.label != null && dataSource.label!.isNotEmpty) {
      return dataSource.label!;
    }
    // Derive from path
    return dataSource.path.toReadableLabel();
  }

  /// Get display name for a tank type ID
  String? _getTankTypeName(String? typeId) {
    if (typeId == null) return null;
    const typeNames = {
      'diesel': 'Diesel',
      'petrol': 'Petrol',
      'gasoline': 'Gas',
      'propane': 'Propane',
      'freshWater': 'Fresh',
      'blackWater': 'Black',
      'wasteWater': 'Waste',
      'liveWell': 'Live',
      'lubrication': 'Lube',
      'ballast': 'Ballast',
    };
    return typeNames[typeId];
  }

  @override
  Widget build(BuildContext context) {
    if (config.dataSources.isEmpty) {
      return const Center(
        child: Text('No tanks configured'),
      );
    }

    final style = config.style;
    final showCapacity = style.customProperties?['showCapacity'] as bool? ?? false;
    final toolLabel = style.customProperties?['label'] as String?;
    final showToolLabel = style.showLabel == true && toolLabel != null && toolLabel.isNotEmpty;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          // Tool label at top
          if (showToolLabel) ...[
            Text(
              toolLabel,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
          ],
          // Tank row
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: config.dataSources.asMap().entries.map((entry) {
                final index = entry.key;
                final dataSource = entry.value;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: _buildTank(
                      context,
                      dataSource,
                      index,
                      showCapacity,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTank(
    BuildContext context,
    DataSource dataSource,
    int index,
    bool showCapacity,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _getTankColor(index);
    final label = _getTankLabel(dataSource);

    // Get tank root path (strip .currentLevel, .capacity, etc. if present)
    String tankRoot = dataSource.path;
    for (final suffix in ['.currentLevel', '.capacity', '.currentVolume', '.type', '.name']) {
      if (tankRoot.endsWith(suffix)) {
        tankRoot = tankRoot.substring(0, tankRoot.length - suffix.length);
        break;
      }
    }

    // Get tank level (0-1 ratio)
    final levelPath = '$tankRoot.currentLevel';
    final rawLevel = ConversionUtils.getRawValue(signalKService, levelPath);

    // Check data freshness
    final isDataFresh = signalKService.isDataFresh(
      levelPath,
      source: dataSource.source,
      ttlSeconds: config.style.ttlSeconds,
    );

    final level = isDataFresh ? (rawLevel ?? 0.0) : 0.0;
    final levelPercent = (level * 100).clamp(0.0, 100.0);

    // Get capacity (uses conversion system for units)
    final capacityPath = '$tankRoot.capacity';
    final capacityValue = ConversionUtils.getConvertedValue(signalKService, capacityPath);
    final unit = signalKService.getUnitSymbol(capacityPath) ?? '';

    String? capacityText;
    String? remainingText;
    if (capacityValue != null && capacityValue > 0) {
      final remaining = capacityValue * level;
      capacityText = '${capacityValue.toStringAsFixed(0)}${unit.isNotEmpty ? ' $unit' : ''}';
      remainingText = '${remaining.toStringAsFixed(0)}${unit.isNotEmpty ? ' $unit' : ''}';
    }

    // Get tank type name for display inside tank
    final tankTypes = config.style.customProperties?['tankTypes'] as List?;
    String? tankTypeName;
    if (tankTypes != null && index < tankTypes.length) {
      final typeId = tankTypes[index]?.toString();
      tankTypeName = _getTankTypeName(typeId);
    }

    return Column(
      children: [
        // Label at top
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black87,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),

        // Total capacity
        if (showCapacity && capacityText != null)
          Text(
            capacityText,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),

        if (showCapacity && capacityText != null)
          const SizedBox(height: 2),

        // Tank visualization
        Expanded(
          child: _TankVisual(
            levelPercent: levelPercent,
            color: color,
            isDataFresh: isDataFresh,
            isDark: isDark,
            remainingText: showCapacity ? remainingText : null,
            tankTypeName: tankTypeName,
          ),
        ),
      ],
    );
  }
}

/// Custom tank visual with rounded shape and level indicator
class _TankVisual extends StatelessWidget {
  final double levelPercent;
  final Color color;
  final bool isDataFresh;
  final bool isDark;
  final String? remainingText;
  final String? tankTypeName;

  const _TankVisual({
    required this.levelPercent,
    required this.color,
    required this.isDataFresh,
    required this.isDark,
    this.remainingText,
    this.tankTypeName,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.clamp(30.0, 60.0);
        final height = constraints.maxHeight;
        final levelHeight = isDataFresh ? (height * levelPercent / 100) : 0.0;

        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: CustomPaint(
              painter: _TankPainter(
                levelPercent: isDataFresh ? levelPercent : 0,
                color: color,
                isDark: isDark,
              ),
              child: Stack(
                children: [
                  // Percentage and remaining at the level line
                  if (isDataFresh && levelPercent > 5)
                    Positioned(
                      bottom: levelHeight - 20,
                      left: 0,
                      right: 0,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${levelPercent.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _getContrastColor(color),
                              shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  blurRadius: 2,
                                ),
                              ],
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (remainingText != null)
                            Text(
                              remainingText!,
                              style: TextStyle(
                                fontSize: 9,
                                color: _getContrastColor(color).withValues(alpha: 0.8),
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    blurRadius: 2,
                                  ),
                                ],
                              ),
                              textAlign: TextAlign.center,
                            ),
                        ],
                      ),
                    ),
                  // Show percentage at bottom if level too low
                  if (isDataFresh && levelPercent <= 5)
                    Positioned(
                      bottom: tankTypeName != null ? 20 : 4,
                      left: 0,
                      right: 0,
                      child: Text(
                        '${levelPercent.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  // Tank type name at bottom inside the liquid
                  if (tankTypeName != null && isDataFresh && levelPercent > 10)
                    Positioned(
                      bottom: 4,
                      left: 0,
                      right: 0,
                      child: Text(
                        tankTypeName!,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _getContrastColor(color),
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  // Stale data indicator
                  if (!isDataFresh)
                    Center(
                      child: Text(
                        '--',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white38 : Colors.black26,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Color _getContrastColor(Color color) {
    final luminance = color.computeLuminance();
    return luminance > 0.5 ? Colors.black87 : Colors.white;
  }
}

/// Custom painter for tank shape
class _TankPainter extends CustomPainter {
  final double levelPercent;
  final Color color;
  final bool isDark;

  _TankPainter({
    required this.levelPercent,
    required this.color,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cornerRadius = w * 0.3;
    final topRadius = w * 0.4;

    // Tank outline path (rounded rectangle with dome top)
    final tankPath = Path();

    // Start from bottom left
    tankPath.moveTo(0, h - cornerRadius);

    // Bottom left corner
    tankPath.quadraticBezierTo(0, h, cornerRadius, h);

    // Bottom edge
    tankPath.lineTo(w - cornerRadius, h);

    // Bottom right corner
    tankPath.quadraticBezierTo(w, h, w, h - cornerRadius);

    // Right edge
    tankPath.lineTo(w, topRadius);

    // Top dome (right side)
    tankPath.quadraticBezierTo(w, 0, w / 2, 0);

    // Top dome (left side)
    tankPath.quadraticBezierTo(0, 0, 0, topRadius);

    // Left edge back to start
    tankPath.close();

    // Draw tank background
    final bgPaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.black.withValues(alpha: 0.04)
      ..style = PaintingStyle.fill;
    canvas.drawPath(tankPath, bgPaint);

    // Draw fill level
    if (levelPercent > 0) {
      final fillHeight = h * levelPercent / 100;

      // Clip to tank shape
      canvas.save();
      canvas.clipPath(tankPath);

      // Fill rectangle from bottom
      final fillRect = Rect.fromLTWH(0, h - fillHeight, w, fillHeight);
      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            color.withValues(alpha: 0.7),
            color,
            color.withValues(alpha: 0.7),
          ],
        ).createShader(fillRect)
        ..style = PaintingStyle.fill;

      canvas.drawRect(fillRect, fillPaint);

      // Draw level line
      final linePaint = Paint()
        ..color = color.withValues(alpha: 0.9)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(0, h - fillHeight),
        Offset(w, h - fillHeight),
        linePaint,
      );

      canvas.restore();
    }

    // Draw tank outline
    final outlinePaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.3)
          : Colors.black.withValues(alpha: 0.2)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawPath(tankPath, outlinePaint);

    // Draw level markers (E, 1/4, 1/2, 3/4, F)
    final markerPaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.2)
          : Colors.black.withValues(alpha: 0.1)
      ..strokeWidth = 1;

    for (final fraction in [0.25, 0.5, 0.75]) {
      final y = h - (h * fraction);
      canvas.drawLine(Offset(0, y), Offset(w * 0.15, y), markerPaint);
      canvas.drawLine(Offset(w * 0.85, y), Offset(w, y), markerPaint);
    }
  }

  @override
  bool shouldRepaint(_TankPainter oldDelegate) {
    return oldDelegate.levelPercent != levelPercent ||
        oldDelegate.color != color ||
        oldDelegate.isDark != isDark;
  }
}

/// Builder for tanks tool
class TanksToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'tanks',
      name: 'Tanks',
      description: 'Display up to 5 tank levels',
      category: ToolCategory.instruments,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: false,
        allowsMultiplePaths: true,
        minPaths: 1,
        maxPaths: 5,
        styleOptions: const [
          'showLabel',
          'label',
          'showCapacity',
          'tankTypes',
        ],
      ),
    );
  }

  @override
  ToolConfig? getDefaultConfig(String vesselId) {
    return ToolConfig(
      vesselId: vesselId,
      dataSources: [
        DataSource(path: 'tanks.fuel.0', label: 'Diesel'),
        DataSource(path: 'tanks.freshWater.0', label: 'Fresh Water'),
      ],
      style: StyleConfig(
        customProperties: {
          'showCapacity': false,
          'tankTypes': ['diesel', 'freshWater'],
        },
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return TanksTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
