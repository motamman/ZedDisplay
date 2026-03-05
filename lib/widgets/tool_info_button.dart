import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/tool_info.dart';
import '../services/tool_info_service.dart';
import '../services/signalk_service.dart';

/// Button that displays tool information in a dialog
/// Shows tool description, required plugins with status, and data sources
class ToolInfoButton extends StatefulWidget {
  final String toolId;
  final SignalKService signalKService;
  final double iconSize;
  final Color? iconColor;

  const ToolInfoButton({
    super.key,
    required this.toolId,
    required this.signalKService,
    this.iconSize = 18,
    this.iconColor,
  });

  @override
  State<ToolInfoButton> createState() => _ToolInfoButtonState();
}

class _ToolInfoButtonState extends State<ToolInfoButton> {
  @override
  void initState() {
    super.initState();
    // Ensure service is loaded
    ToolInfoService.instance.load();
  }

  Future<void> _showInfoDialog() async {
    final toolInfo = ToolInfoService.instance.getToolInfo(widget.toolId);
    if (toolInfo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No info available for ${widget.toolId}')),
      );
      return;
    }

    // Check plugin status
    Map<String, PluginStatus> pluginStatus = {};
    if (toolInfo.requiredPlugins.isNotEmpty) {
      pluginStatus = await ToolInfoService.instance.checkPluginStatus(
        toolInfo.requiredPlugins,
        widget.signalKService,
      );
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => _ToolInfoDialog(
        toolInfo: toolInfo,
        pluginStatus: pluginStatus,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.info_outline,
        size: widget.iconSize,
        color: widget.iconColor ?? Theme.of(context).colorScheme.primary,
      ),
      onPressed: _showInfoDialog,
      tooltip: 'Tool info',
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(
        minWidth: widget.iconSize + 8,
        minHeight: widget.iconSize + 8,
      ),
    );
  }
}

/// Dialog that displays tool information
class _ToolInfoDialog extends StatelessWidget {
  final ToolInfoData toolInfo;
  final Map<String, PluginStatus> pluginStatus;

  const _ToolInfoDialog({
    required this.toolInfo,
    required this.pluginStatus,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.info_outline, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              toolInfo.name,
              style: theme.textTheme.titleLarge,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Description (markdown)
              MarkdownBody(
                data: toolInfo.description,
                styleSheet: MarkdownStyleSheet(
                  p: theme.textTheme.bodyMedium,
                  strong: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  listBullet: theme.textTheme.bodyMedium,
                ),
                shrinkWrap: true,
              ),

              // Required plugins section
              if (toolInfo.requiredPlugins.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  'Required Plugins',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ...toolInfo.requiredPlugins.map((plugin) {
                  final status = pluginStatus[plugin.pluginId] ??
                      PluginStatus.notInstalled;
                  return _PluginStatusRow(
                    plugin: plugin,
                    status: status,
                  );
                }),
              ],

              // Data sources section (filter out "signalk" - implicit)
              if (toolInfo.dataSources.where((s) => s.id != 'signalk').isNotEmpty) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  'Data Sources',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ...toolInfo.dataSources
                    .where((source) => source.id != 'signalk')
                    .map((source) {
                  return _DataSourceRow(dataSource: source);
                }),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Row showing a plugin requirement with its status
class _PluginStatusRow extends StatelessWidget {
  final PluginRequirement plugin;
  final PluginStatus status;

  const _PluginStatusRow({
    required this.plugin,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    IconData icon;
    Color color;
    String statusText;

    switch (status) {
      case PluginStatus.installed:
        icon = Icons.check_circle;
        color = Colors.green;
        statusText = 'Installed';
        break;
      case PluginStatus.disabled:
        icon = Icons.warning_amber;
        color = Colors.orange;
        statusText = 'Disabled';
        break;
      case PluginStatus.notInstalled:
        icon = Icons.cancel;
        color = Colors.red;
        statusText = 'Not installed';
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      plugin.displayName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (!plugin.required) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'optional',
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ],
                ),
                if (plugin.description != null)
                  Text(
                    plugin.description!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            statusText,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Row showing a data source with optional link
class _DataSourceRow extends StatelessWidget {
  final DataSourceInfo dataSource;

  const _DataSourceRow({required this.dataSource});

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            Icons.storage,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              dataSource.name,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (dataSource.url != null)
            IconButton(
              icon: Icon(
                Icons.open_in_new,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              onPressed: () => _launchUrl(dataSource.url!),
              tooltip: 'Open website',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
        ],
      ),
    );
  }
}
