import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../services/dashboard_service.dart';
import '../services/signalk_service.dart';
import '../services/storage_service.dart';
import '../services/tool_registry.dart';
import '../services/tool_service.dart';
import '../models/dashboard_screen.dart';
import '../models/tool.dart';
import 'tool_config_screen.dart';
import 'template_library_screen.dart';
import 'settings_screen.dart';

/// Main dashboard screen with multi-screen support using PageView
class DashboardManagerScreen extends StatefulWidget {
  const DashboardManagerScreen({super.key});

  @override
  State<DashboardManagerScreen> createState() => _DashboardManagerScreenState();
}

class _DashboardManagerScreenState extends State<DashboardManagerScreen> {
  late PageController _pageController;
  bool _isEditMode = false;

  @override
  void initState() {
    super.initState();
    final dashboardService = Provider.of<DashboardService>(context, listen: false);
    _pageController = PageController(
      initialPage: dashboardService.currentLayout?.activeScreenIndex ?? 0,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _addTool() async {
    final dashboardService = Provider.of<DashboardService>(context, listen: false);
    final toolService = Provider.of<ToolService>(context, listen: false);
    final activeScreen = dashboardService.currentLayout?.activeScreen;

    if (activeScreen == null) return;

    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ToolConfigScreen(screenId: activeScreen.id),
      ),
    );

    if (result is Map<String, dynamic>) {
      final tool = result['tool'] as Tool;
      final width = result['width'] as int? ?? 1;
      final height = result['height'] as int? ?? 1;

      // Create a placement for this tool with size
      final placement = toolService.createPlacement(
        toolId: tool.id,
        screenId: activeScreen.id,
        width: width,
        height: height,
      );
      await dashboardService.addPlacementToActiveScreen(placement);
    }
  }

