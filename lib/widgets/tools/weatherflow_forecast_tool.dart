import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/color_extensions.dart';
import '../../utils/conversion_utils.dart';
import '../weatherflow_forecast.dart';

/// Config-driven WeatherFlow forecast tool
class WeatherFlowForecastTool extends StatelessWidget {
  final ToolConfig config;
  final SignalKService signalKService;

  const WeatherFlowForecastTool({
    super.key,
    required this.config,
    required this.signalKService,
  });

  // Default paths for WeatherFlow data
  static const _defaultPaths = [
    'environment.outside.tempest.observations.airTemperature',      // 0: current temp
    'environment.outside.tempest.observations.relativeHumidity',    // 1: current humidity
    'environment.outside.tempest.observations.stationPressure',     // 2: current pressure
    'environment.outside.tempest.observations.windAvg',             // 3: current wind speed
    'environment.outside.tempest.observations.windGust',            // 4: current wind gust
    'environment.outside.tempest.observations.windDirection',       // 5: current wind direction
    'environment.outside.tempest.forecast.hourly',                  // 6: forecast base path
  ];

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

    // Get custom properties
    final hoursToShow = style.customProperties?['hoursToShow'] as int? ?? 12;
    final showCurrentConditions = style.customProperties?['showCurrentConditions'] as bool? ?? true;

    // Get current observations using ConversionUtils for proper unit handling
    final currentTemp = ConversionUtils.getConvertedValue(signalKService, _getPath(0));
    final currentHumidity = ConversionUtils.getConvertedValue(signalKService, _getPath(1));
    final currentPressure = ConversionUtils.getConvertedValue(signalKService, _getPath(2));
    final currentWindSpeed = ConversionUtils.getConvertedValue(signalKService, _getPath(3));
    final currentWindGust = ConversionUtils.getConvertedValue(signalKService, _getPath(4));
    final currentWindDirection = ConversionUtils.getConvertedValue(signalKService, _getPath(5));

    // Get unit symbols from SignalK service
    final tempUnit = signalKService.getUnitSymbol(_getPath(0)) ?? '°C';
    final pressureUnit = signalKService.getUnitSymbol(_getPath(2)) ?? 'hPa';
    final windUnit = signalKService.getUnitSymbol(_getPath(3)) ?? 'kts';

    // Get hourly forecasts
    final forecastBasePath = _getPath(6);
    final hourlyForecasts = _getHourlyForecasts(forecastBasePath, hoursToShow);

    return WeatherFlowForecast(
      currentTemp: currentTemp,
      currentHumidity: currentHumidity,
      currentPressure: currentPressure,
      currentWindSpeed: currentWindSpeed,
      currentWindGust: currentWindGust,
      currentWindDirection: currentWindDirection,
      tempUnit: tempUnit,
      pressureUnit: pressureUnit,
      windUnit: windUnit,
      hourlyForecasts: hourlyForecasts,
      hoursToShow: hoursToShow,
      primaryColor: primaryColor,
      showCurrentConditions: showCurrentConditions,
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

/// Builder for WeatherFlow forecast tool
class WeatherFlowForecastToolBuilder extends ToolBuilder {
  @override
  ToolDefinition getDefinition() {
    return ToolDefinition(
      id: 'weatherflow_forecast',
      name: 'WeatherFlow Forecast',
      description: 'Weather forecast from WeatherFlow Tempest station',
      category: ToolCategory.display,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: true,
        minPaths: 0,
        maxPaths: 7,
        styleOptions: const [
          'primaryColor',
          'hoursToShow',
          'showCurrentConditions',
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
        DataSource(path: 'environment.outside.tempest.observations.relativeHumidity', label: 'Humidity'),
        DataSource(path: 'environment.outside.tempest.observations.stationPressure', label: 'Pressure'),
        DataSource(path: 'environment.outside.tempest.observations.windAvg', label: 'Wind Speed'),
        DataSource(path: 'environment.outside.tempest.observations.windGust', label: 'Wind Gust'),
        DataSource(path: 'environment.outside.tempest.observations.windDirection', label: 'Wind Dir'),
        DataSource(path: 'environment.outside.tempest.forecast.hourly', label: 'Forecast'),
      ],
      style: StyleConfig(
        primaryColor: '#2196F3',
        customProperties: {
          'hoursToShow': 12,
          'showCurrentConditions': true,
        },
      ),
    );
  }

  @override
  Widget build(ToolConfig config, SignalKService signalKService) {
    return WeatherFlowForecastTool(
      config: config,
      signalKService: signalKService,
    );
  }
}
