import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/intercom_service.dart';
import '../../services/tool_registry.dart';

/// Permission levels for SignalK users
enum SignalKPermission {
  readonly,
  readwrite,
  admin,
}

/// Extension to provide display properties for permissions
extension SignalKPermissionExtension on SignalKPermission {
  String get displayName {
    switch (this) {
      case SignalKPermission.readonly:
        return 'Read Only';
      case SignalKPermission.readwrite:
        return 'Read/Write';
      case SignalKPermission.admin:
        return 'Admin';
    }
  }

  Color get color {
    switch (this) {
      case SignalKPermission.readonly:
        return Colors.grey;
      case SignalKPermission.readwrite:
        return Colors.blue;
      case SignalKPermission.admin:
        return Colors.purple;
    }
  }

  IconData get icon {
    switch (this) {
      case SignalKPermission.readonly:
        return Icons.visibility;
      case SignalKPermission.readwrite:
        return Icons.edit;
      case SignalKPermission.admin:
        return Icons.shield;
    }
  }
}

/// Model for a SignalK user
class SignalKUser {
  final String userId;
  final String username;
  final SignalKPermission permission;

  SignalKUser({
    required this.userId,
    required this.username,
    required this.permission,
  });

  factory SignalKUser.fromJson(Map<String, dynamic> json) {
    // Parse permission from string
    final permStr = (json['type'] as String? ?? json['permission'] as String? ?? 'readonly').toLowerCase();
    SignalKPermission perm;
    switch (permStr) {
      case 'admin':
        perm = SignalKPermission.admin;
        break;
      case 'readwrite':
        perm = SignalKPermission.readwrite;
        break;
      default:
        perm = SignalKPermission.readonly;
    }

    return SignalKUser(
      userId: json['userId'] as String? ?? json['username'] as String? ?? '',
      username: json['username'] as String? ?? json['userId'] as String? ?? '',
      permission: perm,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'username': username,
      'type': permission.name,
    };
  }
}

/// Tool for managing SignalK server users
class UserManagementTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const UserManagementTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<UserManagementTool> createState() => _UserManagementToolState();
}

class _UserManagementToolState extends State<UserManagementTool> {
  List<SignalKUser> _users = [];
  bool _loading = false;
  Timer? _refreshTimer;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    // Auto-refresh every 30 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadUsers();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
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

