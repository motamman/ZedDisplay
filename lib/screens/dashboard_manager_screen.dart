import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/dashboard_service.dart';
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

class _DashboardManagerScreenState extends State<DashboardManagerScreen> {
  late PageController _pageController;
  bool _isEditMode = false;
  bool _isFullScreen = false;
  bool _showAppBar = true;
  Timer? _appBarHideTimer;
  int _currentVirtualPage = 0; // Track virtual page for infinite scroll

  @override
  void initState() {
    super.initState();
    final dashboardService = Provider.of<DashboardService>(context, listen: false);
    final initialIndex = dashboardService.currentLayout?.activeScreenIndex ?? 0;

    // Start at a high offset to allow wrap-around in both directions
    _currentVirtualPage = 1000 + initialIndex;
    _pageController = PageController(
      initialPage: _currentVirtualPage,
    );
  }

  @override
  void dispose() {
    _appBarHideTimer?.cancel();
    _pageController.dispose();
    super.dispose();
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
    final layout = dashboardService.currentLayout;

    if (layout == null) return;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Select Screen',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: layout.screens.length,
                itemBuilder: (context, index) {
                  final screen = layout.screens[index];
                  final isActive = index == layout.activeScreenIndex;

                  return ListTile(
                    leading: Icon(
                      Icons.dashboard,
                      color: isActive ? Theme.of(context).colorScheme.primary : null,
                    ),
                    title: Text(
                      screen.name,
                      style: TextStyle(
                        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                        color: isActive ? Theme.of(context).colorScheme.primary : null,
                      ),
                    ),
                    trailing: isActive ? const Icon(Icons.check, color: Colors.green) : null,
                    onTap: () {
                      Navigator.pop(context);

                      // Calculate target virtual page
                      final totalScreens = layout.screens.length;
                      final currentActualIndex = _currentVirtualPage % totalScreens;

                      // Determine direction and distance
                      int targetVirtualPage;
                      if (index == currentActualIndex) {
                        targetVirtualPage = _currentVirtualPage;
                      } else {
                        // Move in the shortest direction
                        final forwardDist = (index - currentActualIndex + totalScreens) % totalScreens;
                        final backwardDist = (currentActualIndex - index + totalScreens) % totalScreens;

                        if (forwardDist <= backwardDist) {
                          targetVirtualPage = _currentVirtualPage + forwardDist;
                        } else {
                          targetVirtualPage = _currentVirtualPage - backwardDist;
                        }
                      }

                      _pageController.animateToPage(
                        targetVirtualPage,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
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

  void _showScreenManagementMenu() {
    final dashboardService = Provider.of<DashboardService>(context, listen: false);

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Add Screen'),
              onTap: () async {
                Navigator.pop(context);
                await dashboardService.addScreen();
                // Jump to the new screen using virtual page system
                final newIndex = dashboardService.currentLayout!.screens.length - 1;
                final totalScreens = dashboardService.currentLayout!.screens.length;
                final currentActualIndex = _currentVirtualPage % totalScreens;

                // Move forward to the new screen
                final targetVirtualPage = _currentVirtualPage + (newIndex - currentActualIndex);
                _pageController.animateToPage(
                  targetVirtualPage,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              },
            ),
            if (dashboardService.currentLayout!.screens.length > 1)
              ListTile(
                leading: const Icon(Icons.delete),
                title: const Text('Remove Current Screen'),
                onTap: () async {
                  Navigator.pop(context);
                  final activeScreen = dashboardService.currentLayout!.activeScreen;
                  if (activeScreen != null) {
                    await dashboardService.removeScreen(activeScreen.id);
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename Current Screen'),
              onTap: () async {
                Navigator.pop(context);
                final activeScreen = dashboardService.currentLayout!.activeScreen;
                if (activeScreen != null) {
                  _showRenameDialog(activeScreen.id, activeScreen.name);
                }
              },
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
        actions: [
          // Compact connection status indicator
          Consumer<SignalKService>(
            builder: (context, service, child) {
              return IconButton(
                icon: Icon(
                  service.isConnected ? Icons.cloud_done : Icons.cloud_off,
                  color: service.isConnected ? Colors.green : Colors.red,
                  size: 22,
                ),
                onPressed: () {
                  if (service.isConnected) {
                    // Show connection details on tap
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Connected to ${service.serverUrl}'),
                        duration: const Duration(seconds: 2),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } else {
                    // Navigate to settings to connect (with connections expanded)
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const SettingsScreen(
                          showConnections: true,
                        ),
                      ),
                    );
                  }
                },
                tooltip: service.isConnected ? 'Connected to ${service.serverUrl}' : 'Tap to connect',
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addTool,
            tooltip: 'Add Tool',
          ),
          IconButton(
            icon: Icon(_isEditMode ? Icons.done : Icons.edit),
            onPressed: () {
              setState(() => _isEditMode = !_isEditMode);
            },
            tooltip: _isEditMode ? 'Exit Edit Mode' : 'Edit Mode',
          ),
          IconButton(
            icon: const Icon(Icons.view_carousel),
            onPressed: _showScreenManagementMenu,
            tooltip: 'Manage Screens',
          ),
          // Theme mode toggle
          Consumer<StorageService>(
            builder: (context, storageService, child) {
              final themeMode = storageService.getThemeMode();
              final isDark = themeMode == 'dark';
              return IconButton(
                icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
                onPressed: () async {
                  final newMode = isDark ? 'light' : 'dark';
                  await storageService.saveThemeMode(newMode);
                },
                tooltip: isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
              );
            },
          ),
          // Fullscreen toggle
          IconButton(
            icon: Icon(_isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen),
            onPressed: _toggleFullScreen,
            tooltip: _isFullScreen ? 'Exit Full Screen' : 'Enter Full Screen',
          ),
          // Crew communications
          IconButton(
            icon: const Icon(Icons.group),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const CrewScreen(),
                ),
              );
            },
            tooltip: 'Crew',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
            },
            tooltip: 'Settings',
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

            return Stack(
            children: [
              // PageView with screens - full screen with wrap-around
              PageView.builder(
                controller: _pageController,
                physics: (_isEditMode || _toolBeingPlaced != null) ? const NeverScrollableScrollPhysics() : null, // Disable swipe in edit mode OR placement mode
                onPageChanged: (virtualIndex) {
                  final totalScreens = layout.screens.length;
                  if (totalScreens == 0) return;

                  // Calculate actual screen index from virtual index
                  final actualIndex = virtualIndex % totalScreens;
                  _currentVirtualPage = virtualIndex;
                  dashboardService.setActiveScreen(actualIndex);

                  // Show app bar temporarily when switching screens in fullscreen mode
                  _showAppBarTemporarily();
                },
                itemBuilder: (context, virtualIndex) {
                  final totalScreens = layout.screens.length;
                  if (totalScreens == 0) {
                    return const Center(child: Text('No screens available'));
                  }

                  // Map virtual index to actual screen index using modulo
                  final actualIndex = virtualIndex % totalScreens;
                  final screen = layout.screens[actualIndex];
                  return _buildScreenContent(screen, signalKService);
                },
              ),

              // Screen selector button (only show if multiple screens)
              if (layout.screens.length > 1)
                Positioned(
                  bottom: 16,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _showScreenSelector(context),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.dashboard,
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                layout.activeScreen?.name ?? 'Dashboard',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.arrow_drop_up,
                                color: Colors.white,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
          ),
        ),
      ),
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
