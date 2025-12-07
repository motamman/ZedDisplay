import 'package:flutter/material.dart';
import '../../../models/tool_config.dart';
import '../../../models/tool.dart';
import '../../../services/signalk_service.dart';
import '../base_tool_configurator.dart';

/// Configurator for system/diagnostic tools: conversion_test, rpi_monitor, server_manager
/// These tools use pre-defined data sources and have no custom configuration options.
class SystemConfigurator extends ToolConfigurator {
  final String _toolTypeId;

  SystemConfigurator(this._toolTypeId);

  @override
  String get toolTypeId => _toolTypeId;

  @override
  Size get defaultSize => const Size(4, 8);

  // System tools have no custom properties

  @override
  void reset() {
    // Nothing to reset
  }

  @override
  void loadDefaults(SignalKService signalKService) {
    // Nothing to load
  }

  @override
  void loadFromTool(Tool tool) {
    // No custom properties to load
  }

  @override
  ToolConfig getConfig() {
    // Return empty config - these tools use pre-defined data sources only
    return ToolConfig(
      dataSources: const [],
      style: StyleConfig(
        customProperties: {},
      ),
    );
  }

  @override
  String? validate() {
    // No validation needed
    return null;
  }

  @override
  Widget buildConfigUI(BuildContext context, SignalKService signalKService) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_getToolTypeName()} Configuration',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),

          // Informational text based on tool type
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withAlpha(77),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withAlpha(77),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'About this tool',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _getToolDescription(),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Text(
            'This tool uses pre-defined data sources and has no additional configuration options. '
            'You can still customize the common settings like colors, font size, and TTL in the main configuration section.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).textTheme.bodySmall?.color?.withAlpha(179),
                  fontStyle: FontStyle.italic,
                ),
          ),
        ],
      ),
    );
  }

  String _getToolTypeName() {
    switch (_toolTypeId) {
      case 'conversion_test':
        return 'Conversion Test';
      case 'rpi_monitor':
        return 'Raspberry Pi Monitor';
      case 'server_manager':
        return 'Server Manager';
      case 'crew_messages':
        return 'Crew Messages';
      case 'crew_list':
        return 'Crew List';
      case 'intercom':
        return 'Voice Intercom';
      case 'file_share':
        return 'File Sharing';
      default:
        return 'System Tool';
    }
  }

  String _getToolDescription() {
    switch (_toolTypeId) {
      case 'conversion_test':
        return 'The Conversion Test tool displays various navigation and environmental data '
            'with automatic unit conversions. It helps verify that unit conversions are working '
            'correctly by showing 11 pre-defined data paths including position, heading, wind, '
            'speed, and course information.';
      case 'rpi_monitor':
        return 'The Raspberry Pi Monitor displays system performance metrics for your Raspberry Pi. '
            'It shows CPU utilization (overall and per-core), temperatures, memory usage, storage usage, '
            'and system uptime. This tool uses 10 pre-defined SignalK paths from the environment.rpi namespace.';
      case 'server_manager':
        return 'The Server Manager provides quick access to SignalK server administrative functions. '
            'It allows you to manage your SignalK server directly from the dashboard without needing '
            'to open a separate browser window.';
      case 'crew_messages':
        return 'View and send messages to crew members. Shows recent messages with quick reply, '
            'and provides access to the full chat screen.';
      case 'crew_list':
        return 'Displays online crew members and their current status. Shows who is on watch, '
            'off watch, standby, resting, or away.';
      case 'intercom':
        return 'Voice communication with crew members using WebRTC. Supports push-to-talk and '
            'open channel modes across multiple channels like Helm, Main Salon, and Crew Cabin.';
      case 'file_share':
        return 'Share and receive files with crew members over the local network. Supports images, '
            'documents, waypoints (GPX), and audio files.';
      default:
        return 'This system tool provides diagnostic or administrative functionality.';
    }
  }
}