  Future<void> _browseTemplates() async {
    final dashboardService = Provider.of<DashboardService>(context, listen: false);
    final toolService = Provider.of<ToolService>(context, listen: false);
    final activeScreen = dashboardService.currentLayout?.activeScreen;

    if (activeScreen == null) return;

    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const TemplateLibraryScreen(),
      ),
    );

    if (result is Map<String, dynamic>) {
      final tool = result['tool'] as Tool;
      final width = result['width'] as int? ?? 1;
      final height = result['height'] as int? ?? 1;

      // Create a placement for this tool with size
      final placement = toolService.createPlacement(
        toolId: tool.id,
        screenId: activeScreen.id,
        width: width,
        height: height,
      );
      await dashboardService.addPlacementToActiveScreen(placement);
    }
  }

  void _showAddMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('Create Tool'),
              subtitle: const Text('Configure a tool from scratch'),
              onTap: () {
                Navigator.pop(context);
                _addTool();
              },
            ),
            ListTile(
              leading: const Icon(Icons.collections_bookmark),
              title: const Text('Browse Tools'),
              subtitle: const Text('Use saved tools'),
              onTap: () {
                Navigator.pop(context);
                _browseTemplates();
              },
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

    // Find the current placement to get size
    final currentPlacement = activeScreen.placements.firstWhere(
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
                // Jump to the new screen
                final newIndex = dashboardService.currentLayout!.screens.length - 1;
                _pageController.animateToPage(
                  newIndex,
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
    return Scaffold(
      appBar: AppBar(
        title: Consumer<DashboardService>(
          builder: (context, dashboardService, child) {
            final layout = dashboardService.currentLayout;
            if (layout == null) return const Text('Dashboard');

            final screen = layout.activeScreen;
            return Text(screen?.name ?? 'Dashboard');
          },
        ),
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
                  // Show connection details on tap
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        service.isConnected
                            ? 'Connected to ${service.serverUrl}'
                            : 'Not connected - tap Settings to connect',
                      ),
                      duration: const Duration(seconds: 2),
                      backgroundColor: service.isConnected ? Colors.green : Colors.red,
                    ),
                  );
                },
                tooltip: service.isConnected ? 'Connected' : 'Disconnected',
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddMenu,
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
      ),
      body: Consumer2<DashboardService, SignalKService>(
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
                          builder: (context) => const SettingsScreen(),
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
              // PageView with screens - full screen
              PageView.builder(
                  controller: _pageController,
                  itemCount: layout.screens.length,
                  onPageChanged: (index) {
                    dashboardService.setActiveScreen(index);
                  },
                itemBuilder: (context, index) {
                  final screen = layout.screens[index];
                  return _buildScreenContent(screen, signalKService);
                },
              ),

              // Floating page indicators (only show if multiple screens)
              if (layout.screens.length > 1)
                Positioned(
                  bottom: 16,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(
                          layout.screens.length,
                          (index) => GestureDetector(
                            onTap: () {
                              _pageController.animateToPage(
                                index,
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            },
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: layout.activeScreenIndex == index ? 8 : 6,
                              height: layout.activeScreenIndex == index ? 8 : 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: layout.activeScreenIndex == index
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.5),
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
        },
      ),
    );
  }

  Widget _buildScreenContent(DashboardScreen screen, SignalKService signalKService) {
    final toolService = Provider.of<ToolService>(context, listen: false);

    if (screen.placements.isEmpty) {
      return Center(
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
              onPressed: _showAddMenu,
              icon: const Icon(Icons.add),
              label: const Text('Add Your First Tool'),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Granular column calculation based on orientation
        final orientation = MediaQuery.of(context).orientation;
        final int columns = orientation == Orientation.landscape ? 8 : 4;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: StaggeredGrid.count(
            crossAxisCount: columns,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            children: screen.placements.asMap().entries.map((entry) {
              final index = entry.key;
              final placement = entry.value;
              final tool = toolService.getTool(placement.toolId);

              if (tool == null) {
                return const SizedBox.shrink();
              }

              final registry = ToolRegistry();

              // Get tool size from placement (defaults to 1x1)
              // Max rows: 4 in landscape, 8 in portrait
              final maxRows = orientation == Orientation.landscape ? 4 : 8;
              final crossAxisCells = placement.position.width.clamp(1, columns);
              final mainAxisCells = placement.position.height.clamp(1, maxRows);

              // Build the tile child (content inside the StaggeredGridTile)
              Widget tileChild;

              if (_isEditMode) {
                // In edit mode, wrap with drag and drop
                tileChild = DragTarget<int>(
                  onWillAcceptWithDetails: (details) => details.data != index,
                  onAcceptWithDetails: (details) async {
                    final dashboardService = Provider.of<DashboardService>(context, listen: false);
                    await dashboardService.reorderPlacements(
                      screen.id,
                      details.data,
                      index,
                    );
                  },
                  builder: (context, candidateData, rejectedData) {
                    final isHovering = candidateData.isNotEmpty;
                    return LongPressDraggable<int>(
                      data: index,
                      feedback: Material(
                        elevation: 8,
                        borderRadius: BorderRadius.circular(8),
                        child: Opacity(
                          opacity: 0.8,
                          child: Container(
                            width: 150,
                            height: 150,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.dashboard_customize,
                                size: 64,
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ),
                      ),
                      childWhenDragging: Opacity(
                        opacity: 0.3,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: registry.buildTool(
                                tool.toolTypeId,
                                tool.config,
                                signalKService,
                              ),
                            ),
                          ],
                        ),
                      ),
                      child: Container(
                        decoration: isHovering
                            ? BoxDecoration(
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 3,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              )
                            : null,
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
                            // Drag handle
                            Positioned(
                              top: 4,
                              left: 4,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.grey.withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(
                                  Icons.drag_handle,
                                  size: 20,
                                  color: Colors.white,
                                ),
                              ),
                            ),
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
                            // Delete button at bottom-right
                            Positioned(
                              bottom: 4,
                              right: 4,
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
                          ],
                        ),
                      ),
                    );
                  },
                );
              } else {
                // Normal mode - just show the tool
                tileChild = Padding(
                  padding: const EdgeInsets.all(8),
                  child: registry.buildTool(
                    tool.toolTypeId,
                    tool.config,
                    signalKService,
                  ),
                );
              }

              return StaggeredGridTile.count(
                crossAxisCellCount: crossAxisCells,
                mainAxisCellCount: mainAxisCells,
                child: tileChild,
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
