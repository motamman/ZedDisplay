import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/dashboard_service.dart';
import '../services/signalk_service.dart';
import '../services/tool_registry.dart';
import '../services/tool_service.dart';
import '../models/dashboard_screen.dart';
import '../models/tool.dart';
import '../widgets/save_template_dialog.dart';
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

    if (result is Tool) {
      // Create a placement for this tool
      final placement = toolService.createPlacement(
        toolId: result.id,
        screenId: activeScreen.id,
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

    if (result is Tool) {
      // Create a placement for this tool
      final placement = toolService.createPlacement(
        toolId: result.id,
        screenId: activeScreen.id,
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
              title: const Text('Create Custom Tool'),
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

  Future<void> _editTool(Tool tool) async {
    final toolService = Provider.of<ToolService>(context, listen: false);

    final templateData = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => SaveTemplateDialog(tool: tool),
    );

    if (templateData == null) return;

    try {
      final updatedTool = tool.copyWith(
        name: templateData['name'] as String,
        description: templateData['description'] as String,
        author: templateData['author'] as String,
        category: templateData['category'],
        tags: templateData['tags'] as List<String>,
        updatedAt: DateTime.now(),
      );

      await toolService.saveTool(updatedTool);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tool "${updatedTool.name}" updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update tool: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _removePlacement(String screenId, String toolId) async {
    final dashboardService = Provider.of<DashboardService>(context, listen: false);
    await dashboardService.removePlacement(screenId, toolId);
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
          Consumer<SignalKService>(
            builder: (context, service, child) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Center(
                  child: Row(
                    children: [
                      Icon(
                        service.isConnected ? Icons.cloud_done : Icons.cloud_off,
                        color: service.isConnected ? Colors.green : Colors.red,
                        size: 20,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        service.isConnected ? 'Connected' : 'Disconnected',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
            },
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

          return Column(
            children: [
              // Page indicators
              if (layout.screens.length > 1)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
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
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: layout.activeScreenIndex == index ? 12 : 8,
                          height: layout.activeScreenIndex == index ? 12 : 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: layout.activeScreenIndex == index
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              // PageView with screens
              Expanded(
                child: PageView.builder(
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
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddMenu,
        icon: const Icon(Icons.add),
        label: const Text('Add Tool'),
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

    return OrientationBuilder(
      builder: (context, orientation) {
        return LayoutBuilder(
          builder: (context, constraints) {
            // Calculate responsive columns based on screen width AND orientation
            final screenWidth = constraints.maxWidth;
            final screenHeight = constraints.maxHeight;
            final int columns;

            // Use width as primary factor for column count
            if (screenWidth >= 1200) {
              columns = 4; // Desktop/large tablets
            } else if (screenWidth >= 900) {
              columns = 3; // Tablets landscape or large tablets
            } else if (screenWidth >= 600) {
              columns = 2; // Large phones landscape or tablets portrait
            } else {
              columns = 1; // Phones in portrait
            }

            // Calculate cell size based on available width
            final cellWidth = (screenWidth - 32 - (columns - 1) * 16) / columns;

            // Adjust cell height based on orientation to prevent oversized cells
            final cellHeight = orientation == Orientation.landscape
                ? (screenHeight - 150) / 3.0  // Landscape: more conservative height
                : cellWidth;  // Portrait: square cells

            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                alignment: WrapAlignment.start,
                children: screen.placements.map((placement) {
                  final registry = ToolRegistry();

                  // Resolve the tool from the placement
                  final tool = toolService.getTool(placement.toolId);

                  // Skip if tool not found
                  if (tool == null) {
                    return const SizedBox.shrink();
                  }

                  // Get tool's size preferences, clamped to available columns
                  final toolWidth = placement.position.width.clamp(1, columns);
                  final toolHeight = placement.position.height.clamp(1, 4);

                  // Calculate actual dimensions
                  final width = (cellWidth * toolWidth) + ((toolWidth - 1) * 16);
                  final height = cellHeight * toolHeight + ((toolHeight - 1) * 16);

                  return SizedBox(
                    width: width,
                    height: height,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Use FittedBox to scale content down to fit if needed
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.center,
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: width,
                              maxHeight: height,
                            ),
                            child: registry.buildTool(
                              tool.toolTypeId,
                              tool.config,
                              signalKService,
                            ),
                          ),
                        ),

                        // Edit mode buttons
                        if (_isEditMode) ...[
                          // Edit Tool button
                          Positioned(
                            top: 4,
                            left: 4,
                            child: IconButton(
                              icon: const Icon(Icons.edit, size: 16),
                              onPressed: () => _editTool(tool),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.blue.withValues(alpha: 0.7),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.all(4),
                                minimumSize: const Size(24, 24),
                              ),
                              tooltip: 'Edit Tool',
                            ),
                          ),
                          // Delete button
                          Positioned(
                            top: 4,
                            right: 4,
                            child: IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () => _removePlacement(screen.id, placement.toolId),
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
                      ],
                    ),
                  );
                }).toList(),
              ),
            );
          },
        );
      },
    );
  }
}
