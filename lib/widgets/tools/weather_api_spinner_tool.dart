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

class _WeatherApiSpinnerToolState extends State<WeatherApiSpinnerTool> {
  WeatherApiService? _weatherService;
  bool _fetchScheduled = false;

  @override
  void initState() {
    super.initState();
    _initService();
  }

  void _initService() {
    // Get provider from config
    final provider = widget.config.style.customProperties?['provider'] as String?;

    _weatherService = WeatherApiService(widget.signalKService, provider: provider);
    _weatherService!.addListener(_onDataChanged);
    // Delay first fetch to allow position data to arrive
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && !_fetchScheduled) {
        _fetchScheduled = true;
        _weatherService?.fetchForecasts();
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
    if (mounted) {
      setState(() {});
    }
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
    final style = widget.config.style;

    // Parse color from config
    final primaryColor = style.primaryColor?.toColor(
      fallback: Colors.blue,
    ) ?? Colors.blue;

    // Get unit symbols from SignalK conversions
    final tempUnit = widget.signalKService.getUnitSymbol(_getConversionPath('airTemperature')) ?? '';
    final windUnit = widget.signalKService.getUnitSymbol(_getConversionPath('windAvg')) ?? '';
    final pressureUnit = widget.signalKService.getUnitSymbol(_getConversionPath('seaLevelPressure')) ?? '';

    // Convert API forecasts to HourlyForecast objects using ConversionUtils
    final hourlyForecasts = _buildHourlyForecasts();

    // Get sun/moon times from SignalK (derived-data plugin)
    final sunMoonTimes = _getSunMoonTimes();

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

    return ForecastSpinner(
      hourlyForecasts: hourlyForecasts,
      sunMoonTimes: sunMoonTimes,
      tempUnit: tempUnit,
      windUnit: windUnit,
      pressureUnit: pressureUnit,
      primaryColor: primaryColor,
      providerName: _getProviderDisplayName(),
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
      final temp = apiFC.airTemperature != null
          ? ConversionUtils.convertValue(service, _getConversionPath('airTemperature'), apiFC.airTemperature!)
          : null;
      final feelsLike = apiFC.feelsLike != null
          ? ConversionUtils.convertValue(service, _getConversionPath('airTemperature'), apiFC.feelsLike!)
          : null;
      final windSpeed = apiFC.windAvg != null
          ? ConversionUtils.convertValue(service, _getConversionPath('windAvg'), apiFC.windAvg!)
          : null;
      final windDir = apiFC.windDirection != null
          ? ConversionUtils.convertValue(service, _getConversionPath('windDirection'), apiFC.windDirection!)
          : null;
      final pressure = apiFC.pressure != null
          ? ConversionUtils.convertValue(service, _getConversionPath('seaLevelPressure'), apiFC.pressure!)
          : null;
      final humidity = apiFC.relativeHumidity != null
          ? ConversionUtils.convertValue(service, _getConversionPath('relativeHumidity'), apiFC.relativeHumidity!)
          : null;
      final precipProb = apiFC.precipProbability != null
          ? ConversionUtils.convertValue(service, _getConversionPath('precipProbability'), apiFC.precipProbability!)
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

    // Load up to 5 days of sun/moon data
    for (int i = 0; i < 5; i++) {
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
      category: ToolCategory.display,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: true,
        minPaths: 0,
        maxPaths: 10,
        styleOptions: const [
          'primaryColor',
          'provider',
        ],
      ),
    );
  }

  @override
  ToolConfig? getDefaultConfig(String vesselId) {
    return ToolConfig(
      vesselId: vesselId,
      dataSources: [
        // Sun times for coloring (from derived-data plugin)
        DataSource(path: 'environment.sunlight.times', label: 'Sun Times Today'),
        DataSource(path: 'environment.sunlight.times.1', label: 'Sun Times Day 1'),
        DataSource(path: 'environment.sunlight.times.2', label: 'Sun Times Day 2'),
        DataSource(path: 'environment.sunlight.times.3', label: 'Sun Times Day 3'),
        // Moon data
        DataSource(path: 'environment.moon', label: 'Moon Data'),
        // Position for weather API
        DataSource(path: 'navigation.position', label: 'Vessel Position'),
      ],
      style: StyleConfig(
        primaryColor: '#2196F3',
        customProperties: {
          // Weather API provider (e.g., 'signalk-weatherflow', 'signalk-openweather')
          // Leave empty to use default/first available provider
          'provider': '',
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
