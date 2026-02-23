# What's New in v0.5.6

## Release Notes (Google Play - max 500 chars)

v0.5.6 Custom Resources & Auth Fixes

NEW: ZedDisplay now uses dedicated SignalK resource types for crew messaging, profiles, files, channels, and alarms. Other apps won't see your ZedDisplay data.

FIXED: Auth tokens now stored per connection ID, not server URL. Multiple connections to same server work correctly.

FIXED: Deleting a connection removes its auth token.

## Release Notes (App Store / TestFlight - max 4000 chars)

### Custom Resource Types (NEW)
- **Dedicated Resources** - Migrated from generic `notes` to custom resource types:
  - `zeddisplay-messages` for crew messaging
  - `zeddisplay-crew` for crew profiles and presence
  - `zeddisplay-files` for file sharing metadata
  - `zeddisplay-channels` for intercom channels
  - `zeddisplay-alarms` for shared alarms
- **Privacy Improvement** - Other apps reading `notes` will no longer see ZedDisplay data
- **Auto-creation** - Resource types are automatically created on first connection

### Authentication (FIXED)
- **Token Storage** - Auth tokens now stored by connection ID instead of server URL
- **Multiple Connections** - Each connection maintains its own authentication state
- **Connection Deletion** - Deleting a connection now removes its associated auth token

---

# Previous: v0.5.5

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
