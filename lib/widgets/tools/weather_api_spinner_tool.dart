import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/weather_api_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/color_extensions.dart';
import '../forecast_spinner.dart';
import '../weatherflow_forecast.dart';


/// Generic Weather API Spinner tool
/// Uses SignalK Weather API (/signalk/v2/api/weather/forecasts/point)
/// Works with any weather provider implementing the SignalK Weather API
class WeatherApiSpinnerTool extends StatefulWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const WeatherApiSpinnerTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  @override
  State<WeatherApiSpinnerTool> createState() => _WeatherApiSpinnerToolState();
}

class _WeatherApiSpinnerToolState extends State<WeatherApiSpinnerTool>
    with AutomaticKeepAliveClientMixin {
  WeatherApiService? _weatherService;
  bool _fetchScheduled = false;

  // Cached hourly forecasts to avoid rebuilding on every setState
  List<HourlyForecast>? _cachedForecasts;
  int? _lastForecastCount;

  // Cached sun/moon times to avoid recalculating every build
  SunMoonTimes? _cachedSunMoonTimes;

  @override
  bool get wantKeepAlive => true; // Keep state alive when scrolled off screen

  @override
  void initState() {
    super.initState();
    // Delay initialization to avoid issues during placement preview
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initService();
    });
  }

  void _initService() {
    try {
      // Get provider from config
      final provider = widget.config.style.customProperties?['provider'] as String?;
      // Get forecast days from config (default: 5 days)
      final forecastDays = widget.config.style.customProperties?['forecastDays'] as int? ?? 5;

      // Dynamically subscribe to sun/moon paths based on forecastDays
      _subscribeSunMoonPaths(forecastDays);

      // Rebuild when MetadataStore changes (e.g. server-pushed
      // displayUnits delta after a units-preference change). Drops the
      // hourly-forecast cache so the new symbols/formulas take effect
      // immediately without waiting for a fresh API fetch.
      widget.signalKService.metadataStore.addListener(_onMetadataChanged);

      _weatherService = WeatherApiService(widget.signalKService, provider: provider, forecastDays: forecastDays);
      _weatherService!.addListener(_onDataChanged);

      // Delay first fetch to allow position data to arrive
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && !_fetchScheduled) {
          _fetchScheduled = true;
          _weatherService?.fetchForecasts();
        }
      });
    } catch (e) {
      debugPrint('WeatherApiSpinnerTool init error: $e');
    }
  }

  /// Drop the cached hourly forecasts and rebuild when MetadataStore
  /// changes — covers live displayUnits updates pushed by the server
  /// after a units-preference change.
  void _onMetadataChanged() {
    if (!mounted) return;
    setState(() {
      _cachedForecasts = null;
    });
  }

  /// Subscribe to the leaf sun/moon paths the spinner reads.
  ///
  /// SignalK subscriptions are exact-path — subscribing to a parent
  /// like `environment.sunlight.times` does NOT cover its children,
  /// because the parent itself has no value (the values live on
  /// leaves like `environment.sunlight.times.sunrise`). Subscribe to
  /// each leaf explicitly so the WebSocket actually delivers the
  /// values, then `_getSunMoonTimes` can read them from the cache.
  void _subscribeSunMoonPaths(int forecastDays) {
    // Leaves consumed by `_getSunMoonTimes()` (keep in sync if that
    // method grows). One set per day; today is the unsuffixed base
    // path, days N≥1 use `.N` between the base path and the leaf
    // key (`environment.sunlight.times.1.sunrise`).
    const sunLeaves = [
      'sunrise',
      'sunset',
      'dawn',
      'dusk',
      'nauticalDawn',
      'nauticalDusk',
      'solarNoon',
      'goldenHour',
      'goldenHourEnd',
      'night',
      'nightEnd',
    ];
    const moonLeaves = [
      'times.rise',
      'times.set',
      'phase',
      'fraction',
      'angle',
    ];

    final paths = <String>[
      'navigation.position', // Position for weather API
    ];
    for (int i = 0; i < forecastDays; i++) {
      final sunBase =
          i == 0 ? 'environment.sunlight.times' : 'environment.sunlight.times.$i';
      final moonBase = i == 0 ? 'environment.moon' : 'environment.moon.$i';
      for (final leaf in sunLeaves) {
        paths.add('$sunBase.$leaf');
      }
      for (final leaf in moonLeaves) {
        paths.add('$moonBase.$leaf');
      }
    }

    debugPrint(
        'WeatherSpinner: Subscribing to ${paths.length} sun/moon leaf paths for $forecastDays days');
    widget.signalKService.subscribeToPaths(paths, ownerId: 'weather_spinner');

    // Refresh sun/moon times after data arrives via WebSocket
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        debugPrint('WeatherSpinner: Refreshing sun/moon times after delay');
        setState(() {
          _cachedSunMoonTimes = _getSunMoonTimes();
        });
        debugPrint('WeatherSpinner: Got ${_cachedSunMoonTimes?.days.length ?? 0} days of sun/moon data');
      }
    });
  }

  @override
  void dispose() {
    widget.signalKService.metadataStore.removeListener(_onMetadataChanged);
    _weatherService?.removeListener(_onDataChanged);
    _weatherService?.release();
    _weatherService = null;
    super.dispose();
  }

  void _onDataChanged() {
    if (!mounted) return;

    // Only rebuild forecasts if the data actually changed
    final newCount = _weatherService?.hourlyForecasts.length;
    if (newCount != _lastForecastCount) {
      _cachedForecasts = _buildHourlyForecasts();
      _lastForecastCount = newCount;
      // Also update sun/moon times when forecast data changes
      _cachedSunMoonTimes = _getSunMoonTimes();
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final style = widget.config.style;

    // Parse color from config
    final primaryColor = style.primaryColor?.toColor(
      fallback: Colors.blue,
    ) ?? Colors.blue;

    // Symbols come from MetadataStore.getByCategory — populated by live
    // WebSocket meta deltas and the connect-time preset seeding. Empty
    // strings until the store has an entry for the category.
    final store = widget.signalKService.metadataStore;
    final tempUnit = store.getByCategory('temperature')?.symbol ?? '';
    final windUnit = store.getByCategory('speed')?.symbol ?? '';
    final pressureUnit = store.getByCategory('pressure')?.symbol ?? '';

    // Use cached forecasts (updated in _onDataChanged)
    // Always rebuild if cache is empty but service has data (handles swipe away/back)
    final serviceHasData = (_weatherService?.hourlyForecasts.length ?? 0) > 0;
    if (_cachedForecasts == null || (_cachedForecasts!.isEmpty && serviceHasData)) {
      _cachedForecasts = _buildHourlyForecasts();
      _lastForecastCount = _weatherService?.hourlyForecasts.length;
      _cachedSunMoonTimes = _getSunMoonTimes();
    }
    final hourlyForecasts = _cachedForecasts ?? [];
    final sunMoonTimes = _cachedSunMoonTimes;

    final weatherService = _weatherService;

    // Show loading or error state
    if (weatherService == null || (weatherService.isLoading && hourlyForecasts.isEmpty)) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: primaryColor),
            const SizedBox(height: 16),
            Text(
              'Loading weather...',
              style: TextStyle(color: primaryColor),
            ),
          ],
        ),
      );
    }

    if (weatherService.errorMessage != null && hourlyForecasts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              weatherService.errorMessage!,
              style: const TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => weatherService.fetchForecasts(force: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (hourlyForecasts.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_queue, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No forecast data available',
              style: TextStyle(color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Weather API may not be enabled',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }

    final cp = widget.config.style.customProperties ?? const {};
    final showWeatherAnimation = cp['showWeatherAnimation'] as bool? ?? true;
    // Default the new centre modes ON so the ported wind display is
    // visible without requiring a customProperties edit. Tap the
    // centre disc to cycle through modes; dots at the bottom show
    // which mode is active.
    final showWindCenter = cp['showWindCenter'] as bool? ?? true;
    final showSunMoonIcons = cp['showSunMoonIcons'] as bool? ?? true;
    final showTimeOverlay = cp['showTimeOverlay'] as bool? ?? true;
    // Solar centre hidden until a configured provider exposes
    // irradiance — `WeatherApiForecast.irradianceWm2` is null for the
    // current Open-Meteo mapping, so the centre would always show the
    // "No solar output" fallback. Plumbing in
    // `forecast_spinner._buildSolarCenter` + `WeatherApiService`'s
    // `irradiance` parse stays so re-enabling is a one-line flip.
    const showSolarCenter = false;
    final panelMaxWatts = (cp['panelMaxWatts'] as num?)?.toDouble();
    final systemDerate = (cp['systemDerate'] as num?)?.toDouble();

    return Stack(
      children: [
        ForecastSpinner(
          hourlyForecasts: hourlyForecasts,
          sunMoonTimes: sunMoonTimes,
          tempUnit: tempUnit,
          windUnit: windUnit,
          pressureUnit: pressureUnit,
          primaryColor: primaryColor,
          providerName: _getProviderDisplayName(),
          showWeatherAnimation: showWeatherAnimation,
          showWindCenter: showWindCenter,
          showSolarCenter: showSolarCenter,
          showSunMoonIcons: showSunMoonIcons,
          showTimeOverlay: showTimeOverlay,
          panelMaxWatts: panelMaxWatts,
          systemDerate: systemDerate,
        ),
        // Refresh button with loading/success indicator
        Positioned(
          top: 8,
          right: 8,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Refresh button
              SizedBox(
                width: 32,
                height: 32,
                child: weatherService.isLoading
                    ? Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(6),
                        child: const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : _RefreshButton(
                        onRefresh: () => weatherService.fetchForecasts(force: true),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Get a user-friendly provider display name
  String? _getProviderDisplayName() {
    final provider = _weatherService?.provider;
    if (provider == null || provider.isEmpty) return null;

    // Remove 'signalk-' prefix and format nicely
    String name = provider;
    if (name.startsWith('signalk-')) {
      name = name.substring(8);
    }

    // Capitalize and format common provider names
    switch (name.toLowerCase()) {
      case 'open-meteo':
      case 'openmeteo':
        return 'Open-Meteo';
      case 'meteoblue':
        return 'Meteoblue';
      case 'weatherflow':
        return 'WeatherFlow';
      default:
        // Title case the name
        return name.split('-').map((word) =>
          word.isNotEmpty ? '${word[0].toUpperCase()}${word.substring(1)}' : ''
        ).join(' ');
    }
  }

  /// Convert a raw SI value via the live MetadataStore entry for
  /// [category]. Falls through to the raw value when the store has no
  /// usable entry yet — `_onMetadataChanged` will rebuild the cache
  /// when one arrives.
  double? _convertApi(String category, double? rawValue) {
    if (rawValue == null) return null;
    final meta = widget.signalKService.metadataStore.getByCategory(category);
    return meta?.convert(rawValue) ?? rawValue;
  }

  /// Beaufort scale (0-12) from wind speed in m/s. Cutoffs lifted
  /// verbatim from the sister app's `openmeteo_core.HourlyForecast`
  /// so the wind-state centre on this app reads identically. Returns
  /// null for a null input.
  static int? _beaufortFromMps(double? mps) {
    if (mps == null) return null;
    if (mps < 0.5) return 0;
    if (mps < 1.6) return 1;
    if (mps < 3.4) return 2;
    if (mps < 5.5) return 3;
    if (mps < 8.0) return 4;
    if (mps < 10.8) return 5;
    if (mps < 13.9) return 6;
    if (mps < 17.2) return 7;
    if (mps < 20.8) return 8;
    if (mps < 24.5) return 9;
    if (mps < 28.5) return 10;
    if (mps < 32.7) return 11;
    return 12;
  }

  /// Convert WeatherApiForecast to HourlyForecast for the spinner, applying
  /// unit conversions via MetadataStore for the configured provider paths.
  List<HourlyForecast> _buildHourlyForecasts() {
    final forecasts = <HourlyForecast>[];
    final weatherService = _weatherService;
    if (weatherService == null) return forecasts;

    final now = DateTime.now();

    for (int i = 0; i < weatherService.hourlyForecasts.length; i++) {
      final apiFC = weatherService.hourlyForecasts[i];

      // Calculate hour offset from now
      final hoursFromNow = apiFC.time.difference(now).inMinutes / 60.0;
      if (hoursFromNow < -1) continue; // Skip past forecasts

      final temp = _convertApi('temperature', apiFC.airTemperature);
      final feelsLike = _convertApi('temperature', apiFC.feelsLike);
      final windSpeed = _convertApi('speed', apiFC.windAvg);
      // Wind direction is consumed graphically by the spinner (compass
      // labels, arrow rotation), not as a user-facing numeric in the
      // user's preferred angle unit. Convert radians → degrees
      // directly so a non-degree angle preset can't break the visual.
      final windDirDeg = apiFC.windDirection == null
          ? null
          : apiFC.windDirection! * 180.0 / math.pi;
      final pressure = _convertApi('pressure', apiFC.pressure);
      final humidity = _convertApi('percentage', apiFC.relativeHumidity);
      final precipProb = _convertApi('percentage', apiFC.precipProbability);

      forecasts.add(HourlyForecast(
        hour: i,
        temperature: temp,
        feelsLike: feelsLike,
        conditions: apiFC.conditions,
        longDescription: apiFC.longDescription,
        icon: apiFC.icon,
        precipProbability: precipProb,
        humidity: humidity,
        pressure: pressure,
        windSpeed: windSpeed,
        windDirection: windDirDeg,
        beaufort: _beaufortFromMps(apiFC.windAvg),
        irradianceWm2: apiFC.irradianceWm2,
      ));
    }

    return forecasts;
  }

  /// Get sun/moon times from SignalK derived-data
  SunMoonTimes _getSunMoonTimes() {
    const sunlightBasePath = 'environment.sunlight.times';
    const moonBasePath = 'environment.moon';

    final days = <DaySunTimes>[];

    // Load sun/moon data for configured forecast days
    final forecastDays = widget.config.style.customProperties?['forecastDays'] as int? ?? 5;
    for (int i = 0; i < forecastDays; i++) {
      final sunPrefix = i == 0 ? sunlightBasePath : '$sunlightBasePath.$i';
      final moonPrefix = i == 0 ? moonBasePath : '$moonBasePath.$i';

      final sunrise = _getDateTimeValue('$sunPrefix.sunrise');
      final sunset = _getDateTimeValue('$sunPrefix.sunset');
      final goldenHour = _getDateTimeValue('$sunPrefix.goldenHour');
      final goldenHourEnd = _getDateTimeValue('$sunPrefix.goldenHourEnd');
      final solarNoon = _getDateTimeValue('$sunPrefix.solarNoon');

      if (sunrise != null || sunset != null) {
        days.add(DaySunTimes(
          sunrise: sunrise,
          sunset: sunset,
          dawn: _getDateTimeValue('$sunPrefix.dawn'),
          dusk: _getDateTimeValue('$sunPrefix.dusk'),
          nauticalDawn: _getDateTimeValue('$sunPrefix.nauticalDawn'),
          nauticalDusk: _getDateTimeValue('$sunPrefix.nauticalDusk'),
          solarNoon: solarNoon,
          goldenHour: goldenHour,
          goldenHourEnd: goldenHourEnd,
          night: _getDateTimeValue('$sunPrefix.night'),
          nightEnd: _getDateTimeValue('$sunPrefix.nightEnd'),
          moonrise: _getDateTimeValue('$moonPrefix.times.rise'),
          moonset: _getDateTimeValue('$moonPrefix.times.set'),
        ));
      } else if (i > 0) {
        break;
      }
    }

    return SunMoonTimes(
      days: days,
      moonPhase: _getNumericValue('$moonBasePath.phase'),
      moonFraction: _getNumericValue('$moonBasePath.fraction'),
      moonAngle: _getNumericValue('$moonBasePath.angle'),
    );
  }

  DateTime? _getDateTimeValue(String path) {
    final data = widget.signalKService.getValue(path);
    if (data?.value is String) {
      return DateTime.tryParse(data!.value as String);
    }
    return null;
  }

  double? _getNumericValue(String path) {
    final data = widget.signalKService.getValue(path);
    if (data?.value is num) {
      return (data!.value as num).toDouble();
    }
    return null;
  }
}

/// Builder for Weather API Spinner tool
class WeatherApiSpinnerToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'weather_api_spinner',
      name: 'Weather Spinner (API)',
      description: 'Forecast spinner using SignalK Weather API - works with any weather provider',
      category: ToolCategory.weather,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: true,
        minPaths: 0,
        maxPaths: 10,
        styleOptions: const [
          'primaryColor',
          'provider',
          'forecastDays',
        ],
        allowsDataSources: false,
        allowsUnitSelection: false,
        allowsVisibilityToggles: false,
        allowsTTL: false,
      ),
    );
  }

  @override
  ToolConfig? getDefaultConfig(String vesselId) {
    return ToolConfig(
      vesselId: vesselId,
      dataSources: const [],  // Sun/moon paths are dynamically subscribed based on forecastDays
      style: StyleConfig(
        primaryColor: '#2196F3',
        customProperties: {
          // Weather API provider (e.g., 'signalk-weatherflow', 'signalk-openweather')
          // Leave empty to use default/first available provider
          'provider': '',
          // Number of days to fetch forecast for (1-10, default: 5)
          'forecastDays': 5,
        },
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return WeatherApiSpinnerTool(
      config: config,
      signalKService: signalKService,
    );
  }
}

/// Refresh button that shows a brief checkmark after successful refresh
class _RefreshButton extends StatefulWidget {
  final VoidCallback onRefresh;

  const _RefreshButton({
    required this.onRefresh,
  });

  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton> {
  bool _showSuccess = false;

  void _handleRefresh() async {
    widget.onRefresh();
    // Show success indicator after a delay (assumes refresh completes)
    await Future.delayed(const Duration(milliseconds: 1500));
    if (mounted) {
      setState(() => _showSuccess = true);
      await Future.delayed(const Duration(milliseconds: 1200));
      if (mounted) {
        setState(() => _showSuccess = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _showSuccess
              ? Icon(
                  Icons.check_circle,
                  key: const ValueKey('check'),
                  size: 18,
                  color: Colors.green.shade400,
                )
              : const Icon(
                  Icons.refresh,
                  key: ValueKey('refresh'),
                  size: 18,
                  color: Colors.white,
                ),
        ),
        onPressed: _showSuccess ? null : _handleRefresh,
        tooltip: 'Refresh forecast',
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: EdgeInsets.zero,
      ),
    );
  }
}
