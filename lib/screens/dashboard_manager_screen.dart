import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/dashboard_service.dart';
import '../services/scale_service.dart';
import '../services/setup_service.dart';
import '../services/signalk_service.dart';
import '../services/storage_service.dart';
import '../services/tool_registry.dart';
import '../services/tool_service.dart';
import '../models/dashboard_screen.dart';
import '../models/tool.dart';
import '../models/tool_placement.dart';
import 'tool_config_screen.dart';
// Removed: template_library_screen import (deprecated)
import 'settings_screen.dart';
import 'crew/crew_screen.dart';
import '../widgets/crew/incoming_call_overlay.dart';

/// Main dashboard screen with multi-screen support using PageView
class DashboardManagerScreen extends StatefulWidget {
  const DashboardManagerScreen({super.key});

  @override
  State<DashboardManagerScreen> createState() => _DashboardManagerScreenState();
}

class _DashboardManagerScreenState extends State<DashboardManagerScreen>
    with WidgetsBindingObserver {
  // PageController for screen transitions with wrap-around
  late PageController _pageController;
  static const int _virtualPageOffset = 10000;
  bool _pageControllerInitialized = false;
  bool _isSwipeInProgress = false;  // Prevents listener feedback loop

  // Track screen count to detect add/remove
  int _lastScreenCount = 0;

  // Screen selector auto-hide
  bool _showScreenSelectorDots = true;
  Timer? _selectorHideTimer;

  // Height reserved at bottom for screen selector dots
  static const double _selectorHeight = 50.0;

  bool _isEditMode = false;
  bool _isFullScreen = false;
  bool _showAppBar = true;
  Timer? _appBarHideTimer;

  @override
  void initState() {
    super.initState();

    // Register for app lifecycle events
    WidgetsBinding.instance.addObserver(this);

    // Start screen selector auto-hide timer
    _startSelectorHideTimer();

    // Initialize PageController after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final dashboardService = Provider.of<DashboardService>(context, listen: false);
      _initializePageController(dashboardService);
    });
  }

  /// Initialize PageController for smooth screen transitions
  void _initializePageController(DashboardService dashboardService) {
    if (_pageControllerInitialized) return;

    final layout = dashboardService.currentLayout;
    final screenCount = layout?.screens.length ?? 1;

    // Determine initial screen index:
    // 1. If startupScreenId is set, use that screen
    // 2. Otherwise, use activeScreenIndex (last viewed)
    final storageService = Provider.of<StorageService>(context, listen: false);
    final startupScreenId = storageService.startupScreenId;
    int initialIndex;

    if (startupScreenId != null && layout != null) {
      // Find the index of the startup screen
      final startupIndex = layout.screens.indexWhere((s) => s.id == startupScreenId);
      initialIndex = startupIndex >= 0 ? startupIndex : (layout.activeScreenIndex);
    } else {
      initialIndex = layout?.activeScreenIndex ?? 0;
    }

    final initialPage = _virtualPageOffset * screenCount + initialIndex;

    _pageController = PageController(initialPage: initialPage);
    _pageControllerInitialized = true;
    _lastScreenCount = screenCount;

    // Listen for programmatic screen changes (e.g., from screen selector)
    dashboardService.addListener(_onDashboardServiceChanged);

    // Trigger a rebuild now that PageController is ready
    if (mounted) setState(() {});
  }

  /// Handle programmatic screen changes (e.g., from screen selector bottom sheet)
  void _onDashboardServiceChanged() {
    if (!_pageControllerInitialized || !mounted) return;

    // Skip if this change came from a swipe (already handled by PageView)
    if (_isSwipeInProgress) {
      _isSwipeInProgress = false;
      return;
    }

    final dashboardService = Provider.of<DashboardService>(context, listen: false);
    final layout = dashboardService.currentLayout;
    if (layout == null || !_pageController.hasClients) return;

    final targetIndex = layout.activeScreenIndex;
    final screenCount = layout.screens.length;
    if (screenCount == 0) return;

    // Handle screen count change (add/remove) - jump to correct position
    if (screenCount != _lastScreenCount) {
      _lastScreenCount = screenCount;
      final newVirtualPage = _virtualPageOffset * screenCount + targetIndex;
      _pageController.jumpToPage(newVirtualPage);
      return;
    }

    final currentPage = _pageController.page?.round() ?? 0;
    final currentActualIndex = currentPage % screenCount;

    // Only animate if we're on a different screen
    if (currentActualIndex != targetIndex) {
      // Calculate nearest virtual page (shortest path for wrap-around)
      final baseVirtual = (currentPage ~/ screenCount) * screenCount;
      int targetPage = baseVirtual + targetIndex;

      // Choose shortest path for wrap-around
      final diff = targetIndex - currentActualIndex;
      if (diff.abs() > screenCount / 2) {
        targetPage += (diff > 0) ? -screenCount : screenCount;
      }

      _pageController.animateToPage(
        targetPage,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    _appBarHideTimer?.cancel();
    _selectorHideTimer?.cancel();

    // Cleanup PageController
    if (_pageControllerInitialized) {
      _pageController.dispose();
      // Remove listener from dashboard service
      try {
        final dashboardService = Provider.of<DashboardService>(context, listen: false);
        dashboardService.removeListener(_onDashboardServiceChanged);
      } catch (_) {
        // Context may not be available during dispose
      }
    }

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Show screen selector when app resumes from background
    if (state == AppLifecycleState.resumed) {
      _revealSelectorDots();
    }
  }

  /// Reveal the screen selector dots and restart the hide timer
  void _revealSelectorDots() {
    setState(() => _showScreenSelectorDots = true);
    _startSelectorHideTimer();
  }

  /// Start the auto-hide timer for screen selector dots
  void _startSelectorHideTimer() {
    _selectorHideTimer?.cancel();
    _selectorHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _showScreenSelectorDots = false);
      }
    });
  }

  void _startAppBarHideTimer() {
    _appBarHideTimer?.cancel();
    if (_isFullScreen) {
      _appBarHideTimer = Timer(const Duration(seconds: 5), () {
        if (mounted && _isFullScreen) {
          setState(() {
            _showAppBar = false;
          });
        }
      });
    }
  }

  void _showAppBarTemporarily() {
    if (_isFullScreen) {
      setState(() {
        _showAppBar = true;
      });
      _startAppBarHideTimer();
    }
  }

  Future<void> _addTool() async {
    print('🔧 _addTool: START');

    // Prevent opening tool config if already in placement mode
    if (_toolBeingPlaced != null) {
      print('⚠️ _addTool: Already in placement mode, ignoring');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please place the current tool first!'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final dashboardService = Provider.of<DashboardService>(context, listen: false);
    final toolService = Provider.of<ToolService>(context, listen: false);
    final activeScreen = dashboardService.currentLayout?.activeScreen;

    if (activeScreen == null) {
      print('❌ _addTool: No active screen');
      return;
    }

    print('🔧 _addTool: Opening ToolConfigScreen for screen ${activeScreen.id}');

    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ToolConfigScreen(screenId: activeScreen.id),
      ),
    );

    print('🔧 _addTool: Got result: ${result.runtimeType}');
    print('🔧 _addTool: Result content: $result');
    print('🔧 _addTool: mounted = $mounted');

    if (result is Map<String, dynamic> && mounted) {
      print('🔧 _addTool: Result is Map and mounted, processing...');
      try {
        final tool = result['tool'] as Tool;
        final width = result['width'] as int? ?? 1;
        final height = result['height'] as int? ?? 1;

        print('🔧 _addTool: Tool=${tool.id}, width=$width, height=$height');

        // Create a placement for this tool with size (starting at center)
        final placement = toolService.createPlacement(
          toolId: tool.id,
          screenId: activeScreen.id,
          width: width,
          height: height,
        );

        print('🔧 _addTool: Entering placement mode for drag-to-position');

        // Enter placement mode - user will drag to position
        setState(() {
          _toolBeingPlaced = tool;
          _placementBeingPlaced = placement;
          _placingX = 0; // Start at 0,0
          _placingY = 0;
          _placingWidth = width * 100.0; // Initial pixel width (approximate)
          _placingHeight = height * 100.0; // Initial pixel height (approximate)
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Drag to position • Drag corner to resize • Release to place'),
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 4),
            ),
          );
        }

        print('✅ _addTool: Entered placement mode successfully');
      } catch (e, stack) {
        print('❌ _addTool: Error: $e');
        print('❌ _addTool: Stack trace: $stack');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error adding tool: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else {
      print('❌ _addTool: Result is NOT Map or not mounted');
    }
  }

  // Removed: _browseTemplates() and _showAddMenu() - deprecated
  // "+" button now goes directly to tool configuration

  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
      if (_isFullScreen) {
        // Enter full-screen mode (hide system UI)
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.immersiveSticky,
          overlays: [],
        );
        _showAppBar = true;
        _startAppBarHideTimer();
      } else {
        // Exit full-screen mode (show system UI)
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: SystemUiOverlay.values,
        );
        _appBarHideTimer?.cancel();
        _showAppBar = true;
      }
    });
  }

  void _showScreenSelector(BuildContext context) {
    final dashboardService = Provider.of<DashboardService>(context, listen: false);
    final storageService = Provider.of<StorageService>(context, listen: false);

    if (dashboardService.currentLayout == null) return;

    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          // Read layout inside builder so it updates after reorder
          final layout = dashboardService.currentLayout!;
          final startupScreenId = storageService.startupScreenId;

          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Screens',
                        style: Theme.of(sheetContext).textTheme.titleLarge,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Flexible(
                  child: ReorderableListView.builder(
                    shrinkWrap: true,
                    buildDefaultDragHandles: false,
                    itemCount: layout.screens.length,
                    proxyDecorator: (child, index, animation) {
                      return AnimatedBuilder(
                        animation: animation,
                        builder: (context, child) {
                          final double elevation = Tween<double>(begin: 0, end: 6)
                              .animate(animation).value;
                          return Material(
                            elevation: elevation,
                            shadowColor: Colors.black54,
                            child: child,
                          );
                        },
                        child: child,
                      );
                    },
                    onReorder: (oldIndex, newIndex) {
                      // ReorderableListView gives newIndex as position before removal
                      if (newIndex > oldIndex) {
                        newIndex -= 1;
                      }
                      dashboardService.reorderScreens(oldIndex, newIndex);
                      setSheetState(() {}); // Refresh bottom sheet UI
                    },
                    itemBuilder: (sheetContext, index) {
                      final screen = layout.screens[index];
                      final isActive = index == layout.activeScreenIndex;
                      final isStartupScreen = screen.id == startupScreenId;

                      return ListTile(
                        key: ValueKey(screen.id),
                        leading: Icon(
                          Icons.dashboard,
                          color: isActive ? Theme.of(sheetContext).colorScheme.primary : null,
                        ),
                        title: Text(
                          screen.name,
                          style: TextStyle(
                            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                            color: isActive ? Theme.of(sheetContext).colorScheme.primary : null,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Startup screen toggle
                            IconButton(
                              icon: Icon(
                                isStartupScreen ? Icons.home : Icons.home_outlined,
                                color: isStartupScreen ? Colors.orange : Colors.grey,
                              ),
                              onPressed: () async {
                                // Toggle: if already startup, clear it; otherwise set it
                                final newId = isStartupScreen ? null : screen.id;
                                await storageService.setStartupScreenId(newId);
                                setSheetState(() {}); // Rebuild bottom sheet
                              },
                              tooltip: isStartupScreen ? 'Clear startup screen' : 'Set as startup screen',
                              visualDensity: VisualDensity.compact,
                            ),
                            // Active screen indicator
                            if (isActive)
                              const Icon(Icons.check, color: Colors.green),
                            // Drag handle for reordering
                            ReorderableDragStartListener(
                              index: index,
                              child: const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: Icon(Icons.drag_indicator, color: Colors.grey),
                              ),
                            ),
                          ],
                        ),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          dashboardService.setActiveScreen(index);
                        },
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                // Screen management actions
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _showAddScreenDialog();
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add'),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          final activeScreen = dashboardService.currentLayout?.activeScreen;
                          if (activeScreen != null) {
                            _showRenameDialog(activeScreen.id, activeScreen.name);
                          }
                        },
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Rename'),
                      ),
                      if (layout.screens.length > 1)
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            final activeScreen = dashboardService.currentLayout?.activeScreen;
                            if (activeScreen != null) {
                              _confirmRemoveScreen(activeScreen.id, activeScreen.name);
                            }
                          },
                          icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                          label: const Text('Delete', style: TextStyle(color: Colors.red)),
                        ),
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _showIntendedUseDialog();
                        },
                        icon: const Icon(Icons.devices, size: 18),
                        label: const Text('Device'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showAddScreenDialog() async {
    final nameController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Screen'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Screen Name',
            hintText: 'e.g., Navigation, Engine, Weather',
          ),
          autofocus: true,
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(context, name);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result != null && mounted) {
      final dashboardService = Provider.of<DashboardService>(context, listen: false);
      await dashboardService.addScreen(name: result);

      // Jump to new screen
      final newIndex = dashboardService.currentLayout!.screens.length - 1;
      dashboardService.setActiveScreen(newIndex);
    }
  }

  void _confirmRemoveScreen(String screenId, String screenName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Screen?'),
        content: Text('Are you sure you want to delete "$screenName"? This will remove all tools on this screen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final dashboardService = Provider.of<DashboardService>(context, listen: false);
      await dashboardService.removeScreen(screenId);
    }
  }

  Future<void> _editTool(Tool tool, String placementToolId) async {
    final dashboardService = Provider.of<DashboardService>(context, listen: false);
    final activeScreen = dashboardService.currentLayout?.activeScreen;

    if (activeScreen == null) return;

    // Find the current placement to get size (check both orientations)
    final orientation = MediaQuery.of(context).orientation;
    final placements = orientation == Orientation.portrait
        ? activeScreen.portraitPlacements
        : activeScreen.landscapePlacements;

    final currentPlacement = placements.firstWhere(
      (p) => p.toolId == placementToolId,
    );

    // Open the tool configuration screen with the existing tool
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ToolConfigScreen(
          existingTool: tool,
          screenId: activeScreen.id,
          existingWidth: currentPlacement.position.width,
          existingHeight: currentPlacement.position.height,
        ),
      ),
    );

    if (result is Map<String, dynamic> && mounted) {
      final updatedTool = result['tool'] as Tool;
      final newWidth = result['width'] as int? ?? 1;
      final newHeight = result['height'] as int? ?? 1;

      // Update the placement size if it changed
      if (newWidth != currentPlacement.position.width ||
          newHeight != currentPlacement.position.height) {
        await dashboardService.updatePlacementSize(
          activeScreen.id,
          placementToolId,
          newWidth,
          newHeight,
        );
      } else {
        // Even if size didn't change, save the dashboard to persist any updates
        await dashboardService.saveDashboard();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tool "${updatedTool.name}" updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  void _removePlacement(String screenId, String toolId) async {
    final dashboardService = Provider.of<DashboardService>(context, listen: false);
    await dashboardService.removePlacement(screenId, toolId);
  }

  void _confirmRemovePlacement(String screenId, String toolId, String toolName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Tool'),
        content: Text('Are you sure you want to remove "$toolName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _removePlacement(screenId, toolId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _showIntendedUseDialog() {
    final dashboardService = Provider.of<DashboardService>(context, listen: false);
    final currentUse = dashboardService.currentLayout?.intendedUse;

    const presets = ['Phone', 'Tablet', 'Desktop'];
    final isCustom = currentUse != null && !presets.contains(currentUse);

    String? selectedValue = isCustom ? 'Custom' : currentUse;
    final customController = TextEditingController(text: isCustom ? currentUse : '');

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Intended Use'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Select the intended device type for this dashboard layout.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              RadioGroup<String?>(
                groupValue: selectedValue,
                onChanged: (value) {
                  setState(() => selectedValue = value);
                },
                child: Column(
                  children: [
                    ...presets.map((preset) => RadioListTile<String?>(
                      title: Text(preset),
                      value: preset,
                    )),
                    const RadioListTile<String?>(
                      title: Text('Custom'),
                      value: 'Custom',
                    ),
                    const RadioListTile<String?>(
                      title: Text('None'),
                      subtitle: Text('Clear intended use'),
                      value: null,
                    ),
                  ],
                ),
              ),
              if (selectedValue == 'Custom')
                Padding(
                  padding: const EdgeInsets.only(left: 16, right: 16, top: 8),
                  child: TextField(
                    controller: customController,
                    decoration: const InputDecoration(
                      labelText: 'Custom name',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    autofocus: true,
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                // Get services before any await to avoid async context issues
                final setupService = Provider.of<SetupService>(context, listen: false);
                final navigator = Navigator.of(context);

                String? newValue;
                if (selectedValue == 'Custom') {
                  newValue = customController.text.trim();
                  if (newValue.isEmpty) newValue = null;
                } else {
                  newValue = selectedValue;
                }

                final currentLayout = dashboardService.currentLayout;
                if (currentLayout != null) {
                  final updatedLayout = currentLayout.copyWith(
                    intendedUse: newValue,
                    clearIntendedUse: newValue == null,
                  );
                  await dashboardService.updateLayout(updatedLayout);

                  // Also sync to saved setup if it exists
                  if (setupService.setupExists(currentLayout.id)) {
                    await setupService.updateSetupIntendedUse(currentLayout.id, newValue);
                  }
                }

                if (context.mounted) {
                  navigator.pop();
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(String screenId, String currentName) {
    final controller = TextEditingController(text: currentName);
    final dashboardService = Provider.of<DashboardService>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Screen'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Screen Name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                await dashboardService.renameScreen(screenId, newName);
                if (context.mounted) {
                  Navigator.pop(context);
                }
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  /// Get display name from saved connection (falls back to hostname)
  String _getServerDisplayName(String? serverUrl, StorageService storageService) {
    if (serverUrl == null || serverUrl.isEmpty) return 'Not Connected';

    // Look up the saved connection by URL to get its name
    final connection = storageService.findConnectionByUrl(serverUrl);
    if (connection != null && connection.name.isNotEmpty) {
      return connection.name;
    }

    // Fallback to hostname if no saved connection found
    try {
      final uri = Uri.parse(serverUrl);
      return uri.host.isNotEmpty ? uri.host : 'Server';
    } catch (_) {
      return 'Server';
    }
  }

  /// Handle menu item selection
  void _handleMenuSelection(String value, StorageService storageService) {
    switch (value) {
      case 'addTool':
        _addTool();
        break;
      case 'editMode':
        setState(() => _isEditMode = !_isEditMode);
        break;
      case 'theme':
        final isDark = storageService.getThemeMode() == 'dark';
        storageService.saveThemeMode(isDark ? 'light' : 'dark');
        break;
      case 'fullscreen':
        _toggleFullScreen();
        break;
      case 'crew':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CrewScreen()),
        );
        break;
      case 'settings':
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
        break;
    }
  }

  /// Build a menu item with icon and label (OpenMeteo pattern)
  PopupMenuItem<String> _buildMenuItem(
    MenuItemDefinition? menuItem,
    String fallbackId, {
    bool isActive = false,
    IconData? customIcon,
    String? customLabel,
  }) {
    final icon = customIcon ?? menuItem?.iconData ?? Icons.help_outline;
    final label = customLabel ?? menuItem?.label ?? fallbackId;

    return PopupMenuItem<String>(
      value: fallbackId,
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: isActive ? Colors.green : null,
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive ? Colors.green : null,
            ),
          ),
          if (isActive) ...[
            const Spacer(),
            const Icon(Icons.check, size: 16, color: Colors.green),
          ],
        ],
      ),
    );
  }

  /// Show server picker bottom sheet (equivalent to OpenMeteo's location picker)
  void _showServerPicker(BuildContext context, SignalKService signalKService) {
    final storageService = Provider.of<StorageService>(context, listen: false);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => _ServerPickerSheet(
        signalKService: signalKService,
        storageService: storageService,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IncomingCallOverlay(
      child: Scaffold(
        extendBody: _isFullScreen,
        extendBodyBehindAppBar: _isFullScreen,
      floatingActionButton: (_isFullScreen && !_showAppBar && _toolBeingPlaced == null)
          ? FloatingActionButton.small(
              onPressed: _showAppBarTemporarily,
              backgroundColor: Colors.black.withValues(alpha: 0.6),
              child: const Icon(Icons.arrow_upward, color: Colors.white),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
      appBar: (!_isFullScreen || _showAppBar || _toolBeingPlaced != null) ? AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 8,
        title: Consumer2<SignalKService, StorageService>(
          builder: (context, signalKService, storageService, child) {
            return Row(
              children: [
                // Connection indicator (compact)
                Icon(
                  signalKService.isConnected ? Icons.cloud_done : Icons.cloud_off,
                  color: signalKService.isConnected ? Colors.green : Colors.red,
                  size: 18,
                ),
                const SizedBox(width: 8),
                // Server name (tappable to show server picker)
                Flexible(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _showServerPicker(context, signalKService),
                    child: Text(
                      signalKService.isConnected
                          ? _getServerDisplayName(signalKService.serverUrl, storageService)
                          : 'Not Connected',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        actions: [
          // Edit mode indicator when active
          if (_isEditMode)
            IconButton(
              icon: const Icon(Icons.done, color: Colors.green),
              onPressed: () => setState(() => _isEditMode = false),
              tooltip: 'Exit Edit Mode',
            ),
          // Main menu dropdown (hamburger)
          Consumer<StorageService>(
            builder: (context, storageService, child) {
              final isDark = storageService.getThemeMode() == 'dark';
              return PopupMenuButton<String>(
                icon: const Icon(Icons.menu),
                tooltip: 'Menu',
                onSelected: (value) => _handleMenuSelection(value, storageService),
                itemBuilder: (context) {
                  final scaleService = ScaleService.instance;
                  return [
                    _buildMenuItem(scaleService.getMenuItem('addTool'), 'addTool'),
                    _buildMenuItem(scaleService.getMenuItem('editMode'), 'editMode',
                        isActive: _isEditMode),
                    _buildMenuItem(
                      scaleService.getMenuItem('theme'),
                      'theme',
                      customIcon: isDark ? Icons.light_mode : Icons.dark_mode,
                      customLabel: isDark ? 'Light Mode' : 'Dark Mode',
                    ),
                    _buildMenuItem(scaleService.getMenuItem('fullscreen'), 'fullscreen',
                        isActive: _isFullScreen),
                    _buildMenuItem(scaleService.getMenuItem('crew'), 'crew'),
                    _buildMenuItem(scaleService.getMenuItem('settings'), 'settings'),
                  ];
                },
              );
            },
          ),
        ],
      ) : null,
      body: SafeArea(
        top: !_isFullScreen,
        bottom: !_isFullScreen,
        left: !_isFullScreen,
        right: !_isFullScreen,
        child: Consumer2<DashboardService, SignalKService>(
          builder: (context, dashboardService, signalKService, child) {
            if (!dashboardService.initialized) {
              return const Center(child: CircularProgressIndicator());
            }

            final layout = dashboardService.currentLayout;
            if (layout == null || layout.screens.isEmpty) {
              return const Center(
                child: Text('No dashboard screens available'),
              );
            }

            if (!signalKService.isConnected) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      'Not connected to SignalK server',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const SettingsScreen(
                              showConnections: true,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.settings),
                      label: const Text('Connection Settings'),
                    ),
                  ],
                ),
              );
            }

            // Build dashboard with PageView navigation
            return _buildDashboard(layout, dashboardService, signalKService);
        },
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard(dynamic layout, DashboardService dashboardService, SignalKService signalKService) {
    if (layout.screens.isEmpty) {
      return const Center(child: Text('No screens available'));
    }

    final int screenCount = layout.screens.length;

    // Disable swipe in edit mode, placement mode, or single screen
    final disableSwipe = _isEditMode || _toolBeingPlaced != null || screenCount <= 1;

    // Ensure PageController is initialized before building
    if (!_pageControllerInitialized) {
      _initializePageController(dashboardService);
      // Return loading indicator while initializing
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      children: [
        // PageView for smooth slide transitions with live drag preview
        PageView.builder(
          controller: _pageController,
          physics: disableSwipe
              ? const NeverScrollableScrollPhysics()
              : const BouncingScrollPhysics(),
          onPageChanged: (virtualPage) {
            // Convert virtual page to actual index (wrap-around)
            final int actualIndex = virtualPage % screenCount;

            // Only update service if index actually changed
            if (actualIndex != layout.activeScreenIndex) {
              // Mark as swipe to prevent listener feedback loop
              _isSwipeInProgress = true;
              dashboardService.setActiveScreen(actualIndex);
              _showAppBarTemporarily();
              _revealSelectorDots();
            }
          },
          itemBuilder: (context, virtualPage) {
            // Convert virtual page to actual screen index (wrap-around)
            final int actualIndex = virtualPage % screenCount;
            final screen = layout.screens[actualIndex];
            return _buildScreenContent(screen, signalKService);
          },
          // No itemCount = infinite scrolling for wrap-around
        ),

        // Screen indicator dots at bottom (only if multiple screens)
        // Auto-hides after 4 seconds, tap bottom zone to reveal
        if (layout.screens.length > 1)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                if (!_showScreenSelectorDots) {
                  _revealSelectorDots();
                }
              },
              child: Container(
                height: _selectorHeight, // Tap zone height for revealing hidden dots
                alignment: Alignment.topCenter,
                padding: const EdgeInsets.only(top: 10),
                child: AnimatedOpacity(
                  opacity: _showScreenSelectorDots ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: IgnorePointer(
                    ignoring: !_showScreenSelectorDots,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          _revealSelectorDots(); // Reset timer on interaction
                          _showScreenSelector(context);
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(layout.screens.length, (index) {
                              final isActive = index == layout.activeScreenIndex;
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isActive
                                        ? Colors.grey.shade800
                                        : Colors.grey.shade400,
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // Track widget being resized
  String? _resizingWidgetId;
  double _resizingWidth = 0;
  double _resizingHeight = 0;

  // Track widget being moved
  String? _movingWidgetId;
  double _movingX = 0;
  double _movingY = 0;

  // Track tool being placed (drag-to-place for new tools)
  Tool? _toolBeingPlaced;
  ToolPlacement? _placementBeingPlaced;
  double _placingX = 0;
  double _placingY = 0;
  double _placingWidth = 0;
  double _placingHeight = 0;

  Widget _buildScreenContent(DashboardScreen screen, SignalKService signalKService) {
    final toolService = Provider.of<ToolService>(context, listen: false);
    final orientation = MediaQuery.of(context).orientation;
    final placements = orientation == Orientation.portrait
        ? screen.portraitPlacements
        : screen.landscapePlacements;

    // IMPORTANT: Don't return early if screen is empty - we need to check for placement overlay!
    Widget emptyScreenWidget = Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.dashboard_customize, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No tools on "${screen.name}"',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _addTool,
            icon: const Icon(Icons.add),
            label: const Text('Add Your First Tool'),
          ),
        ],
      ),
    );

    // If empty AND no placement overlay, just return the empty screen widget
    if (placements.isEmpty && _toolBeingPlaced == null) {
      return emptyScreenWidget;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Get orientation and choose appropriate placements
        final orientation = MediaQuery.of(context).orientation;
        final placements = orientation == Orientation.portrait
            ? screen.portraitPlacements
            : screen.landscapePlacements;

        // Determine if we should allow scrolling
        final useScrolling = screen.allowOverflow;

        // Build the content widget - use empty screen if no placements
        Widget contentWidget = placements.isEmpty
            ? emptyScreenWidget
            : Stack(
          children: placements.map((placement) {
            final tool = toolService.getTool(placement.toolId);

            if (tool == null) {
              return const SizedBox.shrink();
            }

            final registry = ToolRegistry();

            // Get position from placement - TEMPORARY: convert grid to pixels
            // TODO: Update placements to use PixelPosition instead of GridPosition
            final screenWidth = constraints.maxWidth;
            final screenHeight = constraints.maxHeight;
            final cellWidth = screenWidth / 8;
            final cellHeight = screenHeight / 8;

            // Use moving position if this widget is being moved, otherwise use placement position
            final isBeingMoved = _movingWidgetId == placement.toolId;
            final x = isBeingMoved ? _movingX : placement.position.col * cellWidth;
            final y = isBeingMoved ? _movingY : placement.position.row * cellHeight;

            // Use resizing dimensions if this widget is being resized, otherwise use placement dimensions
            final isBeingResized = _resizingWidgetId == placement.toolId;
            final width = isBeingResized ? _resizingWidth : placement.position.width * cellWidth;
            final height = isBeingResized ? _resizingHeight : placement.position.height * cellHeight;

            // Build the widget content
            Widget widgetContent;

            if (_isEditMode) {
              // In edit mode, show controls
              widgetContent = Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Tool widget
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: registry.buildTool(
                                tool.toolTypeId,
                                tool.config,
                                signalKService,
                              ),
                            ),

                            // Edit mode buttons
                            // Edit button at top-right
                            Positioned(
                              top: 4,
                              right: 4,
                              child: IconButton(
                                icon: const Icon(Icons.edit, size: 16),
                                onPressed: () => _editTool(tool, placement.toolId),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.blue.withValues(alpha: 0.7),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.all(4),
                                  minimumSize: const Size(24, 24),
                                ),
                                tooltip: 'Edit Tool',
                              ),
                            ),
                            // Drag-to-move handle at top-left
                            Positioned(
                              top: 4,
                              left: 4,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanStart: (details) {
                                  // Start moving
                                  setState(() {
                                    _movingWidgetId = placement.toolId;
                                    _movingX = x;
                                    _movingY = y;
                                  });
                                },
                                onPanUpdate: (details) {
                                  // Update position in real-time
                                  setState(() {
                                    _movingX = (_movingX + details.delta.dx).clamp(0, screenWidth - width);
                                    _movingY = (_movingY + details.delta.dy).clamp(0, screenHeight - height);
                                  });
                                },
                                onPanEnd: (details) {
                                  // Save final position
                                  final dashboardService = Provider.of<DashboardService>(context, listen: false);

                                  final updatedPlacement = placement.copyWith(
                                    position: placement.position.copyWith(
                                      col: (_movingX / cellWidth).round(),
                                      row: (_movingY / cellHeight).round(),
                                    ),
                                  );

                                  final isPortrait = orientation == Orientation.portrait;
                                  final updatedScreen = isPortrait
                                      ? screen.copyWith(
                                          portraitPlacements: screen.portraitPlacements
                                              .map((p) => p.toolId == updatedPlacement.toolId ? updatedPlacement : p)
                                              .toList(),
                                        )
                                      : screen.copyWith(
                                          landscapePlacements: screen.landscapePlacements
                                              .map((p) => p.toolId == updatedPlacement.toolId ? updatedPlacement : p)
                                              .toList(),
                                        );

                                  dashboardService.updateScreen(updatedScreen);

                                  // Clear moving state
                                  setState(() {
                                    _movingWidgetId = null;
                                  });
                                },
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: Colors.purple.withValues(alpha: 0.8),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: const Icon(
                                    Icons.open_with,
                                    size: 20,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),

                            // Delete button at bottom-left
                            Positioned(
                              bottom: 4,
                              left: 4,
                              child: IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () => _confirmRemovePlacement(screen.id, placement.toolId, tool.name),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.red.withValues(alpha: 0.7),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.all(4),
                                  minimumSize: const Size(24, 24),
                                ),
                                tooltip: 'Remove',
                              ),
                            ),

                            // Resize handle at bottom-right corner (larger hit area)
                            Positioned(
                              bottom: -4,
                              right: -4,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanStart: (details) {
                                  // Start resizing
                                  setState(() {
                                    _resizingWidgetId = placement.toolId;
                                    _resizingWidth = width;
                                    _resizingHeight = height;
                                  });
                                },
                                onPanUpdate: (details) {
                                  // Update widget size based on drag in real-time
                                  setState(() {
                                    _resizingWidth = (_resizingWidth + details.delta.dx).clamp(100.0, screenWidth - x);
                                    _resizingHeight = (_resizingHeight + details.delta.dy).clamp(100.0, screenHeight - y);
                                  });
                                },
                                onPanEnd: (details) {
                                  // Save final size to placement
                                  final updatedPlacement = placement.copyWith(
                                    position: placement.position.copyWith(
                                      width: (_resizingWidth / cellWidth).round(),
                                      height: (_resizingHeight / cellHeight).round(),
                                    ),
                                  );

                                  // Save to dashboard - ONLY update the current orientation
                                  final dashboardService = Provider.of<DashboardService>(context, listen: false);
                                  final isPortrait = orientation == Orientation.portrait;

                                  // Update the screen with the new placement in the current orientation only
                                  final updatedScreen = isPortrait
                                      ? screen.copyWith(
                                          portraitPlacements: screen.portraitPlacements
                                              .map((p) => p.toolId == updatedPlacement.toolId ? updatedPlacement : p)
                                              .toList(),
                                        )
                                      : screen.copyWith(
                                          landscapePlacements: screen.landscapePlacements
                                              .map((p) => p.toolId == updatedPlacement.toolId ? updatedPlacement : p)
                                              .toList(),
                                        );

                                  dashboardService.updateScreen(updatedScreen);

                                  // Clear resizing state
                                  setState(() {
                                    _resizingWidgetId = null;
                                  });
                                },
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.8),
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(8),
                                    ),
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: const Icon(
                                    Icons.zoom_out_map,
                                    size: 24,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
            } else {
              // Normal mode - just show the tool
              widgetContent = Padding(
                padding: const EdgeInsets.all(8),
                child: registry.buildTool(
                  tool.toolTypeId,
                  tool.config,
                  signalKService,
                ),
              );
            }

            // Return positioned widget with exact pixel positioning
            return Positioned(
              left: x,
              top: y,
              width: width,
              height: height,
              child: widgetContent,
            );
          }).toList(),
        );

        // Add overlay for tool being placed (if any)
        if (_toolBeingPlaced != null && _placementBeingPlaced != null) {
          final screenWidth = constraints.maxWidth;
          final screenHeight = constraints.maxHeight;

          contentWidget = Stack(
            children: [
              contentWidget,
              // Draggable overlay for new tool
              Positioned(
                left: _placingX,
                top: _placingY,
                width: _placingWidth,
                height: _placingHeight,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      // Ensure max is always >= 0 to avoid clamp error
                      final maxX = (screenWidth - _placingWidth).clamp(0.0, double.infinity);
                      final maxY = (screenHeight - _placingHeight).clamp(0.0, double.infinity);
                      _placingX = (_placingX + details.delta.dx).clamp(0, maxX);
                      _placingY = (_placingY + details.delta.dy).clamp(0, maxY);
                    });
                  },
                  onPanEnd: (details) async {
                    // Save the tool at this position
                    final dashboardService = Provider.of<DashboardService>(context, listen: false);
                    final messenger = ScaffoldMessenger.of(context);
                    final cellWidth = screenWidth / 8;
                    final cellHeight = screenHeight / 8;

                    // Convert pixel position and size to grid position
                    final updatedPlacement = _placementBeingPlaced!.copyWith(
                      position: _placementBeingPlaced!.position.copyWith(
                        col: (_placingX / cellWidth).round(),
                        row: (_placingY / cellHeight).round(),
                        width: (_placingWidth / cellWidth).round().clamp(1, 8),
                        height: (_placingHeight / cellHeight).round().clamp(1, 8),
                      ),
                    );

                    // Add to BOTH orientations so tool appears in portrait AND landscape
                    final updatedScreen = screen.addPlacement(updatedPlacement);

                    await dashboardService.updateScreen(updatedScreen);

                    // Show success message before clearing state
                    final toolName = _toolBeingPlaced!.name;

                    // Clear placing state
                    setState(() {
                      _toolBeingPlaced = null;
                      _placementBeingPlaced = null;
                    });

                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('Tool "$toolName" placed'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                  child: Opacity(
                    opacity: 0.7,
                    child: Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.yellow, width: 6),
                            borderRadius: BorderRadius.circular(12),
                            color: Colors.yellow.withValues(alpha: 0.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.5),
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.pan_tool, size: 64, color: Colors.orange[900]),
                                const SizedBox(height: 16),
                                Text(
                                  _toolBeingPlaced!.name,
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 24,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'DRAG ME TO POSITION',
                                  style: TextStyle(
                                    color: Colors.red[900],
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Drag corner to resize • Release to place',
                                  style: TextStyle(
                                    color: Colors.black87,
                                    fontSize: 14,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Resize handle for placement
                        Positioned(
                          bottom: -4,
                          right: -4,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanUpdate: (details) {
                              setState(() {
                                _placingWidth = (_placingWidth + details.delta.dx).clamp(100.0, screenWidth - _placingX);
                                _placingHeight = (_placingHeight + details.delta.dy).clamp(100.0, screenHeight - _placingY);
                              });
                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.8),
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(8),
                                ),
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(
                                Icons.zoom_out_map,
                                size: 24,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        // Wrap in scrollview if overflow is allowed
        if (useScrolling) {
          contentWidget = SingleChildScrollView(
            child: contentWidget,
          );
        }

        return contentWidget;
      },
    );
  }
}

/// Server picker bottom sheet (replicates OpenMeteo's _LocationPickerSheet)
class _ServerPickerSheet extends StatefulWidget {
  final SignalKService signalKService;
  final StorageService storageService;

  const _ServerPickerSheet({
    required this.signalKService,
    required this.storageService,
  });

  @override
  State<_ServerPickerSheet> createState() => _ServerPickerSheetState();
}

class _ServerPickerSheetState extends State<_ServerPickerSheet> {
  @override
  Widget build(BuildContext context) {
    final savedConnections = widget.storageService.getAllConnections();
    final currentUrl = widget.signalKService.serverUrl;

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.8,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  'Select Server',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Add Server button
          ListTile(
            leading: Icon(
              Icons.add_circle_outline,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(
              'Add Server',
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
            onTap: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SettingsScreen(showConnections: true),
                ),
              );
            },
          ),
          const Divider(height: 1),
          // Saved servers list
          Expanded(
            child: savedConnections.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.cloud_off,
                            size: 48,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No saved servers',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap "Add Server" to connect',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    itemCount: savedConnections.length,
                    itemBuilder: (context, index) {
                      final connection = savedConnections[index];
                      final isSelected = currentUrl == connection.serverUrl;

                      return ListTile(
                        leading: Icon(
                          isSelected ? Icons.cloud_done : Icons.cloud_outlined,
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        title: Text(
                          connection.name,
                          style: isSelected
                              ? TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.primary,
                                )
                              : null,
                        ),
                        subtitle: Text(
                          connection.serverUrl,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        trailing: isSelected
                            ? Icon(
                                Icons.check_circle,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : null,
                        onTap: () async {
                          Navigator.pop(context);
                          if (!isSelected) {
                            // Connect to selected server
                            await widget.signalKService.connect(
                              connection.serverUrl,
                              secure: connection.useSecure,
                            );
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
