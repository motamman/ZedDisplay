import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'signalk_service.dart';

/// Response from SignalK Weather API forecasts/point endpoint
class WeatherApiForecast {
  final DateTime time;
  final double? airTemperature; // Kelvin
  final double? feelsLike; // Kelvin
  final double? relativeHumidity; // 0-1 ratio
  final double? windAvg; // m/s
  final double? windDirection; // radians
  final double? windGust; // m/s
  final double? precip; // meters
  final double? precipProbability; // 0-1 ratio
  final String? precipType;
  final double? uv;
  final double? pressure; // Pa
  final String? conditions;
  final String? icon;

  WeatherApiForecast({
    required this.time,
    this.airTemperature,
    this.feelsLike,
    this.relativeHumidity,
    this.windAvg,
    this.windDirection,
    this.windGust,
    this.precip,
    this.precipProbability,
    this.precipType,
    this.uv,
    this.pressure,
    this.conditions,
    this.icon,
  });

  factory WeatherApiForecast.fromJson(Map<String, dynamic> json) {
    // Parse time from 'date' field (ISO string)
    DateTime time;
    final timeValue = json['date'] ?? json['time'];
    if (timeValue is String) {
      time = DateTime.tryParse(timeValue) ?? DateTime.now();
    } else if (timeValue is int) {
      time = timeValue > 9999999999
          ? DateTime.fromMillisecondsSinceEpoch(timeValue)
          : DateTime.fromMillisecondsSinceEpoch(timeValue * 1000);
    } else {
      time = DateTime.now();
    }

    // SignalK Weather API structure:
    // { date, type, description, outside: {...}, wind: {...} }
    final outside = json['outside'] as Map<String, dynamic>? ?? {};
    final wind = json['wind'] as Map<String, dynamic>? ?? {};

    // Temperature in Kelvin - use feelsLikeTemperature as fallback if temperature missing
    double? airTemp = (outside['temperature'] as num?)?.toDouble();
    airTemp ??= (outside['feelsLikeTemperature'] as num?)?.toDouble();

    // Feels like temperature in Kelvin
    double? feelsLike = (outside['feelsLikeTemperature'] as num?)?.toDouble();

    // Humidity as 0-1 ratio
    double? humidity = (outside['relativeHumidity'] as num?)?.toDouble();

    // Wind speed in m/s
    double? windSpeed = (wind['speedTrue'] as num?)?.toDouble();
    windSpeed ??= (wind['averageSpeed'] as num?)?.toDouble();

    // Wind direction in radians
    double? windDir = (wind['directionTrue'] as num?)?.toDouble();

    // Wind gust in m/s
    double? windGust = (wind['gust'] as num?)?.toDouble();

    // Precipitation probability as 0-1 ratio
    double? precipProb = (outside['precipitationProbability'] as num?)?.toDouble();

    // Pressure in Pascals
    double? pressure = (outside['pressure'] as num?)?.toDouble();

    // UV index
    double? uv = (outside['uvIndex'] as num?)?.toDouble();

    // Description and icon
    String? conditions = json['description'] as String?;
    // Use icon from API if provided (Meteoblue), otherwise derive from conditions
    String? icon = json['icon'] as String? ?? _deriveIconFromConditions(conditions, time);

    return WeatherApiForecast(
      time: time,
      airTemperature: airTemp,
      feelsLike: feelsLike,
      relativeHumidity: humidity,
      windAvg: windSpeed,
      windDirection: windDir,
      windGust: windGust,
      precip: (outside['precipitationVolume'] as num?)?.toDouble(),
      precipProbability: precipProb,
      precipType: null,
      uv: uv,
      pressure: pressure,
      conditions: conditions,
      icon: icon,
    );
  }