  Future<void> _loadUsers() async {
    if (!widget.signalKService.isConnected) return;

    // Skip polling if no valid auth token (prevents 401 spam)
    final token = widget.signalKService.authToken?.token;
    if (token == null || token.isEmpty) {
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/skServer/security/users'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<SignalKUser> users = [];

        if (data is List) {
          users = data
              .map((item) => SignalKUser.fromJson(item as Map<String, dynamic>))
              .toList();
        } else if (data is Map) {
          // Handle map format where keys are user IDs
          (data as Map<String, dynamic>).forEach((key, value) {
            if (value is Map<String, dynamic>) {
              users.add(SignalKUser.fromJson({
                ...value,
                'userId': value['userId'] ?? key,
                'username': value['username'] ?? key,
              }));
            }
          });
        }

        if (mounted) {
          setState(() {
            _users = users;
            _loading = false;
          });
        }
      } else if (response.statusCode == 401) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Admin access required';
            _loading = false;
          });
        }
      } else if (response.statusCode == 403) {
        if (mounted) {
          setState(() {
            _errorMessage = 'Admin permissions needed';
            _loading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _loading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading users: $e');
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _createUser(String username, String password, SignalKPermission permission) async {
    try {
      // SignalK expects POST to /skServer/security/users/{userId} with user data in body
      final response = await http.post(
        Uri.parse('$_baseUrl/skServer/security/users/$username'),
        headers: _getHeaders(),
        body: jsonEncode({
          'password': password,
          'type': permission.name,
        }),
      ).timeout(const Duration(seconds: 10));

      if (mounted) {
        if (response.statusCode == 200 || response.statusCode == 201) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User created successfully'),
              backgroundColor: Colors.green,
            ),
          );
          await _loadUsers();
        } else if (response.statusCode == 401) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Not authorized. Admin permissions required.'),
              backgroundColor: Colors.red,
            ),
          );
        } else if (response.statusCode == 400) {
          // Server returns 400 for "User already exists"
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.body.isNotEmpty ? response.body : 'User already exists or invalid request'),
              backgroundColor: Colors.red,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to create user: ${response.statusCode}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error creating user: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateUser(String userId, {String? password, SignalKPermission? permission}) async {
    try {
      final body = <String, dynamic>{};
      if (password != null && password.isNotEmpty) {
        body['password'] = password;
      }
      if (permission != null) {
        body['type'] = permission.name;
      }

      final response = await http.put(
        Uri.parse('$_baseUrl/skServer/security/users/$userId'),
        headers: _getHeaders(),
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));

      if (mounted) {
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User updated successfully'),
              backgroundColor: Colors.green,
            ),
          );
          await _loadUsers();
        } else if (response.statusCode == 401) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Not authorized. Admin permissions required.'),
              backgroundColor: Colors.red,
            ),
          );
        } else if (response.statusCode == 400) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid password or request'),
              backgroundColor: Colors.red,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update user: ${response.statusCode}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error updating user: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteUser(SignalKUser user) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete User'),
        content: Text('Delete user "${user.username}"?\nThis cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/skServer/security/users/${user.userId}'),
        headers: _getHeaders(),
      ).timeout(const Duration(seconds: 10));

      if (mounted) {
        if (response.statusCode == 200) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User deleted'),
              backgroundColor: Colors.orange,
            ),
          );
          await _loadUsers();
        } else if (response.statusCode == 401) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Not authorized. Admin permissions required.'),
              backgroundColor: Colors.red,
            ),
          );
        } else if (response.statusCode == 400) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot delete your own account'),
              backgroundColor: Colors.red,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete user: ${response.statusCode}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error deleting user: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showCreateUserDialog() {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    SignalKPermission selectedPermission = SignalKPermission.readwrite;
    String? errorText;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create User'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: confirmPasswordController,
                  decoration: const InputDecoration(
                    labelText: 'Confirm Password',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<SignalKPermission>(
                  initialValue: selectedPermission,
                  decoration: const InputDecoration(
                    labelText: 'Permission',
                    border: OutlineInputBorder(),
                  ),
                  items: SignalKPermission.values.map((p) => DropdownMenuItem(
                    value: p,
                    child: Row(
                      children: [
                        Icon(p.icon, size: 16, color: p.color),
                        const SizedBox(width: 8),
                        Text(p.displayName),
                      ],
                    ),
                  )).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() {
                        selectedPermission = value;
                      });
                    }
                  },
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorText!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () {
                final username = usernameController.text.trim();
                final password = passwordController.text;
                final confirmPassword = confirmPasswordController.text;

                if (username.isEmpty) {
                  setDialogState(() {
                    errorText = 'Username is required';
                  });
                  return;
                }
                if (password.isEmpty) {
                  setDialogState(() {
                    errorText = 'Password is required';
                  });
                  return;
                }
                if (password != confirmPassword) {
                  setDialogState(() {
                    errorText = 'Passwords do not match';
                  });
                  return;
                }
                if (password.length < 4) {
                  setDialogState(() {
                    errorText = 'Password must be at least 4 characters';
                  });
                  return;
                }

                Navigator.of(context).pop();
                _createUser(username, password, selectedPermission);
              },
              child: const Text('CREATE'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditUserDialog(SignalKUser user) {
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    SignalKPermission selectedPermission = user.permission;
    bool changePassword = false;
    String? errorText;

    // Get intercom service for channel subscriptions
    final intercomService = Provider.of<IntercomService>(context, listen: false);
    final channels = intercomService.channels;

    // Get current subscriptions for this user (use username as user ID for SignalK users)
    final userId = 'user:${user.username}';
    Set<String> selectedChannels = intercomService.getSubscribedChannels(userId);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Edit User: ${user.username}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<SignalKPermission>(
                  initialValue: selectedPermission,
                  decoration: const InputDecoration(
                    labelText: 'Permission',
                    border: OutlineInputBorder(),
                  ),
                  items: SignalKPermission.values.map((p) => DropdownMenuItem(
                    value: p,
                    child: Row(
                      children: [
                        Icon(p.icon, size: 16, color: p.color),
                        const SizedBox(width: 8),
                        Text(p.displayName),
                      ],
                    ),
                  )).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() {
                        selectedPermission = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                CheckboxListTile(
                  title: const Text('Change Password'),
                  value: changePassword,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (value) {
                    setDialogState(() {
                      changePassword = value ?? false;
                      if (!changePassword) {
                        passwordController.clear();
                        confirmPasswordController.clear();
                        errorText = null;
                      }
                    });
                  },
                ),
                if (changePassword) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: passwordController,
                    decoration: const InputDecoration(
                      labelText: 'New Password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: confirmPasswordController,
                    decoration: const InputDecoration(
                      labelText: 'Confirm Password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                  ),
                ],
                // Channel Subscriptions section
                if (channels.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text(
                    'Channel Subscriptions',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Select which audio channels this user receives',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...channels.map((channel) {
                    final isEmergency = channel.isEmergency;
                    final isSubscribed = selectedChannels.contains(channel.id);

                    return CheckboxListTile(
                      title: Row(
                        children: [
                          if (isEmergency)
                            const Icon(Icons.warning, size: 16, color: Colors.red),
                          if (isEmergency) const SizedBox(width: 8),
                          Text(
                            channel.name,
                            style: TextStyle(
                              fontSize: 13,
                              color: isEmergency ? Colors.red : null,
                            ),
                          ),
                        ],
                      ),
                      subtitle: channel.description != null
                          ? Text(
                              channel.description!,
                              style: const TextStyle(fontSize: 11),
                            )
                          : null,
                      value: isSubscribed,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      // Emergency channel cannot be toggled off
                      onChanged: isEmergency
                          ? null
                          : (value) {
                              setDialogState(() {
                                if (value == true) {
                                  selectedChannels = {...selectedChannels, channel.id};
                                } else {
                                  selectedChannels = selectedChannels
                                      .where((id) => id != channel.id)
                                      .toSet();
                                }
                              });
                            },
                    );
                  }),
                ],
                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    errorText!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () {
                String? newPassword;

                if (changePassword) {
                  final password = passwordController.text;
                  final confirmPassword = confirmPasswordController.text;

                  if (password.isEmpty) {
                    setDialogState(() {
                      errorText = 'Password is required';
                    });
                    return;
                  }
                  if (password != confirmPassword) {
                    setDialogState(() {
                      errorText = 'Passwords do not match';
                    });
                    return;
                  }
                  if (password.length < 4) {
                    setDialogState(() {
                      errorText = 'Password must be at least 4 characters';
                    });
                    return;
                  }
                  newPassword = password;
                }

                Navigator.of(context).pop();
                _updateUser(
                  user.userId,
                  password: newPassword,
                  permission: selectedPermission != user.permission ? selectedPermission : null,
                );

                // Save channel subscriptions
                intercomService.setUserSubscriptions(userId, selectedChannels);
              },
              child: const Text('SAVE'),
            ),
          ],
        ),
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
                          const Icon(Icons.people, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'User Management',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.add, size: 18),
                            onPressed: _showCreateUserDialog,
                            tooltip: 'Add User',
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh, size: 18),
                            onPressed: _loadUsers,
                            tooltip: 'Refresh',
                          ),
                        ],
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

                  // Users List Section
                  Expanded(
                    child: _buildUsersSection(theme),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildUsersSection(ThemeData theme) {
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
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(6),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.people_outline, size: 14, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Users (${_users.length})',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_loading) ...[
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
            child: _users.isEmpty && !_loading
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _errorMessage != null ? 'Cannot load users' : 'No users found',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.textTheme.bodySmall?.color,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(6),
                    itemCount: _users.length,
                    itemBuilder: (context, index) {
                      final user = _users[index];
                      return _buildUserTile(user, theme);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserTile(SignalKUser user, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: user.permission.color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(
              Icons.person,
              size: 16,
              color: user.permission.color,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.username,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Permission badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: user.permission.color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(user.permission.icon, size: 10, color: user.permission.color),
                  const SizedBox(width: 4),
                  Text(
                    user.permission.name,
                    style: TextStyle(
                      fontSize: 9,
                      color: user.permission.color,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            // Edit button
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 16),
              color: Colors.blue.withValues(alpha: 0.7),
              onPressed: () => _showEditUserDialog(user),
              tooltip: 'Edit user',
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
            ),
            // Delete button
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 16),
              color: Colors.red.withValues(alpha: 0.7),
              onPressed: () => _deleteUser(user),
              tooltip: 'Delete user',
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}

/// Builder for user management tool
class UserManagementToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'user_management',
      name: 'User Management',
      description: 'Manage SignalK server users - create, edit permissions, change passwords, and delete user accounts',
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
    return UserManagementTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
