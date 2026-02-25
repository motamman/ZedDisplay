# What's New in v0.5.25

## Release Notes (Google Play - max 500 chars)

v0.5.25 Channel Subscriptions

NEW: Subscribe/unsubscribe from intercom audio channels. Tap channel icons in Crew List to toggle. Emergency channel (CH16) always on. Captains and First Mates can manage any crew member's subscriptions.

IMPROVED: Tools now default to full grid size. Tools without config can be placed directly.

## Release Notes (App Store / TestFlight - max 4000 chars)

### Channel Subscriptions (NEW)
- **Per-User Subscriptions** - Each crew member can choose which audio channels to receive
- **Crew List Icons** - Channel subscription status shown as icons next to each crew member
- **Toggle Subscriptions** - Tap channel icons to subscribe/unsubscribe from channels
- **Emergency Always On** - CH16 (Emergency) cannot be disabled - always subscribed
- **Admin Control** - Captains and First Mates can manage any crew member's subscriptions
- **Persistence** - Subscriptions saved locally and persist across app restarts
- **User Management** - Admins can also edit subscriptions in User Management Tool

### Tool Placement Improvements (IMPROVED)
- **Default Full Grid** - New tools default to 8x8 size for simpler initial placement
- **Direct Placement** - Tools without required configuration skip config dialog and place directly

---

# Previous: v0.5.24

## Release Notes (Google Play - max 500 chars)

v0.5.24 Anchor Widget Layout

IMPROVED: Anchor alarm widget now uses responsive layout. On wider screens (≥600px), map and controls display side-by-side. On narrow screens, they stack vertically. Controls no longer overlay the map - each gets 50% of the widget area.

## Release Notes (App Store / TestFlight - max 4000 chars)

### Anchor Widget Responsive Layout (IMPROVED)
- **Wide Mode** - Map and controls side-by-side on screens ≥600px wide
- **Narrow Mode** - Map and controls stacked vertically on smaller screens
- **Space Sharing** - Each section gets 50% of widget area (no more overlay)
- **Scrollable Controls** - Control panel scrolls when space is limited
- **Adaptive View Controls** - Buttons positioned appropriately for each layout

---

# Previous: v0.5.23

## Release Notes (Google Play - max 500 chars)

v0.5.23 Anchor Widget Fix

FIXED: Anchor alarm widget now displays values with proper unit symbols. Previously showed raw numbers without units (e.g., "29.0" instead of "29 m").

The anchor-alarm plugin uses a different metadata format that wasn't being handled correctly.

## Release Notes (App Store / TestFlight - max 4000 chars)

### Anchor Widget Unit Display (FIXED)
- **Unit Symbols** - Anchor values (distance, alarm radius, rode length) now show with proper units
- **Root Cause** - Anchor-alarm plugin sends `explicit: true` in displayUnits, skipping formula expansion
- **Solution** - Added category-based conversion lookup when formula not provided
- **Identity Handling** - Correctly handles when user's preferred unit matches SI unit (m→m)

---

# Previous: v0.5.22

## Release Notes (Google Play - max 500 chars)

v0.5.22 iOS App Icons

FIXED: iOS app now uses custom branded icons matching Android. Previously iOS was using generic Flutter default icons.

## Release Notes (App Store / TestFlight - max 4000 chars)

### iOS App Icons (FIXED)
- **Branded Icons** - iOS app now displays custom ZedDisplay icons matching Android
- **App Store Ready** - Alpha channel removed for App Store compliance
- **All Sizes** - Generated all 22 required iOS icon sizes

---

# Previous: v0.5.21

## Release Notes (Google Play - max 500 chars)

v0.5.21 Server Load & Connection Fixes

FIXED: Reduced aggressive polling causing SignalK server issues. Polling intervals increased for messaging (5s→15s), crew presence (15s→30s), admin tools (10s→30s). Admin tools skip polling without valid auth token.

FIXED: "Connection Lost" overlay no longer flashes during reconnect attempts.

## Release Notes (App Store / TestFlight - max 4000 chars)

### Server Load Reduction (FIXED)
- **Polling Intervals** - Reduced server load by increasing poll intervals
  - Messaging: 5s → 15s (67% fewer requests)
  - Crew presence: 15s → 30s (50% fewer requests)
  - Admin tools: 10s → 30s (67% fewer requests)
- **Auth Spam** - User Management and Device Access tools now skip polling when no valid auth token, eliminating thousands of failed 401 requests per day
- **Race Conditions** - Reduced probability of concurrent read/write collisions on SignalK resources

### Connection Overlay (FIXED)
- **No More Flashing** - "Connection Lost" overlay no longer flashes during brief reconnect cycles
- **Smoother UX** - Overlay only appears when connection is truly lost

---

# Previous: v0.5.20

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

### iOS Background Audio (NEW)
- **Background Modes** - Voice calls now continue when app is backgrounded
- **VoIP Support** - Calls stay connected when switching apps or locking screen

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