  /// Derive icon code from conditions text
  static String? _deriveIconFromConditions(String? conditions, DateTime time) {
    if (conditions == null || conditions.isEmpty) return null;

    final c = conditions.toLowerCase();
    final hour = time.toLocal().hour;
    final isDay = hour >= 6 && hour < 18;
    final dayNight = isDay ? 'day' : 'night';

    // Check for thunderstorms first (highest priority)
    if (c.contains('thunder')) return 'thunderstorm';

    // Snow conditions
    if (c.contains('snow') || c.contains('flurr')) return 'snow';

    // Sleet/ice conditions
    if (c.contains('sleet') || c.contains('ice') || c.contains('freezing')) return 'sleet';

    // Rain conditions
    if (c.contains('rain') || c.contains('shower') || c.contains('drizzle')) {
      if (c.contains('possible') || c.contains('chance') || c.contains('likely')) {
        return 'possibly-rainy-$dayNight';
      }
      return 'rainy';
    }

    // Fog conditions
    if (c.contains('fog') || c.contains('mist') || c.contains('haz')) return 'foggy';

    // Wind conditions
    if (c.contains('wind') && !c.contains('cloud')) return 'windy';

    // Cloud conditions
    if (c.contains('cloud') || c.contains('overcast')) {
      if (c.contains('partly') || c.contains('mostly clear')) {
        return 'partly-cloudy-$dayNight';
      }
      if (c.contains('mostly cloudy')) {
        return 'cloudy';
      }
      return 'cloudy';
    }

    // Clear conditions
    if (c.contains('clear') || c.contains('sunny') || c.contains('fair')) {
      return 'clear-$dayNight';
    }

    // Default fallback
    return 'partly-cloudy-$dayNight';
  }

  /// Convert temperature from Kelvin to Fahrenheit
  double? get temperatureF {
    if (airTemperature == null) return null;
    return (airTemperature! - 273.15) * 9 / 5 + 32;
  }

  /// Convert temperature from Kelvin to Celsius
  double? get temperatureC {
    if (airTemperature == null) return null;
    return airTemperature! - 273.15;
  }

  /// Convert feels like from Kelvin to Fahrenheit
  double? get feelsLikeF {
    if (feelsLike == null) return null;
    return (feelsLike! - 273.15) * 9 / 5 + 32;
  }

  /// Convert feels like from Kelvin to Celsius
  double? get feelsLikeC {
    if (feelsLike == null) return null;
    return feelsLike! - 273.15;
  }

  /// Convert humidity from 0-1 ratio to percentage
  double? get humidityPercent {
    if (relativeHumidity == null) return null;
    return relativeHumidity! * 100;
  }

  /// Convert precip probability from 0-1 ratio to percentage
  double? get precipProbabilityPercent {
    if (precipProbability == null) return null;
    return precipProbability! * 100;
  }

  /// Convert wind speed from m/s to knots
  double? get windSpeedKnots {
    if (windAvg == null) return null;
    return windAvg! * 1.94384;
  }

  /// Convert wind direction from radians to degrees
  double? get windDirectionDegrees {
    if (windDirection == null) return null;
    return windDirection! * 180 / 3.14159265359;
  }

  /// Convert pressure from Pa to hPa (mbar)
  double? get pressureHpa {
    if (pressure == null) return null;
    return pressure! / 100;
  }
}

/// Service to fetch weather data from SignalK Weather API
/// Uses a static cache to share data across all widgets with the same provider
class WeatherApiService extends ChangeNotifier {
  final SignalKService _signalKService;
  final String? _provider;

  // Static cache of instances by provider key
  static final Map<String, WeatherApiService> _instances = {};
  static final Map<String, int> _refCounts = {};

  List<WeatherApiForecast> _hourlyForecasts = [];
  DateTime? _lastFetch;
  bool _isLoading = false;
  String? _errorMessage;
  Timer? _refreshTimer;

  // Cache duration - don't fetch more often than this
  static const Duration _cacheDuration = Duration(minutes: 15);
  // Auto-refresh interval
  static const Duration _refreshInterval = Duration(minutes: 30);

  /// Get or create a shared instance for the given provider
  factory WeatherApiService(SignalKService signalKService, {String? provider}) {
    final key = provider ?? '_default_';

    if (_instances.containsKey(key)) {
      _refCounts[key] = (_refCounts[key] ?? 0) + 1;
      return _instances[key]!;
    }

    final instance = WeatherApiService._internal(signalKService, provider: provider);
    _instances[key] = instance;
    _refCounts[key] = 1;
    return instance;
  }

