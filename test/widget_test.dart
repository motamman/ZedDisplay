import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zed_display/main.dart';
import 'package:zed_display/services/storage_service.dart';
import 'package:zed_display/services/signalk_service.dart';
import 'package:zed_display/services/dashboard_service.dart';
import 'package:zed_display/services/tool_service.dart';
import 'package:zed_display/services/auth_service.dart';
import 'package:zed_display/services/setup_service.dart';
import 'package:zed_display/services/notification_service.dart';
import 'package:zed_display/services/foreground_service.dart';

void main() {
  late StorageService storageService;
  late SignalKService signalKService;
  late DashboardService dashboardService;
  late ToolService toolService;
  late AuthService authService;
  late SetupService setupService;
  late NotificationService notificationService;
  late ForegroundTaskService foregroundService;

  setUp(() async {
    // Initialize storage service for tests
    storageService = StorageService();
    await storageService.initialize();

    // Initialize notification service
    notificationService = NotificationService();
    await notificationService.initialize();

    // Initialize foreground service
    foregroundService = ForegroundTaskService();
    await foregroundService.initialize();

    // Initialize tool service
    toolService = ToolService(storageService);
    await toolService.initialize();

    // Initialize SignalK service
    signalKService = SignalKService();

    // Initialize dashboard service
    dashboardService = DashboardService(
      storageService,
      signalKService,
      toolService,
    );
    await dashboardService.initialize();

    // Initialize auth service
    authService = AuthService(storageService);

    // Initialize setup service
    setupService = SetupService(
      storageService,
      toolService,
      dashboardService,
    );
    await setupService.initialize();
  });

  tearDown(() async {
    // Clean up storage service after tests
    await storageService.clearAllData();
  });

  testWidgets('App launches with splash screen', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(ZedDisplayApp(
      storageService: storageService,
      signalKService: signalKService,
      dashboardService: dashboardService,
      toolService: toolService,
      authService: authService,
      setupService: setupService,
      notificationService: notificationService,
      foregroundService: foregroundService,
    ));

    // Verify that the app launches
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('Services are initialized', (WidgetTester tester) async {
    await tester.pumpWidget(ZedDisplayApp(
      storageService: storageService,
      signalKService: signalKService,
      dashboardService: dashboardService,
      toolService: toolService,
      authService: authService,
      setupService: setupService,
      notificationService: notificationService,
      foregroundService: foregroundService,
    ));

    // Verify services are initialized
    expect(storageService.initialized, isTrue);
    expect(toolService.initialized, isTrue);
    expect(dashboardService.initialized, isTrue);
  });
}
