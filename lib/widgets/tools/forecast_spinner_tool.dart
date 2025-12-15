import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/color_extensions.dart';
import '../../utils/conversion_utils.dart';
import '../forecast_spinner.dart';
import '../weatherflow_forecast.dart';

/// Config-driven Forecast Spinner tool
class ForecastSpinnerTool extends StatelessWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const ForecastSpinnerTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  // Default paths for WeatherFlow data (same as WeatherFlowForecastTool)
  static const _defaultPaths = [
    'environment.outside.tempest.observations.airTemperature',      // 0: current temp (for unit reference)
    'environment.outside.tempest.forecast.hourly',                  // 1: hourly forecast base path
  ];

  // Sun/Moon paths from derived-data
  static const _sunlightBasePath = 'environment.sunlight.times';
  static const _moonBasePath = 'environment.moon';

  /// Get path at index, using default if not configured
  String _getPath(int index) {
    if (config.dataSources.length > index && config.dataSources[index].path.isNotEmpty) {
      return config.dataSources[index].path;
    }
    return _defaultPaths[index];
  }

  @override
  Widget build(BuildContext context) {
    final style = config.style;

    // Parse color from config
    final primaryColor = style.primaryColor?.toColor(
      fallback: Colors.blue,
    ) ?? Colors.blue;

    // Get unit symbols
    final tempUnit = signalKService.getUnitSymbol(_getPath(0)) ?? '°F';
    final windUnit = signalKService.getUnitSymbol('environment.outside.tempest.forecast.hourly.windAvg.0') ?? 'kn';
    final pressureUnit = signalKService.getUnitSymbol('environment.outside.tempest.forecast.hourly.seaLevelPressure.0') ?? 'hPa';

    // Get hourly forecasts (up to 72 hours)
    final hoursToShow = style.customProperties?['hoursToShow'] as int? ?? 72;
    final hourlyBasePath = _getPath(1);
    final hourlyForecasts = _getHourlyForecasts(hourlyBasePath, hoursToShow);

    // Get sun/moon times
    final sunMoonTimes = _getSunMoonTimes();

    return ForecastSpinner(
      hourlyForecasts: hourlyForecasts,
      sunMoonTimes: sunMoonTimes,
      tempUnit: tempUnit,
      windUnit: windUnit,
      pressureUnit: pressureUnit,
      primaryColor: primaryColor,
    );
  }

  /// Get string value from SignalK path
  String? _getStringValue(String path) {
    final data = signalKService.getValue(path);
    if (data?.value is String) {
      return data!.value as String;
    }
    return null;
  }

  /// Get DateTime value from SignalK path (ISO string format)
  DateTime? _getDateTimeValue(String path) {
    final data = signalKService.getValue(path);
    if (data?.value is String) {
      return DateTime.tryParse(data!.value as String);
    }
    return null;
  }

  /// Get numeric value from SignalK path
  double? _getNumericValue(String path) {
    final data = signalKService.getValue(path);
    if (data?.value is num) {
      return (data!.value as num).toDouble();
    }
    return null;
  }

  /// Build SunMoonTimes from SignalK derived-data
  /// Loads data for today and future days from SignalK
  SunMoonTimes _getSunMoonTimes() {
    final days = <DaySunTimes>[];

    // Load up to 5 days of sun/moon data (today + 4 future days)
    for (int i = 0; i < 5; i++) {
      // Day 0 (today) has no index prefix, others use .1., .2., etc.
      final sunPrefix = i == 0 ? _sunlightBasePath : '$_sunlightBasePath.$i';
      final moonPrefix = i == 0 ? _moonBasePath : '$_moonBasePath.$i';

      final sunrise = _getDateTimeValue('$sunPrefix.sunrise');
      final sunset = _getDateTimeValue('$sunPrefix.sunset');

      // Only add day if we have at least sunrise or sunset data
      if (sunrise != null || sunset != null) {
        days.add(DaySunTimes(
          sunrise: sunrise,
          sunset: sunset,
          dawn: _getDateTimeValue('$sunPrefix.dawn'),
          dusk: _getDateTimeValue('$sunPrefix.dusk'),
          nauticalDawn: _getDateTimeValue('$sunPrefix.nauticalDawn'),
          nauticalDusk: _getDateTimeValue('$sunPrefix.nauticalDusk'),
          solarNoon: _getDateTimeValue('$sunPrefix.solarNoon'),
          goldenHour: _getDateTimeValue('$sunPrefix.goldenHour'),
          goldenHourEnd: _getDateTimeValue('$sunPrefix.goldenHourEnd'),
          night: _getDateTimeValue('$sunPrefix.night'),
          nightEnd: _getDateTimeValue('$sunPrefix.nightEnd'),
          moonrise: _getDateTimeValue('$moonPrefix.times.rise'),
          moonset: _getDateTimeValue('$moonPrefix.times.set'),
        ));
      } else if (i > 0) {
        // Stop if we hit a day with no data (beyond today)
        break;
      }
    }

    return SunMoonTimes(
      days: days,
      moonPhase: _getNumericValue('$_moonBasePath.phase'),
      moonFraction: _getNumericValue('$_moonBasePath.fraction'),
      moonAngle: _getNumericValue('$_moonBasePath.angle'),
    );
  }

  /// Build list of hourly forecasts from indexed SignalK paths
  List<HourlyForecast> _getHourlyForecasts(String basePath, int count) {
    final forecasts = <HourlyForecast>[];

    for (int i = 0; i < count && i < 72; i++) {
      final temp = ConversionUtils.getConvertedValue(signalKService, '$basePath.airTemperature.$i');
      final feelsLike = ConversionUtils.getConvertedValue(signalKService, '$basePath.feelsLike.$i');
      final conditions = _getStringValue('$basePath.conditions.$i');
      final icon = _getStringValue('$basePath.icon.$i');
      final precipProb = ConversionUtils.getConvertedValue(signalKService, '$basePath.precipProbability.$i');
      final humidity = ConversionUtils.getConvertedValue(signalKService, '$basePath.relativeHumidity.$i');
      final pressure = ConversionUtils.getConvertedValue(signalKService, '$basePath.seaLevelPressure.$i');
      final windSpeed = ConversionUtils.getConvertedValue(signalKService, '$basePath.windAvg.$i');
      final windDirection = ConversionUtils.getConvertedValue(signalKService, '$basePath.windDirection.$i');

      // Only add if we have at least temperature or conditions
      if (temp != null || conditions != null) {
        forecasts.add(HourlyForecast(
          hour: i,
          temperature: temp,
          feelsLike: feelsLike,
          conditions: conditions,
          icon: icon,
          precipProbability: precipProb,
          humidity: humidity,
          pressure: pressure,
          windSpeed: windSpeed,
          windDirection: windDirection,
        ));
      }
    }

    return forecasts;
  }
}