  WeatherApiService._internal(this._signalKService, {String? provider}) : _provider = provider {
    // Start auto-refresh timer (every 30 minutes)
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => fetchForecasts());
  }

  String? get provider => _provider;

  List<WeatherApiForecast> get hourlyForecasts => _hourlyForecasts;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasData => _hourlyForecasts.isNotEmpty;

  /// Fetch forecasts from SignalK Weather API
  Future<void> fetchForecasts({bool force = false}) async {
    // Prevent concurrent fetches
    if (_isLoading) return;

    // Check cache validity
    if (!force && _lastFetch != null) {
      final age = DateTime.now().difference(_lastFetch!);
      if (age < _cacheDuration && _hourlyForecasts.isNotEmpty) {
        return; // Use cached data
      }
    }

    if (!_signalKService.isConnected) {
      if (_errorMessage != 'Not connected to SignalK') {
        _errorMessage = 'Not connected to SignalK';
        notifyListeners();
      }
      return;
    }

    // Get vessel position for API call
    final lat = _getVesselLat();
    final lon = _getVesselLon();

    if (lat == null || lon == null) {
      if (_errorMessage != 'Vessel position not available') {
        _errorMessage = 'Vessel position not available';
        if (kDebugMode) {
          print('WeatherApiService: No position data - lat=$lat, lon=$lon');
        }
        notifyListeners();
      }
      return;
    }

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // Build API URL
      final serverUrl = _signalKService.serverUrl;
      final useSecure = serverUrl.startsWith('wss://') || serverUrl.startsWith('https://');
      final host = serverUrl.replaceAll(RegExp(r'^wss?://|^https?://'), '').split('/').first;
      final scheme = useSecure ? 'https' : 'http';

      var url = '$scheme://$host/signalk/v2/api/weather/forecasts/point?lat=$lat&lon=$lon';
      if (_provider != null && _provider.isNotEmpty) {
        url += '&provider=$_provider';
      }

      if (kDebugMode) {
        print('WeatherApiService: Fetching from $url');
      }

      final response = await http.get(
        Uri.parse(url),
        headers: _signalKService.authToken != null
            ? {'Authorization': 'Bearer ${_signalKService.authToken!.token}'}
            : null,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (kDebugMode) {
          print('WeatherApiService: Response type: ${data.runtimeType}');
          if (data is List && data.isNotEmpty) {
            print('WeatherApiService: First item keys: ${(data[0] as Map).keys.toList()}');
          } else if (data is Map) {
            print('WeatherApiService: Response keys: ${data.keys.toList()}');
          }
        }

        // Parse forecasts array
        List<dynamic> forecastList;
        if (data is List) {
          forecastList = data;
        } else if (data is Map && data['forecasts'] is List) {
          forecastList = data['forecasts'] as List;
        } else if (data is Map && data['hourly'] is List) {
          forecastList = data['hourly'] as List;
        } else {
          throw Exception('Unexpected response format: ${data.runtimeType}');
        }

        _hourlyForecasts = forecastList
            .whereType<Map<String, dynamic>>()
            .map((item) => WeatherApiForecast.fromJson(item))
            .toList();

        _lastFetch = DateTime.now();
        _errorMessage = null;

        if (kDebugMode) {
          print('WeatherApiService: Loaded ${_hourlyForecasts.length} hourly forecasts');
        }
      } else if (response.statusCode == 400) {
        final data = json.decode(response.body);
        _errorMessage = data['message'] ?? 'Bad request';
        if (kDebugMode) {
          print('WeatherApiService: 400 error - ${response.body}');
        }
      } else if (response.statusCode == 404) {
        _errorMessage = 'Weather API not available on this server';
      } else {
        _errorMessage = 'Failed to fetch weather: ${response.statusCode}';
        if (kDebugMode) {
          print('WeatherApiService: ${response.statusCode} error - ${response.body}');
        }
      }
    } catch (e) {
      _errorMessage = 'Error fetching weather: $e';
      if (kDebugMode) {
        print('WeatherApiService error: $e');
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Get vessel latitude from SignalK
  double? _getVesselLat() {
    final posData = _signalKService.getValue('navigation.position');
    if (posData?.value is Map) {
      final pos = posData!.value as Map;
      return (pos['latitude'] as num?)?.toDouble();
    }
    return null;
  }

  /// Get vessel longitude from SignalK
  double? _getVesselLon() {
    final posData = _signalKService.getValue('navigation.position');
    if (posData?.value is Map) {
      final pos = posData!.value as Map;
      return (pos['longitude'] as num?)?.toDouble();
    }
    return null;
  }

  /// Release this instance - decrements ref count but keeps instance alive for caching
  void release() {
    final key = _provider ?? '_default_';
    final count = (_refCounts[key] ?? 1) - 1;
    _refCounts[key] = count < 0 ? 0 : count;
    // Keep instance alive for caching - don't dispose even when ref count is 0
  }

  /// Force dispose all instances (call on app shutdown or SignalK disconnect)
  static void disposeAll() {
    for (final instance in _instances.values) {
      instance._refreshTimer?.cancel();
    }
    _instances.clear();
    _refCounts.clear();
  }

  @override
  void dispose() {
    // Don't call super.dispose() directly - use release() or disposeAll()
    // This prevents accidental disposal of shared instances
  }
}
