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
    'environment.outside.tempest.forecast.hourly',                  // 6: hourly forecast base path
    'environment.outside.tempest.forecast.daily',                   // 7: daily forecast base path
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

    // Get rain data
    const rainLastHourPath = 'environment.outside.tempest.observations.precipTotal1h';
    const rainTodayPath = 'environment.outside.tempest.observations.localDailyRainAccumulation';
    final rainLastHour = ConversionUtils.getConvertedValue(signalKService, rainLastHourPath);
    final rainToday = ConversionUtils.getConvertedValue(signalKService, rainTodayPath);

    // Get unit symbols from SignalK service
    final tempUnit = signalKService.getUnitSymbol(_getPath(0)) ?? '°C';
    final pressureUnit = signalKService.getUnitSymbol(_getPath(2)) ?? 'hPa';
    final windUnit = signalKService.getUnitSymbol(_getPath(3)) ?? 'kts';
    final rainUnit = signalKService.getUnitSymbol(rainLastHourPath) ?? 'mm';

    // Get hourly forecasts
    final hourlyBasePath = _getPath(6);
    final hourlyForecasts = _getHourlyForecasts(hourlyBasePath, hoursToShow);

    // Get daily forecasts
    final dailyBasePath = _getPath(7);
    final daysToShow = style.customProperties?['daysToShow'] as int? ?? 7;
    final dailyForecasts = _getDailyForecasts(dailyBasePath, daysToShow);

    // Get sun/moon times from derived-data
    final sunMoonTimes = _getSunMoonTimes();
    final showSunMoonArc = style.customProperties?['showSunMoonArc'] as bool? ?? true;

    return WeatherFlowForecast(
      currentTemp: currentTemp,
      currentHumidity: currentHumidity,
      currentPressure: currentPressure,
      currentWindSpeed: currentWindSpeed,
      currentWindGust: currentWindGust,
      currentWindDirection: currentWindDirection,
      rainLastHour: rainLastHour,
      rainToday: rainToday,
      tempUnit: tempUnit,
      pressureUnit: pressureUnit,
      windUnit: windUnit,
      rainUnit: rainUnit,
      hourlyForecasts: hourlyForecasts,
      dailyForecasts: dailyForecasts,
      hoursToShow: hoursToShow,
      daysToShow: daysToShow,
      primaryColor: primaryColor,
      showCurrentConditions: showCurrentConditions,
      sunMoonTimes: sunMoonTimes,
      showSunMoonArc: showSunMoonArc,
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
  /// Dynamically loads available days
  SunMoonTimes _getSunMoonTimes() {
    final days = <DaySunTimes>[];

    // Load up to 7 days of sun/moon data
    for (int i = 0; i < 7; i++) {
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
        // Stop if we hit a day with no data
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

  /// Build list of daily forecasts from indexed SignalK paths
  List<DailyForecast> _getDailyForecasts(String basePath, int count) {
    final forecasts = <DailyForecast>[];

    // Get temperature conversion formula from observations path
    final tempPath = _getPath(0);
    final availableUnits = signalKService.getAvailableUnits(tempPath);
    String? tempFormula;
    if (availableUnits.isNotEmpty) {
      final conversionInfo = signalKService.getConversionInfo(tempPath, availableUnits.first);
      tempFormula = conversionInfo?.formula;
    }

    for (int i = 0; i < count && i < 10; i++) {
      // Get raw temp values and apply conversion manually
      final rawTempHigh = _getNumericValue('$basePath.airTempHigh.$i');
      final rawTempLow = _getNumericValue('$basePath.airTempLow.$i');

      double? tempHigh = rawTempHigh;
      double? tempLow = rawTempLow;
      if (tempFormula != null) {
        if (rawTempHigh != null) {
          tempHigh = ConversionUtils.evaluateFormula(tempFormula, rawTempHigh);
        }
        if (rawTempLow != null) {
          tempLow = ConversionUtils.evaluateFormula(tempFormula, rawTempLow);
        }
      }

      final conditions = _getStringValue('$basePath.conditions.$i');
      final icon = _getStringValue('$basePath.icon.$i');
      final precipProb = ConversionUtils.getConvertedValue(signalKService, '$basePath.precipProbability.$i');
      final precipIcon = _getStringValue('$basePath.precipIcon.$i');

      // Get sunrise/sunset ISO times
      final sunrise = _getDateTimeValue('$basePath.sunriseIso.$i');
      final sunset = _getDateTimeValue('$basePath.sunsetIso.$i');

      // Only add if we have at least high temp or conditions
      if (tempHigh != null || conditions != null) {
        forecasts.add(DailyForecast(
          dayIndex: i,
          tempHigh: tempHigh,
          tempLow: tempLow,
          conditions: conditions,
          icon: icon,
          precipProbability: precipProb,
          precipIcon: precipIcon,
          sunrise: sunrise,
          sunset: sunset,
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
      category: ToolCategory.weather,
      configSchema: ConfigSchema(
        allowsMinMax: false,
        allowsColorCustomization: true,
        allowsMultiplePaths: true,
        minPaths: 0,
        maxPaths: 8,
        styleOptions: const [
          'primaryColor',
          'hoursToShow',
          'daysToShow',
          'showCurrentConditions',
          'showSunMoonArc',
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
        DataSource(path: 'environment.outside.tempest.forecast.hourly', label: 'Hourly Forecast'),
        DataSource(path: 'environment.outside.tempest.forecast.daily', label: 'Daily Forecast'),
      ],
      style: StyleConfig(
        primaryColor: '#2196F3',
        customProperties: {
          'hoursToShow': 12,
          'daysToShow': 7,
          'showCurrentConditions': true,
          'showSunMoonArc': true,
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
