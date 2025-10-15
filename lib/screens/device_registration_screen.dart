import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/signalk_service.dart';
import '../services/dashboard_service.dart';
import '../models/access_request.dart';
import 'dashboard_manager_screen.dart';

class DeviceRegistrationScreen extends StatefulWidget {
  final String serverUrl;
  final bool secure;
  final String clientId;
  final String description;

  const DeviceRegistrationScreen({
    super.key,
    required this.serverUrl,
    required this.secure,
    required this.clientId,
    required this.description,
  });

  @override
  State<DeviceRegistrationScreen> createState() =>
      _DeviceRegistrationScreenState();
}

class _DeviceRegistrationScreenState extends State<DeviceRegistrationScreen> {
  @override
  void initState() {
    super.initState();
    _submitAccessRequest();
  }

  Future<void> _submitAccessRequest() async {
    final authService = Provider.of<AuthService>(context, listen: false);

    try {
      final request = await authService.requestAccess(
        serverUrl: widget.serverUrl,
        clientId: widget.clientId,
        description: widget.description,
        secure: widget.secure,
      );

      if (request.state == AccessRequestState.pending) {
        // Start polling for approval
        authService.startPolling(
          serverUrl: widget.serverUrl,
          requestId: request.requestId,
          secure: widget.secure,
        );
      } else if (request.state == AccessRequestState.approved) {
        // Already approved, navigate to dashboard
        _navigateToDashboard();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Registration failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _navigateToDashboard() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final signalKService = Provider.of<SignalKService>(context, listen: false);
    final dashboardService = Provider.of<DashboardService>(context, listen: false);

    // Get the saved token
    final token = authService.getSavedToken(widget.serverUrl);

    if (token != null) {
      try {
        // Connect to SignalK with the token
        await signalKService.connect(
          widget.serverUrl,
          secure: widget.secure,
          authToken: token,
        );

        // Trigger dashboard subscription update (happens automatically in DashboardService)
        // Force an update to ensure subscriptions are set up
        await dashboardService.updateLayout(dashboardService.currentLayout!);

        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => const DashboardManagerScreen(),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Connection failed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Registration'),
      ),
      body: Consumer<AuthService>(
        builder: (context, authService, child) {
          final request = authService.currentRequest;

          if (request == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildStatusIcon(request.state),
                const SizedBox(height: 24),
                _buildStatusMessage(request),
                const SizedBox(height: 32),
                _buildActionButtons(request),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusIcon(AccessRequestState state) {
    IconData icon;
    Color color;

    switch (state) {
      case AccessRequestState.pending:
        icon = Icons.pending;
        color = Colors.orange;
        break;
      case AccessRequestState.approved:
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case AccessRequestState.denied:
        icon = Icons.cancel;
        color = Colors.red;
        break;
      case AccessRequestState.error:
        icon = Icons.error;
        color = Colors.red;
        break;
    }

    return Icon(icon, size: 80, color: color);
  }

  Widget _buildStatusMessage(AccessRequest request) {
    String title;
    String message;

    switch (request.state) {
      case AccessRequestState.pending:
        title = 'Waiting for Approval';
        message =
            'Please approve this device on the SignalK server Admin UI.\n\nClient ID:\n${request.clientId}';
        break;
      case AccessRequestState.approved:
        title = 'Approved!';
        message = 'Your device has been approved. Connecting...';
        // Auto-navigate after a short delay
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) _navigateToDashboard();
        });
        break;
      case AccessRequestState.denied:
        title = 'Access Denied';
        message =
            'The server administrator denied your access request.\n\n${request.message ?? ""}';
        break;
      case AccessRequestState.error:
        title = 'Error';
        message =
            'An error occurred during registration.\n\n${request.message ?? ""}';
        break;
    }

    return Column(
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          message,
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildActionButtons(AccessRequest request) {
    if (request.state == AccessRequestState.pending) {
      return Column(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          const Text('Polling for approval...'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              Provider.of<AuthService>(context, listen: false).stopPolling();
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
        ],
      );
    }

    if (request.state == AccessRequestState.denied ||
        request.state == AccessRequestState.error) {
      return ElevatedButton(
        onPressed: () {
          Provider.of<AuthService>(context, listen: false).resetCurrentRequest();
          Navigator.of(context).pop();
        },
        child: const Text('Back'),
      );
    }

    return const SizedBox.shrink();
  }

  @override
  void dispose() {
    Provider.of<AuthService>(context, listen: false).stopPolling();
    super.dispose();
  }
}
