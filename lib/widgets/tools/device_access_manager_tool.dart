import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';

/// Model for a device access request
class DeviceAccessRequest {
  final String accessIdentifier;
  final String accessDescription;
  final String? ip;

  DeviceAccessRequest({
    required this.accessIdentifier,
    required this.accessDescription,
    this.ip,
  });

  factory DeviceAccessRequest.fromJson(Map<String, dynamic> json) {
    return DeviceAccessRequest(
      accessIdentifier: json['accessIdentifier'] as String? ?? json['requestId'] as String? ?? '',
      accessDescription: json['accessDescription'] as String? ?? json['description'] as String? ?? 'Unknown device',
      ip: json['ip'] as String?,
    );
  }
}

/// Model for an approved device
class ApprovedDevice {
  final String clientId;
  final String? description;
  final String? permissions;

  ApprovedDevice({
    required this.clientId,
    this.description,
    this.permissions,
  });

  factory ApprovedDevice.fromJson(Map<String, dynamic> json) {
    return ApprovedDevice(
      clientId: json['clientId'] as String? ?? '',
      description: json['description'] as String?,
      permissions: json['permissions'] as String?,
    );
  }
}

/// Tool for managing device access requests and permissions on the SignalK server
class DeviceAccessManagerTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const DeviceAccessManagerTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<DeviceAccessManagerTool> createState() => _DeviceAccessManagerToolState();
}