/// Builder for Forecast Spinner tool
class ForecastSpinnerToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'forecast_spinner',
      name: 'Forecast Spinner',
      description: 'Circular dial to explore hourly forecast by spinning',
      category: ToolCategory.weather,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: true,
        minPaths: 0,
        maxPaths: 10,
        styleOptions: const [
          'primaryColor',
          'hoursToShow',
        ],
      ),
    );
  }

  @override
  ToolConfig? getDefaultConfig(String vesselId) {
    return ToolConfig(
      vesselId: vesselId,
      dataSources: [
        DataSource(path: 'environment.outside.tempest.observations.airTemperature', label: 'Temperature'),
        DataSource(path: 'environment.outside.tempest.forecast.hourly', label: 'Hourly Forecast'),
        // Sun times for today and future days
        DataSource(path: 'environment.sunlight.times', label: 'Sun Times Today'),
        DataSource(path: 'environment.sunlight.times.1', label: 'Sun Times Day 1'),
        DataSource(path: 'environment.sunlight.times.2', label: 'Sun Times Day 2'),
        DataSource(path: 'environment.sunlight.times.3', label: 'Sun Times Day 3'),
        // Moon data
        DataSource(path: 'environment.moon', label: 'Moon Data'),
      ],
      style: StyleConfig(
        primaryColor: '#2196F3',
        customProperties: {
          'hoursToShow': 72,
        },
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return ForecastSpinnerTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
