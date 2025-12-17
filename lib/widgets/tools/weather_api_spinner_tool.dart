import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/weather_api_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/color_extensions.dart';
import '../../utils/conversion_utils.dart';
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

      _weatherService = WeatherApiService(widget.signalKService, provider: provider, forecastDays: forecastDays);
      _weatherService!.addListener(_onDataChanged);

      // Fetch unit categories for fallback conversions
      ConversionUtils.fetchCategories(widget.signalKService);

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

  /// Dynamically subscribe to sun/moon paths based on forecast days
  void _subscribeSunMoonPaths(int forecastDays) {
    final paths = <String>[
      'environment.sunlight.times',  // Today
      'environment.moon',            // Moon data
      'navigation.position',         // Position for weather API
    ];

    // Add paths for each additional forecast day (today is base path, .1 is tomorrow, etc.)
    for (int i = 1; i < forecastDays; i++) {
      paths.add('environment.sunlight.times.$i');
      paths.add('environment.moon.$i');
    }

    debugPrint('WeatherSpinner: Subscribing to ${paths.length} sun/moon paths for $forecastDays days');
    widget.signalKService.subscribeToPaths(paths);

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

  // Build conversion path based on provider source
  String _getConversionPath(String field) {
    final provider = _weatherService?.provider;
    String source = 'meteoblue'; // default
    if (provider != null && provider.startsWith('signalk-')) {
      source = provider.substring(8); // remove "signalk-" prefix
    } else if (provider != null && provider.isNotEmpty) {
      source = provider;
    }
    // Normalize provider names to match SignalK conversion paths
    if (source == 'weatherflow') {
      source = 'tempest';
    } else if (source == 'open-meteo') {
      source = 'openmeteo'; // SignalK path uses no hyphen
    }
    return 'environment.outside.$source.forecast.hourly.$field.0';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final style = widget.config.style;

    // Parse color from config
    final primaryColor = style.primaryColor?.toColor(
      fallback: Colors.blue,
    ) ?? Colors.blue;

    // Get unit symbols from SignalK conversions (with fallback to server preferences)
    var tempUnit = widget.signalKService.getUnitSymbol(_getConversionPath('airTemperature')) ?? '';
    var windUnit = widget.signalKService.getUnitSymbol(_getConversionPath('windAvg')) ?? '';
    var pressureUnit = widget.signalKService.getUnitSymbol(_getConversionPath('seaLevelPressure')) ?? '';

    // Use fallback symbols if no conversion available
    if (tempUnit.isEmpty) {
      tempUnit = ConversionUtils.getWeatherUnitSymbol(WeatherFieldType.temperature);
    }
    if (windUnit.isEmpty) {
      windUnit = ConversionUtils.getWeatherUnitSymbol(WeatherFieldType.speed);
    }
    if (pressureUnit.isEmpty) {
      pressureUnit = ConversionUtils.getWeatherUnitSymbol(WeatherFieldType.pressure);
    }

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

    final showWeatherAnimation = widget.config.style.customProperties?['showWeatherAnimation'] as bool? ?? true;

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
        ),
        // Refresh button with loading/success indicator
        Positioned(
          top: 4,
          right: 4,
          child: SizedBox(
            width: 32,
            height: 32,
            child: weatherService.isLoading
                ? Padding(
                    padding: const EdgeInsets.all(6),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: primaryColor.withValues(alpha: 0.7),
                    ),
                  )
                : _RefreshButton(
                    primaryColor: primaryColor,
                    onRefresh: () => weatherService.fetchForecasts(force: true),
                  ),
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

  /// Convert a value using standard conversions, with fallback to weather-specific conversions
  double? _convertWithFallback(SignalKService service, String path, double rawValue, WeatherFieldType fieldType) {
    // Try standard conversion first
    final converted = ConversionUtils.convertValue(service, path, rawValue);

    // If conversion returned the raw value unchanged (no conversion available),
    // use fallback weather conversions based on server preferences
    if (converted == rawValue) {
      return ConversionUtils.convertWeatherValue(service, fieldType, rawValue);
    }

    return converted;
  }

  /// Convert WeatherApiForecast to HourlyForecast for the spinner
  /// Uses ConversionUtils to apply the same unit conversions as WeatherFlow spinner
  List<HourlyForecast> _buildHourlyForecasts() {
    final forecasts = <HourlyForecast>[];
    final weatherService = _weatherService;
    if (weatherService == null) return forecasts;

    final now = DateTime.now();
    final service = widget.signalKService;

    for (int i = 0; i < weatherService.hourlyForecasts.length; i++) {
      final apiFC = weatherService.hourlyForecasts[i];

      // Calculate hour offset from now
      final hoursFromNow = apiFC.time.difference(now).inMinutes / 60.0;
      if (hoursFromNow < -1) continue; // Skip past forecasts

      // Apply conversions using ConversionUtils
      // Raw values from API are in SI units (Kelvin, Pa, m/s, radians, ratios)
      // Use fallback conversions if standard conversions return unchanged value
      final temp = apiFC.airTemperature != null
          ? _convertWithFallback(service, _getConversionPath('airTemperature'), apiFC.airTemperature!, WeatherFieldType.temperature)
          : null;
      final feelsLike = apiFC.feelsLike != null
          ? _convertWithFallback(service, _getConversionPath('airTemperature'), apiFC.feelsLike!, WeatherFieldType.temperature)
          : null;
      final windSpeed = apiFC.windAvg != null
          ? _convertWithFallback(service, _getConversionPath('windAvg'), apiFC.windAvg!, WeatherFieldType.speed)
          : null;
      final windDir = apiFC.windDirection != null
          ? _convertWithFallback(service, _getConversionPath('windDirection'), apiFC.windDirection!, WeatherFieldType.angle)
          : null;
      final pressure = apiFC.pressure != null
          ? _convertWithFallback(service, _getConversionPath('seaLevelPressure'), apiFC.pressure!, WeatherFieldType.pressure)
          : null;
      final humidity = apiFC.relativeHumidity != null
          ? _convertWithFallback(service, _getConversionPath('relativeHumidity'), apiFC.relativeHumidity!, WeatherFieldType.percentage)
          : null;
      final precipProb = apiFC.precipProbability != null
          ? _convertWithFallback(service, _getConversionPath('precipProbability'), apiFC.precipProbability!, WeatherFieldType.percentage)
          : null;

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
        windDirection: windDir,
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
  final Color primaryColor;
  final VoidCallback onRefresh;

  const _RefreshButton({
    required this.primaryColor,
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
    return IconButton(
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _showSuccess
            ? Icon(
                Icons.check_circle,
                key: const ValueKey('check'),
                size: 18,
                color: Colors.green.shade400,
              )
            : Icon(
                Icons.refresh,
                key: const ValueKey('refresh'),
                size: 18,
                color: widget.primaryColor.withValues(alpha: 0.7),
              ),
      ),
      onPressed: _showSuccess ? null : _handleRefresh,
      tooltip: 'Refresh forecast',
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
    );
  }
}
