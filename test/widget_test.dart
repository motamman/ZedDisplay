import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
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
import 'package:zed_display/services/anchor_alarm_service.dart';
import 'package:zed_display/services/find_home_target_service.dart';
import 'package:zed_display/services/dashboard_store_service.dart';
import 'package:zed_display/services/chart_tile_cache_service.dart';
import 'package:zed_display/services/chart_tile_server_service.dart';
import 'package:zed_display/services/chart_download_manager.dart';
import 'package:zed_display/services/route_planner_auth_service.dart';
import 'package:zed_display/services/route_planner_boats_service.dart';
import 'package:zed_display/services/route_planner_charts_service.dart';
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
  late AnchorAlarmService anchorAlarmService;
  late FindHomeTargetService findHomeTargetService;
  late DashboardStoreService dashboardStoreService;
  late ChartTileCacheService chartTileCacheService;
  late ChartTileServerService chartTileServerService;
  late ChartDownloadManager chartDownloadManager;
  late RoutePlannerAuthService routePlannerAuthService;
  late WeatherRoutingService weatherRoutingService;
  late RoutePlannerBoatsService routePlannerBoatsService;
  late RoutePlannerChartsService routePlannerChartsService;

  late Directory tempDir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // Headless tests have no native plugins. Mock the path_provider channel so
    // StorageService/Hive and the chart/file services get a real on-disk dir,
    // and stub the other plugins touched during setUp/pumpWidget to no-ops.
    tempDir = Directory.systemTemp.createTempSync('zed_widget_test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    // permission_handler: report everything granted (1) so permission gates
    // during service init don't throw headless.
    messenger.setMockMethodCallHandler(
      const MethodChannel('flutter.baseflow.com/permissions/methods'),
      (call) async {
        if (call.method == 'checkPermissionStatus') return 1; // granted
        if (call.method == 'requestPermissions') {
          // Report each requested permission as granted (1), matching
          // checkPermissionStatus — an empty map reads back as denied/unset.
          final perms = (call.arguments as List?)?.cast<int>() ?? const [];
          return {for (final p in perms) p: 1};
        }
        return 1;
      },
    );

    // Initialize storage service for tests
    storageService = StorageService();
    await storageService.initialize();

    // Notification + foreground services wrap native plugins
    // (flutter_local_notifications, flutter_foreground_task) that have no
    // implementation in a headless test. Construct them (the app requires the
    // instances) and attempt init best-effort; the smoke test asserts only the
    // core data services below, which must initialize cleanly.
    notificationService = NotificationService();
    try {
      await notificationService.initialize();
    } catch (e) {
      if (!_isHeadlessPluginFailure(e)) rethrow;
    }

    foregroundService = ForegroundTaskService();
    try {
      await foregroundService.initialize();
    } catch (e) {
      if (!_isHeadlessPluginFailure(e)) rethrow;
    }

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

    // Initialize anchor alarm service (app-level singleton)
    anchorAlarmService = AnchorAlarmService(
      signalKService: signalKService,
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
    weatherRoutingService =
        WeatherRoutingService(routePlannerAuthService, storageService);
    routePlannerBoatsService = RoutePlannerBoatsService(
      auth: routePlannerAuthService,
      storage: storageService,
    );
    routePlannerChartsService =
        RoutePlannerChartsService(auth: routePlannerAuthService);
  });

  tearDown(() async {
    // Clean up storage service after tests
    await storageService.clearAllData();
    // Close every open Hive box (StorageService's + ChartTileCacheService's)
    // and AWAIT it, so no box-close races with the next test's setUp and no
    // async file work outlives the test. The temp dir is left for the OS to
    // reap — deleting it here would race Hive's own lock-file cleanup.
    // Dispose the anchor alarm service too: it sets a static `instance` and
    // registers a coordinator resolve callback in its constructor, which would
    // otherwise leak into the next test's setUp.
    anchorAlarmService.dispose();
    chartTileCacheService.dispose();
    await Hive.close();
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
      anchorAlarmService: anchorAlarmService,
      findHomeTargetService: findHomeTargetService,
      dashboardStoreService: dashboardStoreService,
      chartTileCacheService: chartTileCacheService,
      chartTileServerService: chartTileServerService,
      chartDownloadManager: chartDownloadManager,
      routePlannerAuthService: routePlannerAuthService,
      weatherRoutingService: weatherRoutingService,
      routePlannerBoatsService: routePlannerBoatsService,
      routePlannerChartsService: routePlannerChartsService,
    ));

    // Verify that the app launches
    expect(find.byType(MaterialApp), findsOneWidget);

    await _settleSplash(tester);
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
      anchorAlarmService: anchorAlarmService,
      findHomeTargetService: findHomeTargetService,
      dashboardStoreService: dashboardStoreService,
      chartTileCacheService: chartTileCacheService,
      chartTileServerService: chartTileServerService,
      chartDownloadManager: chartDownloadManager,
      routePlannerAuthService: routePlannerAuthService,
      weatherRoutingService: weatherRoutingService,
      routePlannerBoatsService: routePlannerBoatsService,
      routePlannerChartsService: routePlannerChartsService,
    ));

    // Verify services are initialized
    expect(storageService.initialized, isTrue);
    expect(toolService.initialized, isTrue);
    expect(dashboardService.initialized, isTrue);

    await _settleSplash(tester);
  });
}

/// True for the two benign ways a native plugin's `initialize()` fails when
/// run headless (no platform implementation registered): a
/// [MissingPluginException] from an un-mocked method channel, or a
/// `LateInitializationError` from the plugin's uninitialized platform-interface
/// `instance` field. Anything else is a real regression and should propagate.
bool _isHeadlessPluginFailure(Object e) {
  if (e is MissingPluginException) return true;
  // NOTE: Copilot suggested checking the type directly, but `e is
  // LateInitializationError` does not compile (the type isn't public), and the
  // runtime type is actually `LateError` — only the message string carries the
  // "LateInitializationError" prefix. So matching toString() is the only option.
  return e is Error && e.toString().startsWith('LateInitializationError');
}

/// The splash screen arms two fire-and-forget timers in initState
/// (auto-connect at 500ms, navigate at 2500ms). Pump past both so none are
/// left pending at teardown. No server is saved in the test, so auto-connect
/// no-ops and the app navigates on to the server list.
Future<void> _settleSplash(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(seconds: 1));
}
