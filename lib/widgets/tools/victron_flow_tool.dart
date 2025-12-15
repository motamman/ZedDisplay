import 'package:flutter/material.dart';
import '../../models/tool_config.dart';
import '../../models/tool_definition.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';

/// Victron Power Flow Tool - Visual power flow diagram with animated flow lines
class VictronFlowTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const VictronFlowTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<VictronFlowTool> createState() => _VictronFlowToolState();
}

class _VictronFlowToolState extends State<VictronFlowTool> with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
    widget.signalKService.addListener(_onDataUpdate);
  }

  @override
  void dispose() {
    _animController.dispose();
    widget.signalKService.removeListener(_onDataUpdate);
    super.dispose();
  }

  void _onDataUpdate() {
    if (mounted) setState(() {});
  }

  String _getPath(int index) {
    if (index < widget.config.dataSources.length) {
      return widget.config.dataSources[index].path;
    }
    return '';
  }

  double? _getValue(int index) {
    final path = _getPath(index);
    if (path.isEmpty) return null;
    final data = widget.signalKService.getValue(path);
    if (data?.value is num) {
      return (data!.value as num).toDouble();
    }
    return null;
  }

  String? _getStringValue(int index) {
    final path = _getPath(index);
    if (path.isEmpty) return null;
    final data = widget.signalKService.getValue(path);
    if (data?.value != null) {
      return data!.value.toString();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Get current values for animation speed
    final shoreCurrent = (_getValue(0) ?? 0).abs();
    final solarPower = (_getValue(6) ?? 0).abs();
    final alternatorCurrent = (_getValue(8) ?? 0).abs();
    final batteryCurrent = _getValue(15) ?? 0;
    final acLoadsPower = (_getValue(22) ?? 0).abs();
    final dcLoadsPower = (_getValue(25) ?? 0).abs();

    return LayoutBuilder(
      builder: (context, constraints) {
        return AnimatedBuilder(
          animation: _animController,
          builder: (context, child) {
            return CustomPaint(
              painter: _FlowLinesPainter(
                animValue: _animController.value,
                shoreActive: shoreCurrent > 0.1,
                shoreCurrent: shoreCurrent,
                solarActive: solarPower > 1,
                solarPower: solarPower,
                alternatorActive: alternatorCurrent > 0.1,
                alternatorCurrent: alternatorCurrent,
                batteryCharging: batteryCurrent > 0,
                batteryDischarging: batteryCurrent < 0,
                batteryCurrent: batteryCurrent.abs(),
                acLoadsActive: acLoadsPower > 1,
                acLoadsPower: acLoadsPower,
                dcLoadsActive: dcLoadsPower > 1,
                dcLoadsPower: dcLoadsPower,
              ),
              child: child,
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _buildFlowDiagram(constraints),
          ),
        );
      },
    );
  }

  Widget _buildFlowDiagram(BoxConstraints constraints) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Left column - Power sources
        Expanded(
          flex: 3,
          child: Column(
            children: [
              Expanded(child: _buildShoreBox()),
              const SizedBox(height: 16),
              Expanded(child: _buildSolarBox()),
              const SizedBox(height: 16),
              Expanded(child: _buildAlternatorBox()),
            ],
          ),
        ),
        const SizedBox(width: 40),
        // Center column - Inverter & Battery
        Expanded(
          flex: 4,
          child: Column(
            children: [
              Expanded(flex: 2, child: _buildInverterBox()),
              const SizedBox(height: 16),
              Expanded(flex: 3, child: _buildBatteryBox()),
            ],
          ),
        ),
        const SizedBox(width: 40),
        // Right column - Loads
        Expanded(
          flex: 3,
          child: Column(
            children: [
              Expanded(child: _buildAcLoadsBox()),
              const SizedBox(height: 16),
              Expanded(child: _buildDcLoadsBox()),
              const Spacer(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildComponentBox({
    required String title,
    required IconData icon,
    required Widget content,
    Color? borderColor,
    Color? backgroundColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = backgroundColor ?? (isDark ? const Color(0xFF1a3a5c) : Colors.blue.shade50);
    final border = borderColor ?? Colors.blue.shade300;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: 2),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.white70),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(child: content),
        ],
      ),
    );
  }

  Widget _buildShoreBox() {
    final current = _getValue(0);
    final voltage = _getValue(1);
    final frequency = _getValue(2);
    final power = _getValue(3);

    return _buildComponentBox(
      title: 'Shore',
      icon: Icons.power,
      content: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              current != null ? '${current.toStringAsFixed(1)}A' : '--A',
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
            ),
            Text(
              '${voltage?.toStringAsFixed(0) ?? '--'}V  ${frequency?.toStringAsFixed(0) ?? '--'}Hz  ${power?.toStringAsFixed(0) ?? '--'}W',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSolarBox() {
    final current = _getValue(4);
    final voltage = _getValue(5);
    final power = _getValue(6);
    final state = _getStringValue(7);

    return _buildComponentBox(
      title: 'Solar yield',
      icon: Icons.wb_sunny_outlined,
      content: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              current != null ? '${current.toStringAsFixed(1)}A' : '--A',
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
            ),
            if (state != null)
              Text(_formatState(state), style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Text(
              '${voltage?.toStringAsFixed(2) ?? '--'}V  ${power?.toStringAsFixed(2) ?? '--'}W',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlternatorBox() {
    final current = _getValue(8);
    final voltage = _getValue(9);
    final power = _getValue(10);
    final state = _getStringValue(11);

    return _buildComponentBox(
      title: 'Alternator',
      icon: Icons.settings_input_svideo,
      content: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              current != null ? '${current.toStringAsFixed(1)}A' : '--A',
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
            ),
            Text(state ?? 'Off', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Text(
              '${voltage?.toStringAsFixed(2) ?? '--'}V  ${power?.toStringAsFixed(2) ?? '--'}W',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInverterBox() {
    final state = _getStringValue(12);

    return _buildComponentBox(
      title: 'Inverter / Charger',
      icon: Icons.electrical_services,
      borderColor: Colors.blue.shade200,
      content: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            _formatState(state ?? 'Off'),
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildBatteryBox() {
    final soc = _getValue(13);
    final voltage = _getValue(14);
    final current = _getValue(15);
    final power = _getValue(16);
    final timeRemaining = _getValue(17);
    final temp = _getValue(18);

    final isCharging = (current ?? 0) > 0;
    final isDischarging = (current ?? 0) < 0;

    String stateText = 'Idle';
    if (isCharging) stateText = 'Charging';
    if (isDischarging) stateText = 'Discharging';

    String timeText = '';
    if (timeRemaining != null && timeRemaining > 0) {
      final hours = timeRemaining ~/ 3600;
      final minutes = (timeRemaining % 3600) ~/ 60;
      if (hours > 24) {
        timeText = '${hours ~/ 24}d ${hours % 24}h';
      } else {
        timeText = '${hours}h ${minutes}m';
      }
    }

    return _buildComponentBox(
      title: 'Battery',
      icon: Icons.battery_std,
      backgroundColor: Colors.blue.shade400.withValues(alpha: 0.9),
      borderColor: Colors.blue.shade200,
      content: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  soc != null ? '${(soc * 100).toStringAsFixed(0)}%' : '--%',
                  style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
                ),
                if (temp != null) ...[
                  const SizedBox(width: 16),
                  Text('${(temp - 273.15).toStringAsFixed(0)}°C', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                ],
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  stateText,
                  style: TextStyle(
                    color: isCharging ? Colors.greenAccent : (isDischarging ? Colors.orangeAccent : Colors.white70),
                    fontSize: 14,
                  ),
                ),
                if (timeText.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(timeText, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${voltage?.toStringAsFixed(2) ?? '--'}V  ${current?.toStringAsFixed(1) ?? '--'}A  ${power?.toStringAsFixed(0) ?? '--'}W',
              style: TextStyle(
                color: isCharging ? Colors.greenAccent : (isDischarging ? Colors.orangeAccent : Colors.white70),
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAcLoadsBox() {
    final current = _getValue(19);
    final voltage = _getValue(20);
    final frequency = _getValue(21);
    final power = _getValue(22);

    return _buildComponentBox(
      title: 'AC Loads',
      icon: Icons.outlet,
      content: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              current != null ? '${current.toStringAsFixed(1)}A' : '--A',
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
            ),
            Text(
              '${voltage?.toStringAsFixed(0) ?? '--'}V  ${frequency?.toStringAsFixed(0) ?? '--'}Hz  ${power?.toStringAsFixed(0) ?? '--'}W',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDcLoadsBox() {
    final current = _getValue(23);
    final voltage = _getValue(24);
    final power = _getValue(25);

    return _buildComponentBox(
      title: 'DC Loads',
      icon: Icons.power,
      content: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              current != null ? '${current.toStringAsFixed(1)}A' : '--A',
              style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
            ),
            Text(
              '${voltage?.toStringAsFixed(2) ?? '--'}V  ${power?.toStringAsFixed(2) ?? '--'}W',
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  String _formatState(String state) {
    if (state.isEmpty) return 'Off';
    return state
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isNotEmpty ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}' : '')
        .join(' ');
  }
}

/// Animated flow lines painter
class _FlowLinesPainter extends CustomPainter {
  final double animValue;
  final bool shoreActive;
  final double shoreCurrent;
  final bool solarActive;
  final double solarPower;
  final bool alternatorActive;
  final double alternatorCurrent;
  final bool batteryCharging;
  final bool batteryDischarging;
  final double batteryCurrent;
  final bool acLoadsActive;
  final double acLoadsPower;
  final bool dcLoadsActive;
  final double dcLoadsPower;

  _FlowLinesPainter({
    required this.animValue,
    required this.shoreActive,
    required this.shoreCurrent,
    required this.solarActive,
    required this.solarPower,
    required this.alternatorActive,
    required this.alternatorCurrent,
    required this.batteryCharging,
    required this.batteryDischarging,
    required this.batteryCurrent,
    required this.acLoadsActive,
    required this.acLoadsPower,
    required this.dcLoadsActive,
    required this.dcLoadsPower,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final inactivePaint = Paint()
      ..color = Colors.blue.withValues(alpha: 0.3)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    // Match layout: padding 12, gaps 40, flex 3:4:3
    const padding = 12.0;
    const gap = 40.0;
    final contentWidth = size.width - padding * 2;
    final colWidthUnit = (contentWidth - gap * 2) / 10;

    final leftColRight = padding + colWidthUnit * 3;
    final centerColLeft = leftColRight + gap;
    final centerColRight = centerColLeft + colWidthUnit * 4;
    final rightColLeft = centerColRight + gap;

    // Vertical positions for rows (3 equal rows in left column with 16px gaps)
    final contentHeight = size.height - padding * 2;
    final rowHeight = (contentHeight - 32) / 3; // 2 gaps of 16px

    final row1Center = padding + rowHeight / 2;
    final row2Center = padding + rowHeight + 16 + rowHeight / 2;
    final row3Center = padding + rowHeight * 2 + 32 + rowHeight / 2;

    // Center column: inverter (flex 2) and battery (flex 3) with 16px gap
    final inverterHeight = (contentHeight - 16) * 2 / 5;
    final batteryHeight = (contentHeight - 16) * 3 / 5;
    final inverterBottom = padding + inverterHeight;
    final batteryTop = inverterBottom + 16;
    final batteryCenter = batteryTop + batteryHeight / 2;

    // Right column: 2 equal boxes + spacer (each box is 1/3 of content height minus gap)
    final rightRowHeight = (contentHeight - 16) / 3; // Only 2 boxes with 1 gap, spacer takes 1/3
    final acLoadsCenter = padding + rightRowHeight / 2;
    final dcLoadsCenter = padding + rightRowHeight + 16 + rightRowHeight / 2;

    // Inverter center for horizontal line
    final inverterCenter = padding + inverterHeight / 2;

    // Shore to Inverter (left to right)
    _drawAnimatedLine(
      canvas,
      Offset(leftColRight, row1Center),
      Offset(centerColLeft, inverterCenter),
      shoreActive,
      shoreCurrent,
      inactivePaint,
      true,
    );

    // Solar to Battery (via corner)
    final midX = leftColRight + gap / 2;
    _drawAnimatedPath(
      canvas,
      [
        Offset(leftColRight, row2Center),
        Offset(midX, row2Center),
        Offset(midX, batteryCenter - 10),
        Offset(centerColLeft, batteryCenter - 10),
      ],
      solarActive,
      solarPower / 100,
      inactivePaint,
      true,
    );

    // Alternator to Battery (via corner)
    _drawAnimatedPath(
      canvas,
      [
        Offset(leftColRight, row3Center),
        Offset(midX, row3Center),
        Offset(midX, batteryCenter + 10),
        Offset(centerColLeft, batteryCenter + 10),
      ],
      alternatorActive,
      alternatorCurrent,
      inactivePaint,
      true,
    );

    // Inverter to/from Battery (vertical)
    _drawAnimatedLine(
      canvas,
      Offset((centerColLeft + centerColRight) / 2, inverterBottom),
      Offset((centerColLeft + centerColRight) / 2, batteryTop),
      batteryCharging || batteryDischarging,
      batteryCurrent,
      inactivePaint,
      batteryCharging,
    );

    // Inverter to AC Loads (right)
    _drawAnimatedLine(
      canvas,
      Offset(centerColRight, inverterCenter),
      Offset(rightColLeft, acLoadsCenter),
      acLoadsActive,
      acLoadsPower / 100,
      inactivePaint,
      true,
    );

    // Battery to DC Loads (right)
    _drawAnimatedLine(
      canvas,
      Offset(centerColRight, batteryCenter),
      Offset(rightColLeft, dcLoadsCenter),
      dcLoadsActive,
      dcLoadsPower / 100,
      inactivePaint,
      true,
    );
  }

  void _drawAnimatedLine(Canvas canvas, Offset start, Offset end, bool active, double current, Paint inactivePaint, bool forward) {
    // Draw dots at endpoints
    final dotPaint = Paint()
      ..color = active ? Colors.blue : Colors.blue.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(start, 5, dotPaint);
    canvas.drawCircle(end, 5, dotPaint);

    if (!active) {
      canvas.drawLine(start, end, inactivePaint);
      return;
    }

    // Calculate animation speed based on current (more current = faster)
    final speed = (current.clamp(0.1, 50) / 10).clamp(0.5, 3.0);
    final dashOffset = (forward ? animValue : 1 - animValue) * speed * 30;

    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    final path = Path()..moveTo(start.dx, start.dy)..lineTo(end.dx, end.dy);
    final dashPath = _createDashedPath(path, dashOffset);
    canvas.drawPath(dashPath, paint);
  }

  void _drawAnimatedPath(Canvas canvas, List<Offset> points, bool active, double current, Paint inactivePaint, bool forward) {
    if (points.length < 2) return;

    // Draw dots at endpoints
    final dotPaint = Paint()
      ..color = active ? Colors.blue : Colors.blue.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(points.first, 5, dotPaint);
    canvas.drawCircle(points.last, 5, dotPaint);

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    if (!active) {
      canvas.drawPath(path, inactivePaint);
      return;
    }

    final speed = (current.clamp(0.1, 50) / 10).clamp(0.5, 3.0);
    final dashOffset = (forward ? animValue : 1 - animValue) * speed * 30;

    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    final dashPath = _createDashedPath(path, dashOffset);
    canvas.drawPath(dashPath, paint);
  }

  Path _createDashedPath(Path source, double offset) {
    final dashPath = Path();
    final metrics = source.computeMetrics();

    const dashLength = 10.0;
    const gapLength = 8.0;
    final totalLength = dashLength + gapLength;

    for (final metric in metrics) {
      double distance = offset % totalLength;
      while (distance < metric.length) {
        final start = distance;
        final end = (distance + dashLength).clamp(0, metric.length);
        final extracted = metric.extractPath(start, end.toDouble());
        dashPath.addPath(extracted, Offset.zero);
        distance += totalLength;
      }
    }
    return dashPath;
  }

  @override
  bool shouldRepaint(covariant _FlowLinesPainter oldDelegate) => true;
}

/// Builder for Victron Flow Tool
class VictronFlowToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'victron_flow',
      name: 'Victron Power Flow',
      description: 'Visual power flow diagram for Victron systems',
      category: ToolCategory.electrical,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: false,
        allowsMultiplePaths: true,
        minPaths: 26,
        maxPaths: 26,
        styleOptions: const [],
      ),
    );
  }

  @override
  ToolConfig? getDefaultConfig(String vesselId) {
    return ToolConfig(
      vesselId: vesselId,
      dataSources: [
        DataSource(path: 'electrical.shore.current', label: 'Shore Current'),
        DataSource(path: 'electrical.shore.voltage', label: 'Shore Voltage'),
        DataSource(path: 'electrical.shore.frequency', label: 'Shore Frequency'),
        DataSource(path: 'electrical.shore.power', label: 'Shore Power'),
        DataSource(path: 'electrical.solar.current', label: 'Solar Current'),
        DataSource(path: 'electrical.solar.voltage', label: 'Solar Voltage'),
        DataSource(path: 'electrical.solar.power', label: 'Solar Power'),
        DataSource(path: 'electrical.solar.chargingMode', label: 'Solar State'),
        DataSource(path: 'electrical.alternator.current', label: 'Alternator Current'),
        DataSource(path: 'electrical.alternator.voltage', label: 'Alternator Voltage'),
        DataSource(path: 'electrical.alternator.power', label: 'Alternator Power'),
        DataSource(path: 'electrical.alternator.state', label: 'Alternator State'),
        DataSource(path: 'electrical.inverter.state', label: 'Inverter State'),
        DataSource(path: 'electrical.batteries.house.capacity.stateOfCharge', label: 'Battery SOC'),
        DataSource(path: 'electrical.batteries.house.voltage', label: 'Battery Voltage'),
        DataSource(path: 'electrical.batteries.house.current', label: 'Battery Current'),
        DataSource(path: 'electrical.batteries.house.power', label: 'Battery Power'),
        DataSource(path: 'electrical.batteries.house.capacity.timeRemaining', label: 'Battery Time Remaining'),
        DataSource(path: 'electrical.batteries.house.temperature', label: 'Battery Temperature'),
        DataSource(path: 'electrical.ac.load.current', label: 'AC Loads Current'),
        DataSource(path: 'electrical.ac.load.voltage', label: 'AC Loads Voltage'),
        DataSource(path: 'electrical.ac.load.frequency', label: 'AC Loads Frequency'),
        DataSource(path: 'electrical.ac.load.power', label: 'AC Loads Power'),
        DataSource(path: 'electrical.dc.load.current', label: 'DC Loads Current'),
        DataSource(path: 'electrical.dc.load.voltage', label: 'DC Loads Voltage'),
        DataSource(path: 'electrical.dc.load.power', label: 'DC Loads Power'),
      ],
      style: StyleConfig(),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return VictronFlowTool(config: config, signalKService: signalKService);
  }
}
