import 'package:flutter/material.dart';
import '../../models/tool_definition.dart';
import '../../models/tool_config.dart';
import '../../services/signalk_service.dart';
import '../../services/tool_registry.dart';
import '../../utils/color_extensions.dart';
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

    // Current observations via MetadataStore-backed conversion.
    final currentTemp = signalKService.getConvertedValue(_getPath(0));
    final currentHumidity = signalKService.getConvertedValue(_getPath(1));
    final currentPressure = signalKService.getConvertedValue(_getPath(2));
    final currentWindSpeed = signalKService.getConvertedValue(_getPath(3));
    final currentWindGust = signalKService.getConvertedValue(_getPath(4));
    final currentWindDirection = signalKService.getConvertedValue(_getPath(5));

    // Get rain data
    const rainLastHourPath = 'environment.outside.tempest.observations.precipTotal1h';
    const rainTodayPath = 'environment.outside.tempest.observations.localDailyRainAccumulation';
    final rainLastHour = signalKService.getConvertedValue(rainLastHourPath);
    final rainToday = signalKService.getConvertedValue(rainTodayPath);

    // Unit symbols from MetadataStore via category lookup. These labels
    // are shared by the current observations AND the forecast rows; the
    // Tempest forecast paths aren't in the server's `default-categories`,
    // so a path-based symbol lookup falls through to null for them.
    // Category lookup hits the `__category__.<name>` entries seeded on
    // connect, so it always carries the user's active preset. Rain stays
    // path-based — it's an observation-only value with no shared category.
    final store = signalKService.metadataStore;
    final tempUnit = store.getByCategory('temperature')?.symbol;
    final pressureUnit = store.getByCategory('pressure')?.symbol;
    final windUnit = store.getByCategory('speed')?.symbol;
    final rainUnit = signalKService.getUnitSymbol(rainLastHourPath);

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

  /// Convert a raw SI value at [path] via the user's preset for
  /// [category]. The Tempest forecast paths aren't in the server's
  /// `default-categories`, so a path-first lookup (`getConvertedValue`)
  /// falls through to raw SI silently. Category lookup goes straight to
  /// the `__category__.<name>` entries seeded by `populateFromPreset`
  /// and so always carries the active preset.
  double? _convertByCategory(String path, String category) {
    final raw = _getNumericValue(path);
    if (raw == null) return null;
    final meta = signalKService.metadataStore.getByCategory(category);
    return meta?.convert(raw) ?? raw;
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
      final temp = _convertByCategory('$basePath.airTemperature.$i', 'temperature');
      final feelsLike = _convertByCategory('$basePath.feelsLike.$i', 'temperature');
      final conditions = _getStringValue('$basePath.conditions.$i');
      final icon = _getStringValue('$basePath.icon.$i');
      final precipProb = _convertByCategory('$basePath.precipProbability.$i', 'percentage');
      final humidity = _convertByCategory('$basePath.relativeHumidity.$i', 'percentage');
      final pressure = _convertByCategory('$basePath.seaLevelPressure.$i', 'pressure');
      final windSpeed = _convertByCategory('$basePath.windAvg.$i', 'speed');
      // Wind direction is graphical (arrow rotation), not a user-facing
      // numeric, so it stays raw SI radians — the consumer rotates in
      // radians directly rather than honouring the user's angle preset.
      final windDirection = _getNumericValue('$basePath.windDirection.$i');

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

    for (int i = 0; i < count && i < 10; i++) {
      // Convert via category lookup. The daily forecast paths aren't in
      // the server's `default-categories`, so a path-based lookup falls
      // through to raw SI; category lookup carries the user's preset.
      final tempHigh = _convertByCategory('$basePath.airTempHigh.$i', 'temperature');
      final tempLow = _convertByCategory('$basePath.airTempLow.$i', 'temperature');

      final conditions = _getStringValue('$basePath.conditions.$i');
      final icon = _getStringValue('$basePath.icon.$i');
      final precipProb = _convertByCategory('$basePath.precipProbability.$i', 'percentage');
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
