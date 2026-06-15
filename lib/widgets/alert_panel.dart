import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/alert_event.dart';
import '../models/cpa_alert_state.dart';
import '../models/notification_payload.dart';
import '../services/alert_coordinator.dart';
import '../services/cpa_alert_service.dart';
import '../services/ais_favorites_service.dart';
import '../services/dashboard_service.dart';
import '../config/ui_constants.dart';

/// Persistent alert panel that renders all active alerts as stacked rows.
/// Lives in the MaterialApp.builder Stack — visible on every screen.
/// Zero height when no alerts are active.
class AlertPanel extends StatelessWidget {
  const AlertPanel({super.key});

  /// Height of the dashboard's screen-nav row (dots + arrows). Single source of
  /// truth shared with dashboard_manager_screen.dart's selector row.
  static const double _screenNavHeight = UIConstants.screenSelectorHeight;

  @override
  Widget build(BuildContext context) {
    return Consumer<AlertCoordinator>(
      builder: (context, coordinator, _) {
        final alerts = coordinator.activeAlerts;
        if (alerts.isEmpty) return const SizedBox.shrink();

        // Sort: highest severity first
        final sorted = List<AlertEvent>.from(alerts)
          ..sort((a, b) => b.severity.index.compareTo(a.severity.index));

        // Sit above the screen-nav row. The nav lives inside the bottom
        // safe-area, so it occupies [viewPadding.bottom .. +_screenNavHeight]
        // from the screen bottom — the panel must clear BOTH the safe-area
        // inset and the nav height, or it overlaps the nav.
        final bottomInset =
            MediaQuery.of(context).viewPadding.bottom + _screenNavHeight;

        return Positioned(
          left: 0,
          right: 0,
          bottom: bottomInset,
          child: Material(
            elevation: 8,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Bulk actions header — only when more than one alert.
                  if (sorted.length > 1)
                    _BulkActionsBar(
                      count: sorted.length,
                      coordinator: coordinator,
                    ),
                  Flexible(
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
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Header above a stack of alerts (shown only when there is more than one):
/// the count plus ACK ALL / DISMISS ALL.
class _BulkActionsBar extends StatelessWidget {
  final int count;
  final AlertCoordinator coordinator;

  const _BulkActionsBar({required this.count, required this.coordinator});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey.shade900,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Text(
            '$count alerts',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          _barButton('ACK ALL', coordinator.acknowledgeAll),
          const SizedBox(width: 4),
          _barButton('DISMISS ALL', coordinator.dismissAll),
        ],
      ),
    );
  }

  Widget _barButton(String label, VoidCallback onPressed) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  final AlertEvent event;
  final AlertCoordinator coordinator;

  const _AlertRow({required this.event, required this.coordinator});

  @override
  Widget build(BuildContext context) {
    final colors = _severityColors(event.severity);

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
          // VIEW — unified for every alert: navigate to the alert's home
          // widget (see _buildViewButton). One rule, no per-subsystem cases.
          _buildViewButton(context),
          // ACK — universal: silence audio (if any) + clear the system
          // notification, but leave the row up. Severity is shown by colour.
          _button('ACK', () {
            coordinator.acknowledgeAlarm(event.subsystem, alarmId: event.alarmId);
          }),
          // DISMISS — universal: removes the alert entirely. Same label at every
          // severity (colour is the severity indicator).
          _button('DISMISS', () {
            coordinator.resolveAlert(event.subsystem, alarmId: event.alarmId);
          }),
        ],
      ),
    );
  }

  /// Unified VIEW button. Resolves the alert's home screen the same way for
  /// every alert, then navigates there on tap:
  ///   1. `alarmSource` — the widget type the alert declares it belongs to
  ///      (e.g. CPA → 'ais_polar_chart', anchor → 'anchor_alarm').
  ///   2. Otherwise the SignalK path the alert carries — go to whatever widget
  ///      the user bound to that path (generic notifications like pressure).
  /// Renders nothing when no relevant widget is placed, so VIEW never appears
  /// pointing nowhere. For vessel alerts it also highlights the vessel.
  Widget _buildViewButton(BuildContext context) {
    final dash = Provider.of<DashboardService>(context, listen: false);

    (int, String)? target;
    final src = event.alarmSource;
    if (src != null && src.isNotEmpty) {
      target = dash.findScreenWithToolType(src);
    }
    if (target == null && event.callbackData is NotificationPayload) {
      final key = (event.callbackData as NotificationPayload).notificationKey;
      if (key != null) target = dash.findScreenWithToolPath(key);
    }
    if (target == null) return const SizedBox.shrink();

    final screenIndex = target.$1;
    return _button('VIEW', () {
      dash.setActiveScreen(screenIndex);
      // Enrichment: highlight the vessel for vessel-based alerts once we're on
      // the chart. Harmless for alerts that aren't about a vessel.
      final cb = event.callbackData;
      try {
        if (cb is CpaVesselAlert) {
          Provider.of<CpaAlertService>(context, listen: false)
              .requestHighlight(cb.vesselId);
        } else if (event.subsystem == AlertSubsystem.aisFavorites &&
            cb is String) {
          Provider.of<AISFavoritesService>(context, listen: false)
              .requestHighlight(cb);
        }
      } catch (_) {}
    });
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
            color: Colors.white,
            fontSize: 12,
            fontWeight: label == 'VIEW' ? FontWeight.normal : FontWeight.bold,
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
