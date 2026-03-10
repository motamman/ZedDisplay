# AlertCoordinator — Implementation Plan

## Status: IMPLEMENTED

Implemented on branch `sunshineoncheeks`. All 5 phases complete.

## Summary

Central alert delivery gateway replacing 7 independently-built subsystems firing 5 delivery channels. AlertCoordinator enforces filters centrally.

### New Files
| File | Purpose |
|------|---------|
| `lib/models/alert_event.dart` | AlertEvent, AlertSeverity, AlertSubsystem enums/model |
| `lib/services/alarm_audio_player.dart` | Singleton audio player with severity preemption |
| `lib/services/alert_coordinator.dart` | Central alert delivery + filter enforcement |

### Modified Files
| File | Changes |
|------|---------|
| `lib/services/anchor_alarm_service.dart` | Removed audio code, delegates to AlertCoordinator |
| `lib/services/cpa_alert_service.dart` | Removed audio code + filter logic, delegates to AlertCoordinator |
| `lib/widgets/tools/clock_alarm_tool.dart` | Delegates audio + notifications to AlertCoordinator |
| `lib/main.dart` | Simplified notification handler, wired AlertCoordinator into Provider tree |
| `lib/services/signalk_service.dart` | Removed ~80 lines dead _NotificationManager WS code |
| `lib/services/notification_service.dart` | Removed unreachable weather_nws switch case |
| `lib/services/storage_service.dart` | Added crew broadcast prefs, removed legacy wrappers |
| `lib/screens/settings_screen.dart` | Added crew broadcast toggles |
| `lib/widgets/tools/anchor_alarm_tool.dart` | Passes AlertCoordinator to service, registers overlay state |
| `lib/widgets/tools/ais_polar_chart_tool.dart` | Passes AlertCoordinator to CpaAlertService |
| `test/widget_test.dart` | Updated for new required params |

### Key Design Decisions
- Subsystems keep domain logic, only delegate delivery
- Fallback paths for when AlertCoordinator is not available (backward compat)
- Audio always fires regardless of master toggle (safety-critical)
- Severity preemption: only one audio player, higher severity wins
- Overlay suppresses snackbar for same subsystem
- Per-subsystem crew broadcast toggles in settings
