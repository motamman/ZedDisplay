import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/alert_event.dart';
import '../models/cpa_alert_state.dart';
import '../services/alert_coordinator.dart';
import '../services/cpa_alert_service.dart';
import '../services/ais_favorites_service.dart';

/// Persistent alert panel that renders all active alerts as stacked rows.
/// Lives in the MaterialApp.builder Stack — visible on every screen.
/// Zero height when no alerts are active.
class AlertPanel extends StatelessWidget {
  const AlertPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AlertCoordinator>(
      builder: (context, coordinator, _) {
        final alerts = coordinator.activeAlerts;
        if (alerts.isEmpty) return const SizedBox.shrink();

        // Sort: highest severity first
        final sorted = List<AlertEvent>.from(alerts)
          ..sort((a, b) => b.severity.index.compareTo(a.severity.index));

        return Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Material(
            elevation: 8,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: sorted.length,
                itemBuilder: (context, index) {
                  return _AlertRow(
                    event: sorted[index],
                    coordinator: coordinator,
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AlertRow extends StatelessWidget {
  final AlertEvent event;
  final AlertCoordinator coordinator;

  const _AlertRow({required this.event, required this.coordinator});

  @override
  Widget build(BuildContext context) {
    final isAlarm = event.severity >= AlertSeverity.alarm;
    final colors = _severityColors(event.severity);
    final isCpa = event.subsystem == AlertSubsystem.cpa;

    return Container(
      color: colors.$1,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(colors.$2, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${event.title} ${event.body}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // VIEW — CPA: highlight vessel on chart
          if (isCpa && event.callbackData is CpaVesselAlert)
            _button('VIEW', () {
              try {
                final cpaService = Provider.of<CpaAlertService>(context, listen: false);
                cpaService.requestHighlight(
                  (event.callbackData as CpaVesselAlert).vesselId,
                );
              } catch (_) {}
            }),
          // VIEW — AIS Favorites: highlight vessel on chart
          if (event.subsystem == AlertSubsystem.aisFavorites && event.callbackData is String)
            _button('VIEW', () {
              try {
                final favService = Provider.of<AISFavoritesService>(context, listen: false);
                favService.requestHighlight(event.callbackData as String);
              } catch (_) {}
            }),
          // ACK — alarm level: stop audio, row stays
          if (isAlarm)
            _button('ACK', () {
              coordinator.acknowledgeAlarm(event.subsystem, alarmId: event.alarmId);
            }),
          // CANCEL / DISMISS — removes alert entirely
          _button(isAlarm ? 'CANCEL' : 'DISMISS', () {
            coordinator.resolveAlert(event.subsystem, alarmId: event.alarmId);
          }),
        ],
      ),
    );
  }

  Widget _button(String label, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: label == 'VIEW' ? Colors.white70 : Colors.white,
            fontSize: 12,
            fontWeight: label == 'ACK' || label == 'CANCEL' || label == 'DISMISS'
                ? FontWeight.bold
                : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  (Color, IconData) _severityColors(AlertSeverity severity) {
    switch (severity) {
      case AlertSeverity.emergency:
        return (Colors.red.shade900, Icons.emergency);
      case AlertSeverity.alarm:
        return (Colors.red.shade700, Icons.alarm);
      case AlertSeverity.warn:
        return (Colors.orange.shade700, Icons.warning);
      case AlertSeverity.alert:
        return (Colors.amber.shade700, Icons.info);
      case AlertSeverity.normal:
        return (Colors.blue.shade700, Icons.notifications);
      case AlertSeverity.nominal:
        return (Colors.green.shade700, Icons.check_circle);
    }
  }
}
