# Notification, Alert & Messaging System — Full Architecture Review

**Date:** 2026-03-10
**Branch:** sunshineoncheeks
**Version:** 0.5.43+39

---

## Executive Summary

The notification/alert system has grown into **seven overlapping subsystems** that share no common architecture. A single anchor alarm event can simultaneously fire audio, a system notification, a crew broadcast, a full-screen overlay, and an in-app snackbar — with **no coordination between them**. The settings UI offers granular notification level filters that are **silently ignored** by most alert types. The original deduplication code in `_NotificationManager` is dead. Overlays don't suppress other notifications. The result is a system where the user drowns in redundant alerts they can't control.

---

## Table of Contents

1. [The Seven Subsystems](#1-the-seven-subsystems)
2. [What Actually Happens When an Alert Fires](#2-what-actually-happens-when-an-alert-fires)
3. [The Filter System is Broken](#3-the-filter-system-is-broken)
4. [Overlays Don't Suppress Anything](#4-overlays-dont-suppress-anything)
5. [Dead Code: _NotificationManager Deduplication](#5-dead-code-notificationmanager-deduplication)
6. [Expired Alert Handling Gaps](#6-expired-alert-handling-gaps)
7. [Connection State & Background Behavior](#7-connection-state--background-behavior)
8. [Code Duplication](#8-code-duplication)
9. [Race Conditions](#9-race-conditions)
10. [Notification ID Collision](#10-notification-id-collision)
11. [Dead Ends & Orphaned Code](#11-dead-ends--orphaned-code)
12. [The Full Wiring Diagram](#12-the-full-wiring-diagram)
13. [Complete File Inventory](#13-complete-file-inventory)
14. [Recommendations](#14-recommendations)

---

## 1. The Seven Subsystems

| # | Subsystem | Service | Delivery Channels | Filters Checked |
|---|-----------|---------|-------------------|-----------------|
| 1 | **SignalK Notifications** | `_NotificationManager` in signalk_service.dart | System notif + in-app snackbar | Master only (level filters checked in main.dart snackbar, NOT in system notif) |
| 2 | **Anchor Alarm** | `AnchorAlarmService` | Audio + system notif + crew broadcast + full-screen overlay | **Master only — ignores level filters** |
| 3 | **Anchor Check-In** | `AnchorAlarmService` | Audio + system notif + crew broadcast + full-screen overlay | **Master only — ignores level filters** |
| 4 | **CPA/AIS Alerts** | `CpaAlertService` | Audio + system notif + crew broadcast + in-app snackbar | Master + level filters (only subsystem that checks them) |
| 5 | **NWS Weather Alerts** | `_NotificationManager` + `WeatherAlertsTool` | System notif + in-app snackbar + widget dialog | Master + on-dashboard gate (level filters NOT checked for system notif) |
| 6 | **Clock Alarms** | `ClockAlarmTool` widget | Audio + system notif (full-screen intent) | **Master only — ignores level filters** |
| 7 | **Crew Messages** | `MessagingService` | System notif (grouped) | Master + crew prefs (level filters NOT checked) |
| 8 | **Intercom** | `IntercomService` | System notif + status indicator overlay | **Master only — ignores all filters** |

**The core problem:** Each subsystem was built independently and calls `NotificationService` methods directly, each doing its own (or no) filter checking. There is no single enforcement point.

---

## 2. What Actually Happens When an Alert Fires

### Anchor Alarm Triggers

When the boat drags anchor, the user is hit with **ALL of these simultaneously**:

| # | Channel | Source | File:Line | Can User Disable? |
|---|---------|--------|-----------|-------------------|
| 1 | Looping alarm audio (5s repeat) | `_playAlarmSound()` | anchor_alarm_service.dart:663 | No filter — always plays |
| 2 | Android/iOS system notification | `showAlarmNotification()` | anchor_alarm_service.dart:653 | Master toggle only |
| 3 | Crew alert broadcast | `messagingService.sendAlert()` | anchor_alarm_service.dart:660 | No filter — always sends |
| 4 | Full-screen red overlay (tool) | `_buildAlarmOverlay()` | anchor_alarm_tool.dart:1401 | No filter — always shows |
| 5 | In-app snackbar (via SignalK notif stream) | `SignalKNotificationListener` | main.dart:651 | In-app level filter |

That's **five simultaneous alerts** for one event. The audio loops indefinitely. The overlay blocks the tool. The snackbar sits on top of the overlay. The crew message goes to every device on the boat.

### Anchor Check-In Required (Every N Minutes)

| # | Channel | Source | File:Line |
|---|---------|--------|-----------|
| 1 | System notification | `showAlarmNotification()` | anchor_alarm_service.dart:739 |
| 2 | Crew alert broadcast | `messagingService.sendAlert()` | anchor_alarm_service.dart:747 |
| 3 | Full-screen orange overlay with countdown | `_buildCheckInOverlay()` | anchor_alarm_tool.dart:1357 |

If the grace period expires without acknowledgment:
| 4 | **All 5 anchor alarm channels fire ON TOP of the check-in channels** |

The old check-in notification is NOT cleared when escalating to alarm (anchor_alarm_service.dart:702-708 — missing `cancelAlarmNotification('check_in')`). User now has **TWO** system notifications, **TWO** crew broadcasts, **TWO** overlays stacked, and audio.

### CPA Vessel Alarm

| # | Channel | Source | File:Line |
|---|---------|--------|-----------|
| 1 | Looping alarm audio (5s repeat) | `_playAlarmSound()` | cpa_alert_service.dart:388 |
| 2 | System notification | `showAlarmNotification()` | cpa_alert_service.dart:339 |
| 3 | Crew alert broadcast (if enabled) | `messagingService.sendAlert()` | cpa_alert_service.dart:349 |
| 4 | In-app snackbar | `onAlertTriggered` callback | cpa_alert_service.dart:354 |

CPA is the **only subsystem** that checks level filters before system notification (line 331).

### Clock Alarm

| # | Channel | Source | File:Line |
|---|---------|--------|-----------|
| 1 | Haptic feedback | `HapticFeedback.heavyImpact()` | clock_alarm_tool.dart:419 |
| 2 | System notification (full-screen intent) | `showAlarmNotification()` | clock_alarm_tool.dart:422 |
| 3 | Looping alarm audio | `_playAlarmSound()` | clock_alarm_tool.dart:431 |

No filters checked at all. Clock alarms bypass everything except the master toggle inside `showAlarmNotification()`.

---

## 3. The Filter System is Broken

### What the Settings UI Offers

The settings screen (`settings_screen.dart:323-523`) presents a sophisticated filter matrix:

| Filter | UI Present | Default |
|--------|-----------|---------|
| Master notifications toggle | Yes | Off |
| In-app: Emergency | Yes | On |
| In-app: Alarm | Yes | Off |
| In-app: Warn | Yes | Off |
| In-app: Alert | Yes | Off |
| In-app: Normal | Yes | Off |
| In-app: Nominal | Yes | Off |
| System: Emergency | Yes | On |
| System: Alarm | Yes | Off |
| System: Warn | Yes | Off |
| System: Alert | Yes | Off |
| Crew messages | Yes | On |
| Crew alerts | Yes | On |

### What the Code Actually Checks

| Notification Path | Master? | Level Filter? | Crew Filter? | Reality |
|-------------------|---------|---------------|--------------|---------|
| `showNotification()` (SignalK generic) | Yes (line 355) | **NO** | N/A | Level filters ignored |
| `showAlarmNotification()` (anchor/clock/CPA) | Yes (line 644) | **NO** | N/A | Level filters ignored |
| `showCrewMessageNotification()` | Yes (line 496) | **NO** | Yes (in MessagingService) | Level filters ignored |
| `showIntercomNotification()` | Yes (line 728) | **NO** | N/A | All filters ignored |
| In-app snackbar (main.dart) | N/A | Yes (line 545) | N/A | **Only place filters work** |
| CPA system notification | Yes | Yes (cpa_alert_service:331) | Yes | **Only alarm service that filters** |

**The gap:** `NotificationService` methods check `_masterEnabled` and nothing else. The level filters in StorageService exist, the settings UI configures them, but **only CPA alerts and the main.dart in-app snackbar actually read them.** The user toggles "System: Alarm → Off" expecting anchor alarms to stop showing system notifications, but they don't.

### Where Filters SHOULD Be Checked But Aren't

1. **`showAlarmNotification()`** — should check `getSystemNotificationFilter('alarm')` before showing
2. **`showNotification()`** — should check `getSystemNotificationFilter(notification.state)` before showing
3. **`showCrewMessageNotification()`** — should check crew filter preferences
4. **`showIntercomNotification()`** — should have its own toggle
5. **Anchor alarm audio** — has no mute/filter at all (only acknowledge stops it)
6. **Crew alert broadcasts** — anchor alarm sends crew alerts with no user preference check

---

## 4. Overlays Don't Suppress Anything

### The Stacking Problem

The anchor alarm tool uses `Positioned.fill()` overlays in a Stack (anchor_alarm_tool.dart:424-432, 464-472):

```dart
// Both can be visible simultaneously!
if (_alarmService.awaitingCheckIn)
  Positioned.fill(child: _buildCheckInOverlay()),  // Orange overlay
if (state.alarmState.isAlarming)
  Positioned.fill(child: _buildAlarmOverlay(state)),  // Red overlay ON TOP
```

While these overlays are visible:
- System notifications still fire (no suppression)
- In-app snackbars still show (ScaffoldMessenger is global, not tool-scoped)
- Crew messages still broadcast (MessagingService doesn't know about overlays)
- Audio still plays (independent of overlay state)
- **Other tools' alerts still fire** (CPA can fire while anchor overlay is showing)

### No Cross-Subsystem Awareness

No subsystem knows what the others are doing:
- Anchor alarm doesn't know CPA is also alarming
- Clock alarm doesn't know anchor check-in overlay is up
- In-app snackbar (main.dart) doesn't know a full-screen overlay is covering the screen
- Multiple audio players can play simultaneously (anchor + CPA + clock)

---

## 5. Dead Code: _NotificationManager Deduplication

### What Was Built

`_NotificationManager` in `signalk_service.dart:2458-2716` contains a complete notification deduplication system:

| Component | Lines | Purpose | Status |
|-----------|-------|---------|--------|
| `_notificationChannel` (WebSocket) | 2462 | Separate WS for notifications | **DEAD — never connected** |
| `connectNotificationChannel()` | 2531-2566 | Open notification WS | **DEAD — never called** |
| `disconnectNotificationChannel()` | 2568-2584 | Close notification WS | **DEAD — never called** |
| `subscribeToNotifications()` | 2587-2607 | Subscribe to `notifications.*` | **DEAD — never called** |
| `handleNotificationMessage()` | 2609-2631 | Parse WS deltas | **DEAD — never called** |
| `_lastNotificationState` | 2472 | Dedup: last state per key | **Active but partially orphaned** |
| `_lastNotificationTime` | 2473 | Throttle: 30s per key+state | **Active but partially orphaned** |
| `_recentNotifications` | 2474 | 10-second window cache | **Active — used by anchor alarm** |
| `handleNotification()` | 2634-2710 | Process + filter + emit | **Active — called from main WS** |
| `_notificationController` | 2465 | Broadcast stream | **Active — subscribed by main.dart** |

### What Actually Happens

Since the Phase A1 (Single WebSocket) refactor, notifications route through the main WebSocket handler `_handleMessage()`, which calls `_notificationManager.handleNotification()` directly. The separate notification WebSocket channel code (~100 lines) is completely dead.

The deduplication in `handleNotification()` (temporal throttle: same key+state within 30s suppressed) IS active and working. But it only deduplicates the stream emission — it does NOT prevent:
- Multiple `showAlarmNotification()` calls from services
- Multiple crew alerts from services
- Multiple audio playback starts

The dedup only affects the SignalK notification stream → in-app snackbar path.

### What Should Be Removed

- `_notificationChannel` field and all connection/subscription methods (~100 lines)
- `handleNotificationMessage()` method (dead — parsing logic never reached)

---

## 6. Expired Alert Handling Gaps

### NWS Weather Alerts

**Expiration check location:** `_NotificationManager.handleNotification()` (signalk_service.dart:2643-2666) checks `NWSAlertUtils.isAlertActive()` using expires/ends/urgency fields.

**Gap:** This check happens before stream emission. But `showNotification()` (called from main.dart:554) does **not** re-check expiration. If the notification was emitted just before expiring, or if there's any delay in processing, the system notification displays for an expired alert.

**Gap:** Weather alerts tool (weather_alerts_tool.dart) tracks seen alert IDs to detect "new" alerts. But if an expired alert's ID is recycled by NWS (unlikely but possible), it won't be treated as new.

### CPA Alert Sunset

**Sunset logic:** Alerts older than 48 hours are pruned in `_evaluate()` (cpa_alert_service.dart:246-255).

**Gap:** `_evaluate()` only runs when AIS data updates. If a vessel goes out of range and AIS updates stop, the 48-hour sunset never fires. The alert persists in memory and the system notification stays in the tray indefinitely.

**Fix needed:** Periodic cleanup timer independent of AIS updates.

### Anchor Check-In → Alarm Escalation

**Gap:** When check-in grace period expires (anchor_alarm_service.dart:755-760):
1. `triggerCheckInAlarm()` fires new alarm notification + crew alert
2. Old check-in notification (alarmId: `'check_in'`) **is NOT cancelled**
3. Old check-in crew alert message persists
4. User sees duplicate notifications for the same escalation event

**Missing line in `triggerCheckInAlarm()`:**
```dart
_notificationService.cancelAlarmNotification('check_in');  // Should be here
```

### No Stale Notification Sweep

When the app is killed during an active alarm, system notifications persist in the OS tray. On restart, there is no mechanism to clear stale notifications. The cold-start handler (notification_service.dart:134-151) only processes tapped notifications, not stale ones.

### Clock Alarm Expiration

Clock alarms have snooze with `snoozeUntil` timestamp, but no mechanism to clear the system notification when snooze expires and the alarm should re-fire. The full-screen intent fires again, potentially stacking with the old notification.

---

## 7. Connection State & Background Behavior

### WebSocket Disconnects

| Subsystem | Behavior on Disconnect | Gap |
|-----------|----------------------|-----|
| SignalK Notifications | Stream stops | OK |
| Anchor Alarm | **Continues running on cached state** | Alarm state may be stale |
| Anchor Check-In | **Timer keeps ticking** | Can fire check-in while disconnected |
| CPA Alerts | **Continues monitoring stale AIS data** | Alerts on outdated positions |
| Crew Messages | Polling stops, local cache intact | OK |
| Intercom | WebRTC signaling stops | OK |
| Weather Alerts | Widget shows cached data | OK |

**Critical:** Anchor check-in timer fires while disconnected. User gets check-in notification + crew alert + overlay, but the crew alert fails silently (no connection). Audio still plays.

### App Backgrounded

- ForegroundService keeps WebSocket alive (foreground_service.dart:36-63)
- All timers continue (check-in, CPA evaluation, crew polling)
- System notifications fire in background (correct behavior)
- Audio continues playing in background (potentially annoying)
- No mechanism to pause non-critical notifications when backgrounded

### App Killed & Restarted

- Cold-start payload processing: `_pendingPayload` handles notification tap that launched app (notification_service.dart:70-78)
- All alarm states reset (anchor check-in countdown, CPA alerts, active alarms)
- Stale system notifications remain in tray with no cleanup
- No state persistence for in-progress alarms across restarts

---

## 8. Code Duplication

### Audio Playback — Triplicated (Critical)

Nearly identical alarm audio code in three files:

| File | Play Method | Stop Method | Lines |
|------|-------------|-------------|-------|
| `anchor_alarm_service.dart` | `_playAlarmSound()` :663-692 | `_stopAlarmSound()` :694-700 | ~45 lines |
| `cpa_alert_service.dart` | `_playAlarmSound()` :388-419 | `_stopAlarmSound()` :421-427 | ~45 lines |
| `clock_alarm_tool.dart` | `_playAlarmSound()` :253-295 | `_stopAlarmSound()` :297-308 | ~60 lines |

All three:
1. Create `AudioPlayer()`
2. Set volume 1.0
3. Play asset
4. Start `Timer.periodic(5 seconds)` that disposes old player, creates new one, replays
5. Check alarm-active condition in timer; cancel if done

**Total duplicated:** ~135 lines of identical logic.

### Alarm Sound Definitions — Duplicated

- `clock_alarm_tool.dart` — Full `AlarmSound` enum with metadata (name, description, icon, assetPath)
- `anchor_alarm_service.dart` — Raw string names (`'bell'`, `'foghorn'`, etc.)
- `cpa_alert_service.dart` — Raw string names (same set)

### Alert-to-Tool Routing — String Prefix Matching

`MessagingService` detects alert origin by parsing message content:
```dart
// Fragile: if wording changes, routing breaks
if (content.startsWith('ANCHOR ALARM:')) → toolTypeId = 'anchor_alarm'
if (content.startsWith('CPA')) → toolTypeId = 'ais_polar_chart'
```

### Snackbar Construction — Duplicated in main.dart and ais_polar_chart_tool.dart

Both `SignalKNotificationListener._handleNotification()` (main.dart:651-720) and `_onCpaAlertTriggered()` (ais_polar_chart_tool.dart:131-192) build nearly identical snackbars with:
- Icon + color by severity
- Tap handler with navigation
- "TAP: {screenName}" hint
- DISMISS action
- Duration by severity

---

## 9. Race Conditions

### AudioPlayer Lifecycle in Timer (HIGH)

All three alarm services share this pattern:

```dart
_alarmRepeatTimer = Timer.periodic(Duration(seconds: 5), (_) async {
  _alarmPlayer?.dispose();           // Step 1
  _alarmPlayer = AudioPlayer();      // Step 2
  await _alarmPlayer!.play(...);     // Step 3 — CRASH if stop() called between 2 and 3
});
```

If `_stopAlarmSound()` runs between Step 2 and Step 3:
1. Timer assigns new player (Step 2)
2. `_stopAlarmSound()` disposes it and sets `_alarmPlayer = null`
3. Timer does `_alarmPlayer!.play()` — **NullPointerException** (force-unwrap on null)

### WeatherAlertsNotifier Double-Fire (MEDIUM)

```dart
void requestExpandAlert(String alertId) {
  _expandAlertId = alertId;
  notifyListeners();
  Future.delayed(Duration(milliseconds: 100), () {
    _expandAlertId = null;  // Clears after 100ms for re-trigger
  });
}
```

Two calls within 100ms: first delayed clear wipes the second request.

### Check-In Grace Period Edge (LOW)

If user acknowledges at the exact moment the grace timer fires, both `acknowledgeCheckIn()` and `_onCheckInGraceExpired()` can execute. The `if (_awaitingCheckIn)` guard mitigates but doesn't eliminate the race.

---

## 10. Notification ID Collision

Two ID generation schemes share the same integer space:

**Stable IDs (alarms):** `alarmId.hashCode.abs() % 100000 + 1` → range 1–100,001
**Sequential IDs (crew/intercom):** `++_notificationIdCounter` → starts at 0, increments forever

When the counter reaches 1–100,001, a crew message notification will collide with an alarm notification. Cancelling one cancels the other.

---

## 11. Dead Ends & Orphaned Code

| Code | Location | Status | Action |
|------|----------|--------|--------|
| `connectNotificationChannel()` | signalk_service.dart:2531 | Dead since Phase A1 | Remove |
| `disconnectNotificationChannel()` | signalk_service.dart:2568 | Dead since Phase A1 | Remove |
| `subscribeToNotifications()` | signalk_service.dart:2587 | Dead since Phase A1 | Remove |
| `handleNotificationMessage()` | signalk_service.dart:2609 | Dead since Phase A1 | Remove |
| `_notificationChannel` field | signalk_service.dart:2462 | Dead | Remove |
| `weather_nws` switch case | notification_service.dart:~235 | Unreachable (early return above) | Remove |
| `saveNotificationLevelFilter()` | storage_service.dart:771 | Legacy wrapper | Remove |
| `getNotificationLevelFilter()` | storage_service.dart:776 | Legacy wrapper | Remove |
| Anchor callback ignores `alarmId` param | anchor_alarm_service.dart:172 | Param received but unused | Use it or document |

---

## 12. The Full Wiring Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                            USER EXPERIENCE                              │
│                                                                         │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐ │
│  │  System   │ │  In-App  │ │ Full-Scrn│ │  Audio   │ │    Crew      │ │
│  │  Notif    │ │ Snackbar │ │ Overlay  │ │ Alarm    │ │  Broadcast   │ │
│  └────▲─────┘ └────▲─────┘ └────▲─────┘ └────▲─────┘ └──────▲───────┘ │
│       │             │            │             │              │         │
├───────┼─────────────┼────────────┼─────────────┼──────────────┼─────────┤
│       │             │            │             │              │         │
│  ┌────┴─────────────┴────┐  ┌───┴─────────────┴──────────────┴───┐     │
│  │   NotificationService │  │        Direct from Services        │     │
│  │   (master check only) │  │     (NO centralized filtering)    │     │
│  └────▲──────▲──────▲────┘  └───▲─────────▲──────────▲───────────┘     │
│       │      │      │           │         │          │                 │
│  ┌────┴──┐ ┌─┴───┐ ┌┴────┐ ┌───┴──┐  ┌───┴───┐ ┌───┴────┐           │
│  │SignalK│ │Crew │ │Inter│ │Anchor│  │  CPA  │ │ Clock  │           │
│  │Stream │ │Msgs │ │com  │ │Alarm │  │ Alert │ │ Alarm  │           │
│  └───────┘ └─────┘ └─────┘ └──────┘  └───────┘ └────────┘           │
│                                                                         │
│  Filters:                                                               │
│  ═══════                                                                │
│  Master toggle ── checked by NotificationService (all paths)            │
│  Level filters ── checked ONLY by: main.dart snackbar + CPA service     │
│  Crew filters ─── checked ONLY by: MessagingService                     │
│  Dashboard gate ─ checked ONLY by: _NotificationManager (NWS)          │
│  Audio ────────── NO FILTER AT ALL (only manual acknowledge stops it)   │
│  Overlays ─────── NO FILTER AT ALL (always shown when alarm active)     │
│  Crew broadcasts─ NO FILTER AT ALL (anchor alarm always sends)          │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 13. Complete File Inventory

### Services (8 files)

| File | Lines | Role | Issues |
|------|-------|------|--------|
| `lib/services/notification_service.dart` | ~790 | Central notification hub | No level filter enforcement |
| `lib/services/notification_navigation_service.dart` | ~120 | Tap-to-navigate routing | None |
| `lib/services/anchor_alarm_service.dart` | ~786 | Anchor alarm + check-in | Bypasses filters, check-in escalation bug |
| `lib/services/cpa_alert_service.dart` | ~440 | AIS collision alerts | Only service that checks filters |
| `lib/services/messaging_service.dart` | ~300 | Crew text/status/alert messaging | String-prefix routing fragile |
| `lib/services/intercom_service.dart` | ~350 | WebRTC voice intercom | No notification filters |
| `lib/services/foreground_service.dart` | ~137 | Background keep-alive | Tied to master toggle |
| `lib/services/storage_service.dart` | 690-778 | Notification preferences | Legacy wrappers, filters defined but unused |
| `lib/services/signalk_service.dart` | 2458-2716 | `_NotificationManager` (embedded) | ~100 lines dead WS code |

### Models (4 files)

| File | Role | Issues |
|------|------|--------|
| `lib/models/notification_payload.dart` | Structured tap payload | None |
| `lib/models/crew_message.dart` | Message model + presets | Alert type detection by string prefix |
| `lib/models/anchor_state.dart` | Anchor alarm states + check-in config | None |
| `lib/models/cpa_alert_state.dart` | CPA alert levels + config | None |

### UI Components (9 files)

| File | Role | Issues |
|------|------|--------|
| `lib/main.dart` (458-733) | `SignalKNotificationListener` + overlays | Only place in-app level filters work |
| `lib/widgets/tools/anchor_alarm_tool.dart` | Overlays: CheckIn (1357-1399) + Alarm (1401-1441) | Overlays don't suppress other notifications |
| `lib/widgets/tools/ais_polar_chart_tool.dart` | CPA alert snackbar (100-193) | Duplicates snackbar pattern from main.dart |
| `lib/widgets/tools/weather_alerts_tool.dart` | NWS alert widget + `WeatherAlertsNotifier` | requestExpandAlert race condition |
| `lib/widgets/tools/clock_alarm_tool.dart` | Clock alarm + audio | Bypasses all filters |
| `lib/widgets/crew/incoming_call_overlay.dart` | Intercom call banner | None |
| `lib/widgets/crew/intercom_panel.dart` | `IntercomStatusIndicator` (621-694) | None |
| `lib/screens/settings_screen.dart` | Notification preference toggles (323-523) | UI configures filters code ignores |
| `lib/screens/dashboard_screen.dart` | Service wiring to widgets | None |

### Utilities (1 file)

| File | Role |
|------|------|
| `lib/utils/nws_alert_utils.dart` | Shared `isAlertActive()` check |

### Audio Assets (6 files)

```
assets/sounds/alarm_bell.mp3
assets/sounds/alarm_chimes.mp3
assets/sounds/alarm_ding.mp3
assets/sounds/alarm_dog.mp3
assets/sounds/alarm_foghorn.mp3
assets/sounds/alarm_whistle.mp3
```

---

## 14. Recommendations

### Tier 1 — Filter Enforcement (Most Impact)

| # | Problem | Fix |
|---|---------|-----|
| 1 | Level filters ignored by NotificationService | Add `StorageService` reference to `NotificationService`; check `getSystemNotificationFilter(level)` in `showNotification()` and `showAlarmNotification()` |
| 2 | Anchor alarm bypasses all filters | Pass through NotificationService filter checks; add user preference for crew broadcast |
| 3 | Clock alarm bypasses all filters | Add level filter check before `showAlarmNotification()` |
| 4 | Crew broadcasts have no user control | Add "Send crew alerts on anchor alarm" toggle (like CPA has `cpaSendCrewAlert`) |
| 5 | No cross-subsystem coordination | Add `AlertCoordinator` that serializes alert delivery and prevents stacking |

### Tier 2 — Alert Stacking & Expiration

| # | Problem | Fix |
|---|---------|-----|
| 6 | Overlays don't suppress snackbars | When overlay is active, suppress in-app snackbar for same subsystem |
| 7 | Check-in escalation leaves orphan notification | Add `cancelAlarmNotification('check_in')` to `triggerCheckInAlarm()` |
| 8 | CPA sunset only runs on AIS updates | Add hourly cleanup timer |
| 9 | No stale notification sweep on restart | Clear all notifications on cold start, re-evaluate active alarms |
| 10 | Multiple audio players can overlap | Single `AlarmAudioPlayer` with priority queue (highest severity wins) |

### Tier 3 — Code Quality

| # | Problem | Fix |
|---|---------|-----|
| 11 | Audio playback triplicated (135 lines) | Extract shared `AlarmAudioPlayer` class |
| 12 | Alarm sound definitions duplicated | Single `AlarmSound` enum shared across services |
| 13 | Snackbar construction duplicated | Extract `AlertSnackBar` builder widget |
| 14 | String-prefix crew alert routing | Add `alertType` field to `CrewMessage` model |
| 15 | Dead _NotificationManager WS code (~100 lines) | Remove dead methods and field |
| 16 | Notification ID collision risk | Start sequential counter at 100,002 |

### Tier 4 — Safety

| # | Problem | Fix |
|---|---------|-----|
| 17 | AudioPlayer race in timer callback | Guard against null; cancel timer before disposing player |
| 18 | AudioPlayer stop/dispose unguarded (anchor, CPA) | Add try-catch like clock_alarm_tool has |
| 19 | Check-in timer fires while disconnected | Pause check-in timer on disconnect |
| 20 | WeatherAlertsNotifier double-fire race | Use Completer or debounce pattern instead of Future.delayed |

### Suggested Architecture: AlertCoordinator

The fundamental problem is that seven subsystems independently fire five delivery channels with no coordination. A centralized `AlertCoordinator` would:

1. **Single entry point** for all alerts: `coordinator.fire(alert)`
2. **Enforce filters** at the coordinator level (not per-subsystem)
3. **Prevent stacking** (suppress snackbar when overlay is active for same event)
4. **Manage audio priority** (one alarm sound at a time, highest severity wins)
5. **Centralize crew broadcasting** with user preference checks
6. **Handle expiration** with periodic sweep timer
7. **Track active alerts** across all subsystems for cross-subsystem awareness

```dart
class AlertCoordinator {
  void fireAlert({
    required String source,       // 'anchor_alarm', 'cpa', 'clock', etc.
    required AlertSeverity level, // emergency, alarm, warn, alert, normal
    required String message,
    bool playAudio = false,
    bool showOverlay = false,
    bool broadcastCrew = false,
    String? alarmSound,
  }) {
    // 1. Check master + level filters
    // 2. Deduplicate (temporal + state)
    // 3. Show system notification (if filter allows)
    // 4. Show in-app snackbar (if filter allows AND no overlay active)
    // 5. Play audio (if no higher-priority audio playing)
    // 6. Broadcast crew alert (if user preference allows)
    // 7. Track for expiration sweep
  }
}
```

---

*Report generated 2026-03-10. Covers version 0.5.43+39 on branch sunshineoncheeks.*
