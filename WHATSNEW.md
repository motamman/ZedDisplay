# What's New in v0.5.20

## Release Notes (Google Play - max 500 chars)

v0.5.20 Crew Presence Fix

FIXED: Crew members now correctly show as online when connected to the same SignalK server. Previously, other crew appeared offline even when messaging worked.

The bug was caused by a key mismatch between URL-encoded and canonical user IDs in presence tracking.

## Release Notes (App Store / TestFlight - max 4000 chars)

### Crew Presence (FIXED)
- **Online Status** - Crew members now correctly appear online when connected
- **Root Cause** - Presence was stored with URL-encoded keys (`user%3Arima`) but looked up with canonical IDs (`user:rima`)
- **Impact** - Direct voice calls and online indicators now work correctly
- **Messaging** - Text messaging was unaffected (used different lookup path)

---

# Previous: v0.5.6

## Release Notes (Google Play - max 500 chars)

v0.5.5 Autopilot V2 Tool

NEW: Redesigned circular autopilot with nested controls. Banana-shaped heading adjustment buttons, mode selector, tack/gybe buttons, and draggable target heading.

NEW: Crew members can now be removed from the server. Captain can remove any crew, users can remove themselves.

IMPROVED: Responsive portrait/landscape layouts.

## Release Notes (App Store / TestFlight - max 4000 chars)

### Autopilot V2 Tool (NEW)
- **Circular Design** - Redesigned autopilot with nested controls
- **Banana Buttons** - Heading adjustment buttons (+1, -1, +10, -10) arced around inner circle
- **Mode Selector** - Compass, Wind, Route modes with engage/standby toggle
- **Tack/Gybe** - Wind mode buttons positioned by turn direction
- **Advance Waypoint** - Route mode button at top
- **Dodge Mode** - Center circle button for Route mode
- **Draggable Target** - Long-press to drag target heading with visual feedback
- **Command Queue** - Incremental commands with acknowledgment tracking

### Crew Deletion (NEW)
- Captain can remove any crew member
- Any user can remove themselves
- Confirmation dialogs before deletion
- Clears both server and local storage

---
