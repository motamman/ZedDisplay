import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/dashboard_service.dart';
import '../services/signalk_service.dart';
import '../services/tool_registry.dart';
import '../services/template_service.dart';
import '../models/dashboard_screen.dart';
import '../models/tool_instance.dart';
import '../widgets/save_template_dialog.dart';
import 'tool_config_screen.dart';
import 'template_library_screen.dart';

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
    final activeScreen = dashboardService.currentLayout?.activeScreen;

    if (activeScreen == null) return;

    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ToolConfigScreen(screenId: activeScreen.id),
      ),
    );

    if (result is ToolInstance) {
      await dashboardService.addToolToActiveScreen(result);
    }
  }

  Future<void> _browseTemplates() async {
    final dashboardService = Provider.of<DashboardService>(context, listen: false);

    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const TemplateLibraryScreen(),
      ),
    );

    if (result is ToolInstance) {
      await dashboardService.addToolToActiveScreen(result);
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
              title: const Text('Browse Templates'),
              subtitle: const Text('Use pre-configured tool templates'),
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

  Future<void> _saveAsTemplate(ToolInstance toolInstance) async {
    final templateService = Provider.of<TemplateService>(context, listen: false);

    final templateData = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => SaveTemplateDialog(toolInstance: toolInstance),
    );

    if (templateData == null) return;

    try {
      final template = templateService.createTemplateFromTool(
        toolInstance: toolInstance,
        name: templateData['name'] as String,
        description: templateData['description'] as String,
        author: templateData['author'] as String,
        category: templateData['category'],
        tags: templateData['tags'] as List<String>,
      );

      await templateService.saveTemplate(template);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Template "${template.name}" saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save template: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _removeTool(String screenId, String toolId) async {
    final dashboardService = Provider.of<DashboardService>(context, listen: false);
    await dashboardService.removeTool(screenId, toolId);
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
              // TODO: Navigate to settings
            },
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
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Back to Connection'),
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
    if (screen.tools.isEmpty) {
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
        ),
        itemCount: screen.tools.length,
        itemBuilder: (context, index) {
          final tool = screen.tools[index];
          final registry = ToolRegistry();

          return Stack(
            children: [
              registry.buildTool(
                tool.toolTypeId,
                tool.config,
                signalKService,
              ),

              // Edit mode buttons
              if (_isEditMode) ...[
                // Save as Template button
                Positioned(
                  top: 4,
                  left: 4,
                  child: IconButton(
                    icon: const Icon(Icons.bookmark_add, size: 16),
                    onPressed: () => _saveAsTemplate(tool),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.blue.withValues(alpha: 0.7),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(4),
                      minimumSize: const Size(24, 24),
                    ),
                    tooltip: 'Save as Template',
                  ),
                ),
                // Delete button
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => _removeTool(screen.id, tool.id),
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
          );
        },
      ),
    );
  }
}