class _DeviceAccessManagerToolState extends State<DeviceAccessManagerTool> {
  List<DeviceAccessRequest> _pendingRequests = [];
  List<ApprovedDevice> _approvedDevices = [];
  bool _loadingRequests = false;
  bool _loadingDevices = false;
  Timer? _refreshTimer;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
    // Auto-refresh every 10 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadPendingRequests();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadPendingRequests(),
      _loadApprovedDevices(),
    ]);
  }

  Map<String, String> _getHeaders() {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (widget.signalKService.authToken != null) {
      headers['Authorization'] = 'Bearer ${widget.signalKService.authToken!.token}';
    }
    return headers;
  }

  String get _protocol => widget.signalKService.useSecureConnection ? 'https' : 'http';
  String get _baseUrl => '$_protocol://${widget.signalKService.serverUrl}';

  Future<void> _loadPendingRequests() async {
    if (!widget.signalKService.isConnected) return;

    if (mounted) {
      setState(() {
        _loadingRequests = true;
        _errorMessage = null;
      });
    }

    try {
      // Try the admin security API endpoint
      final response = await http.get(
        Uri.parse('$_baseUrl/skServer/security/access/requests'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<DeviceAccessRequest> requests = [];

        if (data is List) {
          requests = data
              .map((item) => DeviceAccessRequest.fromJson(item as Map<String, dynamic>))
              .toList();
        } else if (data is Map) {
          // Handle map format where keys are request IDs
          (data as Map<String, dynamic>).forEach((key, value) {
            if (value is Map<String, dynamic>) {
              requests.add(DeviceAccessRequest.fromJson({
                ...value,
                'accessIdentifier': value['accessIdentifier'] ?? key,
              }));
            }
          });
        }

        if (mounted) {
          setState(() {
            _pendingRequests = requests;
            _loadingRequests = false;
          });
        }
      } else if (response.statusCode == 401) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Admin access required';
            _loadingRequests = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _loadingRequests = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading pending requests: $e');
      if (mounted) {
        setState(() {
          _loadingRequests = false;
        });
      }
    }
  }

  Future<void> _loadApprovedDevices() async {
    if (!widget.signalKService.isConnected) return;

    if (mounted) {
      setState(() => _loadingDevices = true);
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/skServer/security/devices'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<ApprovedDevice> devices = [];

        if (data is List) {
          devices = data
              .map((item) => ApprovedDevice.fromJson(item as Map<String, dynamic>))
              .toList();
        } else if (data is Map) {
          (data as Map<String, dynamic>).forEach((key, value) {
            if (value is Map<String, dynamic>) {
              devices.add(ApprovedDevice.fromJson({
                ...value,
                'clientId': value['clientId'] ?? key,
              }));
            }
          });
        }

        if (mounted) {
          setState(() {
            _approvedDevices = devices;
            _loadingDevices = false;
          });
        }
      } else {
        if (mounted) {
          setState(() => _loadingDevices = false);
        }
      }
    } catch (e) {
      debugPrint('Error loading approved devices: $e');
      if (mounted) {
        setState(() => _loadingDevices = false);
      }
    }
  }

  Future<void> _approveRequest(DeviceAccessRequest request, String permission) async {
    try {
      // Build the payload with default permissions
      final payload = <String, dynamic>{
        'permissions': 'readonly',
        'expiration': '1y',
      };

      final response = await http.put(
        Uri.parse('$_baseUrl/skServer/security/access/requests/${request.accessIdentifier}/${permission.toLowerCase()}'),
        headers: _getHeaders(),
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 10));

      if (mounted) {
        if (response.statusCode == 200 || response.statusCode == 202) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                permission == 'APPROVED'
                    ? 'Device approved successfully'
                    : 'Device access denied',
              ),
              backgroundColor: permission == 'APPROVED' ? Colors.green : Colors.orange,
            ),
          );
          // Remove from pending list immediately
          setState(() {
            _pendingRequests.removeWhere((r) => r.accessIdentifier == request.accessIdentifier);
          });
          // Refresh both lists
          await _loadData();
        } else if (response.statusCode == 401) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Not authorized. Admin permissions required.'),
              backgroundColor: Colors.red,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to process request: ${response.statusCode}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error processing access request: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _revokeDevice(ApprovedDevice device) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke Device Access'),
        content: Text('Are you sure you want to revoke access for "${device.description ?? device.clientId}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('REVOKE'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/skServer/security/devices/${device.clientId}'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 10));

      if (mounted) {
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Device access revoked'),
              backgroundColor: Colors.orange,
            ),
          );
          await _loadApprovedDevices();
        } else if (response.statusCode == 401) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Not authorized. Admin permissions required.'),
              backgroundColor: Colors.red,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to revoke access: ${response.statusCode}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error revoking device: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showApproveDialog(DeviceAccessRequest request) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Approve Device'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Device: ${request.accessDescription}'),
            if (request.ip != null) ...[
              const SizedBox(height: 8),
              Text('IP: ${request.ip}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
            const SizedBox(height: 16),
            const Text('Grant this device access to the server?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _approveRequest(request, 'DENIED');
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('DENY'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _approveRequest(request, 'APPROVED');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('APPROVE'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SizedBox(
            height: constraints.maxHeight,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.security, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Device Access',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 18),
                        onPressed: _loadData,
                        tooltip: 'Refresh',
                      ),
                    ],
                  ),

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning, color: Colors.red, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 12),

                  // Pending Requests Section
                  _buildPendingRequestsSection(theme),

                  const SizedBox(height: 12),

                  // Approved Devices Section
                  Expanded(
                    child: _buildApprovedDevicesSection(theme),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPendingRequestsSection(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: _pendingRequests.isNotEmpty
              ? Colors.orange.withValues(alpha: 0.5)
              : Colors.grey.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _pendingRequests.isNotEmpty
                  ? Colors.orange.withValues(alpha: 0.15)
                  : Colors.grey.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(6),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.pending_actions,
                  size: 14,
                  color: _pendingRequests.isNotEmpty ? Colors.orange : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  'Pending Requests (${_pendingRequests.length})',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _pendingRequests.isNotEmpty ? Colors.orange.shade700 : null,
                  ),
                ),
                if (_loadingRequests) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
          ),
          // List
          if (_pendingRequests.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'No pending requests',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.textTheme.bodySmall?.color,
                ),
              ),
            )
          else
            ...(_pendingRequests.take(3).map((request) => _buildPendingRequestTile(request, theme))),
        ],
      ),
    );
  }

  Widget _buildPendingRequestTile(DeviceAccessRequest request, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(Icons.devices, size: 16, color: Colors.orange),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.accessDescription,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
                if (request.ip != null)
                  Text(
                    request.ip!,
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Quick action buttons
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            color: Colors.red,
            onPressed: () => _approveRequest(request, 'DENIED'),
            tooltip: 'Deny',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
          IconButton(
            icon: const Icon(Icons.check, size: 18),
            color: Colors.green,
            onPressed: () => _showApproveDialog(request),
            tooltip: 'Approve',
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildApprovedDevicesSection(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(6),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_user, size: 14, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  'Approved Devices (${_approvedDevices.length})',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_loadingDevices) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
          ),
          // Scrollable list
          Expanded(
            child: _approvedDevices.isEmpty && !_loadingDevices
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'No approved devices',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.textTheme.bodySmall?.color,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(6),
                    itemCount: _approvedDevices.length,
                    itemBuilder: (context, index) {
                      final device = _approvedDevices[index];
                      return _buildApprovedDeviceTile(device, theme);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildApprovedDeviceTile(ApprovedDevice device, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.devices,
              size: 16,
              color: Colors.green,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.description ?? device.clientId,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    device.permissions ?? 'readonly',
                    style: TextStyle(
                      fontSize: 9,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 16),
              color: Colors.red.withValues(alpha: 0.7),
              onPressed: () => _revokeDevice(device),
              tooltip: 'Revoke access',
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}

/// Builder for device access manager tool
class DeviceAccessManagerToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'device_access_manager',
      name: 'Device Access',
      description: 'Manage device access requests and permissions - approve, deny, and revoke device access to the SignalK server',
      category: ToolCategory.system,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: false,
        allowsMultiplePaths: false,
        minPaths: 0,
        maxPaths: 0,
        styleOptions: const [],
      ),
    );
  }

  @override
  ToolConfig? getDefaultConfig(String vesselId) {
    return ToolConfig(
      vesselId: vesselId,
      dataSources: [],
      style: StyleConfig(),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return DeviceAccessManagerTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
