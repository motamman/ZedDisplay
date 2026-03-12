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
import 'package:zed_display/services/crew_service.dart';
import 'package:zed_display/services/messaging_service.dart';
import 'package:zed_display/services/file_share_service.dart';
import 'package:zed_display/services/file_server_service.dart';
import 'package:zed_display/services/intercom_service.dart';
import 'package:zed_display/services/alert_coordinator.dart';
import 'package:zed_display/services/notification_navigation_service.dart';
import 'package:zed_display/services/ais_favorites_service.dart';
import 'package:zed_display/services/find_home_target_service.dart';
import 'package:zed_display/services/dashboard_store_service.dart';

void main() {
  late StorageService storageService;
  late SignalKService signalKService;
  late DashboardService dashboardService;
  late ToolService toolService;
  late AuthService authService;
  late SetupService setupService;
  late NotificationService notificationService;
  late ForegroundTaskService foregroundService;
  late CrewService crewService;
  late MessagingService messagingService;
  late FileServerService fileServerService;
  late FileShareService fileShareService;
  late IntercomService intercomService;
  late AlertCoordinator alertCoordinator;
  late NotificationNavigationService notificationNavigationService;
  late AISFavoritesService aisFavoritesService;
  late FindHomeTargetService findHomeTargetService;
  late DashboardStoreService dashboardStoreService;

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
    signalKService = SignalKService(storageService: storageService);

    // Initialize crew service
    crewService = CrewService(signalKService, storageService);
    await crewService.initialize();

    // Initialize messaging service
    messagingService = MessagingService(signalKService, storageService, crewService);
    await messagingService.initialize();

    // Initialize file server service
    fileServerService = FileServerService();

    // Initialize file share service
    fileShareService = FileShareService(signalKService, storageService, crewService, fileServerService);
    await fileShareService.initialize();

    // Initialize intercom service
    intercomService = IntercomService(signalKService, storageService, crewService);
    await intercomService.initialize();

    // Initialize dashboard service
    dashboardService = DashboardService(
      storageService,
      signalKService,
      toolService,
    );
    await dashboardService.initialize();

    // Initialize auth service
    authService = AuthService(storageService);

    // Initialize alert coordinator
    alertCoordinator = AlertCoordinator(
      storageService: storageService,
      notificationService: notificationService,
      messagingService: messagingService,
    );

    // Initialize notification navigation service
    notificationNavigationService = NotificationNavigationService(dashboardService);

    // Initialize AIS favorites service
    aisFavoritesService = AISFavoritesService();
    aisFavoritesService.loadFromStorage(storageService);

    // Initialize Find Home target service
    findHomeTargetService = FindHomeTargetService();

    // Initialize dashboard store service
    dashboardStoreService = DashboardStoreService(signalKService);

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
      crewService: crewService,
      messagingService: messagingService,
      fileShareService: fileShareService,
      intercomService: intercomService,
      alertCoordinator: alertCoordinator,
      notificationNavigationService: notificationNavigationService,
      aisFavoritesService: aisFavoritesService,
      findHomeTargetService: findHomeTargetService,
      dashboardStoreService: dashboardStoreService,
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
      crewService: crewService,
      messagingService: messagingService,
      fileShareService: fileShareService,
      intercomService: intercomService,
      alertCoordinator: alertCoordinator,
      notificationNavigationService: notificationNavigationService,
      aisFavoritesService: aisFavoritesService,
      findHomeTargetService: findHomeTargetService,
      dashboardStoreService: dashboardStoreService,
    ));

    // Verify services are initialized
    expect(storageService.initialized, isTrue);
    expect(toolService.initialized, isTrue);
    expect(dashboardService.initialized, isTrue);
  });
}
