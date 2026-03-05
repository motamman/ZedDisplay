# ToolInfoButton Implementation Guide

This guide documents the standard appearance and placement for `ToolInfoButton` across all tools in ZedDisplay.

## Standard Appearance

All info buttons must use this consistent style:

```dart
Container(
  decoration: BoxDecoration(
    color: Colors.black.withValues(alpha: 0.5),
    shape: BoxShape.circle,
  ),
  child: ToolInfoButton(
    toolId: 'your_tool_id',
    signalKService: signalKService,
    iconSize: 20,
    iconColor: Colors.white,
  ),
),
```

**Key style properties:**
- **Icon**: `Icons.info_outline` (built into ToolInfoButton)
- **Icon size**: 20px
- **Icon color**: `Colors.white`
- **Background**: Semi-transparent black circle (`Colors.black.withValues(alpha: 0.5)`)

## Positioning Rules

### 1. Top-right corner (default)

For tools without other overlay controls:

```dart
Stack(
  children: [
    // Your tool content
    YourToolWidget(),

    // Info button in top-right
    Positioned(
      top: 8,
      right: 8,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: ToolInfoButton(
          toolId: 'your_tool_id',
          signalKService: signalKService,
          iconSize: 20,
          iconColor: Colors.white,
        ),
      ),
    ),
  ],
)
```

### 2. With other controls (refresh button, etc.)

When multiple buttons exist, group them in a Row with info button on the LEFT:

```dart
Positioned(
  top: 8,
  right: 8,
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      // Info button - ALWAYS leftmost
      Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: ToolInfoButton(
          toolId: 'your_tool_id',
          signalKService: signalKService,
          iconSize: 20,
          iconColor: Colors.white,
        ),
      ),
      const SizedBox(width: 4),
      // Refresh button (or other controls)
      Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: IconButton(
          icon: const Icon(Icons.refresh, size: 20, color: Colors.white),
          onPressed: _onRefresh,
          // ...
        ),
      ),
    ],
  ),
),
```

### 3. In header rows (non-overlay)

For tools with a header row (like RPi Monitor):

```dart
Row(
  children: [
    Icon(Icons.memory, color: theme.colorScheme.primary, size: 20),
    const SizedBox(width: 6),
    Flexible(
      child: Text('Tool Name', style: theme.textTheme.titleSmall),
    ),
    // Info button after title
    Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        shape: BoxShape.circle,
      ),
      child: ToolInfoButton(
        toolId: 'your_tool_id',
        signalKService: signalKService,
        iconSize: 18,  // Slightly smaller for header rows
        iconColor: Colors.white,
      ),
    ),
  ],
),
```

## Tool Info YAML Configuration

Add your tool's info to `assets/tool_info.yaml`:

```yaml
tools:
  your_tool_id:
    name: "Your Tool Name"
    description: |
      Brief description of the tool.

      **Features:**
      - Feature 1
      - Feature 2
    required_plugins:
      - plugin-id-1
    optional_plugins:
      - plugin-id-2
    data_sources:
      - weatherflow  # External sources only (signalk is filtered out)
```

**Note:** The `signalk` data source is automatically filtered out in the dialog display since SignalK Server is implicit for all tools.

## Consistent Button Order

When multiple overlay buttons exist, use this order (left to right):

1. **Info button** (leftmost)
2. **Settings/config button** (if applicable)
3. **Refresh button** (rightmost)

## Reference Implementations

- **Charts**: `lib/widgets/tools/historical_chart_tool.dart` (lines 376-388)
- **Weather spinner**: `lib/widgets/tools/weather_api_spinner_tool.dart`
- **Anchor alarm**: `lib/widgets/tools/anchor_alarm_tool.dart`

## Checklist for New Tools

- [ ] Add `ToolInfoButton` with standard container styling
- [ ] Use `iconSize: 20` and `iconColor: Colors.white`
- [ ] Position at `top: 8, right: 8` using `Positioned`
- [ ] If grouping with other buttons, use `Row` with info button leftmost
- [ ] Add tool entry to `assets/tool_info.yaml`
- [ ] Don't list `signalk` in data_sources (filtered out automatically)
