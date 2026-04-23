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
import 'package:zed_display/services/cpa_alert_service.dart';
import 'package:zed_display/services/find_home_target_service.dart';
import 'package:zed_display/services/dashboard_store_service.dart';
import 'package:zed_display/services/chart_tile_cache_service.dart';
import 'package:zed_display/services/chart_tile_server_service.dart';
import 'package:zed_display/services/chart_download_manager.dart';
import 'package:zed_display/services/route_planner_auth_service.dart';
import 'package:zed_display/services/route_planner_boats_service.dart';
import 'package:zed_display/services/weather_routing_service.dart';

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
  late CpaAlertService cpaAlertService;
  late FindHomeTargetService findHomeTargetService;
  late DashboardStoreService dashboardStoreService;
  late ChartTileCacheService chartTileCacheService;
  late ChartTileServerService chartTileServerService;
  late ChartDownloadManager chartDownloadManager;
  late RoutePlannerAuthService routePlannerAuthService;
  late WeatherRoutingService weatherRoutingService;
  late RoutePlannerBoatsService routePlannerBoatsService;

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

    // Initialize CPA alert service
    cpaAlertService = CpaAlertService(
      signalKService: signalKService,
      notificationService: notificationService,
      messagingService: messagingService,
      storageService: storageService,
      alertCoordinator: alertCoordinator,
    );

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

    // Initialize chart tile cache + proxy + download manager. We
    // construct them like main.dart but skip `tileServerService.start()`
    // — opening a loopback socket inside the test runner is fragile and
    // the widget under test doesn't need it to render.
    chartTileCacheService = ChartTileCacheService();
    await chartTileCacheService.initialize();
    chartTileServerService =
        ChartTileServerService(cacheService: chartTileCacheService);
    chartDownloadManager =
        ChartDownloadManager(cacheService: chartTileCacheService);

    // Route planner auth + weather routing (no network in tests)
    routePlannerAuthService = RoutePlannerAuthService(storageService);
    weatherRoutingService = WeatherRoutingService(routePlannerAuthService);
    routePlannerBoatsService = RoutePlannerBoatsService(
      auth: routePlannerAuthService,
      storage: storageService,
    );
  });

  tearDown(() async {
    // Clean up storage service after tests
    await storageService.clearAllData();
    // Close Hive boxes opened by ChartTileCacheService.initialize()
    // so they don't leak across tests or interfere with other Hive
    // state in the next setUp.
    chartTileCacheService.dispose();
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
      cpaAlertService: cpaAlertService,
      findHomeTargetService: findHomeTargetService,
      dashboardStoreService: dashboardStoreService,
      chartTileCacheService: chartTileCacheService,
      chartTileServerService: chartTileServerService,
      chartDownloadManager: chartDownloadManager,
      routePlannerAuthService: routePlannerAuthService,
      weatherRoutingService: weatherRoutingService,
      routePlannerBoatsService: routePlannerBoatsService,
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
      cpaAlertService: cpaAlertService,
      findHomeTargetService: findHomeTargetService,
      dashboardStoreService: dashboardStoreService,
      chartTileCacheService: chartTileCacheService,
      chartTileServerService: chartTileServerService,
      chartDownloadManager: chartDownloadManager,
      routePlannerAuthService: routePlannerAuthService,
      weatherRoutingService: weatherRoutingService,
      routePlannerBoatsService: routePlannerBoatsService,
    ));

    // Verify services are initialized
    expect(storageService.initialized, isTrue);
    expect(toolService.initialized, isTrue);
    expect(dashboardService.initialized, isTrue);
  });
}
