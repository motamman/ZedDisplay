import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Hourly forecast entry
class HourlyForecast {
  final int hour;
  final double? temperature; // Already converted by ConversionUtils
  final double? feelsLike; // Already converted
  final String? conditions;
  final String? icon;
  final double? precipProbability; // 0-100
  final double? humidity; // Already converted (ratio or %)
  final double? pressure; // Already converted
  final double? windSpeed; // Already converted
  final double? windDirection; // degrees

  HourlyForecast({
    required this.hour,
    this.temperature,
    this.feelsLike,
    this.conditions,
    this.icon,
    this.precipProbability,
    this.humidity,
    this.pressure,
    this.windSpeed,
    this.windDirection,
  });

  /// Get asset path for weather icon based on icon code from WeatherFlow
  String get weatherIconAsset {
    // Map WeatherFlow icon codes to local SVG assets
    const iconMap = {
      'clear-day': 'assets/weather_icons/clear-day.svg',
      'clear-night': 'assets/weather_icons/clear-night.svg',
      'cloudy': 'assets/weather_icons/cloudy.svg',
      'foggy': 'assets/weather_icons/foggy.svg',
      'partly-cloudy-day': 'assets/weather_icons/partly-cloudy-day.svg',
      'partly-cloudy-night': 'assets/weather_icons/partly-cloudy-night.svg',
      'possibly-rainy-day': 'assets/weather_icons/possibly-rainy-day.svg',
      'possibly-rainy-night': 'assets/weather_icons/possibly-rainy-night.svg',
      'possibly-sleet-day': 'assets/weather_icons/possibly-sleet-day.svg',
      'possibly-sleet-night': 'assets/weather_icons/possibly-sleet-night.svg',
      'possibly-snow-day': 'assets/weather_icons/possibly-snow-day.svg',
      'possibly-snow-night': 'assets/weather_icons/possibly-snow-night.svg',
      'possibly-thunderstorm-day': 'assets/weather_icons/possibly-thunderstorm-day.svg',
      'possibly-thunderstorm-night': 'assets/weather_icons/possibly-thunderstorm-night.svg',
      'rainy': 'assets/weather_icons/rainy.svg',
      'sleet': 'assets/weather_icons/sleet.svg',
      'snow': 'assets/weather_icons/snow.svg',
      'thunderstorm': 'assets/weather_icons/thunderstorm.svg',
      'windy': 'assets/weather_icons/windy.svg',
    };
    return iconMap[icon] ?? 'assets/weather_icons/cloudy.svg';
  }

  /// Fallback Flutter icon if asset not available
  IconData get fallbackIcon {
    final code = icon?.toLowerCase() ?? '';
    if (code.contains('clear')) return Icons.wb_sunny;
    if (code.contains('partly-cloudy')) return Icons.cloud_queue;
    if (code.contains('cloudy')) return Icons.cloud;
    if (code.contains('rainy') || code.contains('rain')) return Icons.water_drop;
    if (code.contains('thunder')) return Icons.thunderstorm;
    if (code.contains('snow')) return Icons.ac_unit;
    if (code.contains('sleet')) return Icons.grain;
    if (code.contains('foggy')) return Icons.foggy;
    if (code.contains('windy')) return Icons.air;
    return Icons.help_outline;
  }
}

/// WeatherFlow Forecast widget showing current conditions and hourly forecast
class WeatherFlowForecast extends StatelessWidget {
  /// Current observations (already converted by ConversionUtils)
  final double? currentTemp;
  final double? currentHumidity;
  final double? currentPressure;
  final double? currentWindSpeed;
  final double? currentWindGust;
  final double? currentWindDirection; // degrees

  /// Unit labels for display
  final String tempUnit;
  final String pressureUnit;
  final String windUnit;

  /// Hourly forecasts (up to 72 hours)
  final List<HourlyForecast> hourlyForecasts;

  /// Number of hours to display
  final int hoursToShow;

  /// Primary color
  final Color primaryColor;

  /// Show current conditions section
  final bool showCurrentConditions;

  const WeatherFlowForecast({
    super.key,
    this.currentTemp,
    this.currentHumidity,
    this.currentPressure,
    this.currentWindSpeed,
    this.currentWindGust,
    this.currentWindDirection,
    this.tempUnit = '°C',
    this.pressureUnit = 'hPa',
    this.windUnit = 'kts',
    this.hourlyForecasts = const [],
    this.hoursToShow = 12,
    this.primaryColor = Colors.blue,
    this.showCurrentConditions = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            _buildHeader(context),
            const SizedBox(height: 12),

            // Current conditions
            if (showCurrentConditions) ...[
              _buildCurrentConditions(context, isDark),
              const SizedBox(height: 12),
              Divider(color: isDark ? Colors.white24 : Colors.black12),
              const SizedBox(height: 8),
            ],

            // Hourly forecast
            Text(
              'Hourly Forecast',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _buildHourlyForecast(context, isDark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.cloud,
          color: primaryColor,
          size: 20,
        ),
        const SizedBox(width: 8),
        Text(
          'WeatherFlow Forecast',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ],
    );
  }

  Widget _buildCurrentConditions(BuildContext context, bool isDark) {
    // Values are already converted by ConversionUtils
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildConditionItem(
          context,
          Icons.thermostat,
          currentTemp != null ? '${currentTemp!.toStringAsFixed(1)}$tempUnit' : '--',
          'Temp',
          Colors.orange,
          isDark,
        ),
        _buildConditionItem(
          context,
          Icons.water_drop,
          currentHumidity != null ? '${currentHumidity!.toStringAsFixed(0)}%' : '--',
          'Humidity',
          Colors.cyan,
          isDark,
        ),
        _buildConditionItem(
          context,
          Icons.speed,
          currentPressure != null ? currentPressure!.toStringAsFixed(0) : '--',
          pressureUnit,
          Colors.purple,
          isDark,
        ),
        _buildConditionItem(
          context,
          Icons.air,
          currentWindSpeed != null
              ? (currentWindGust != null
                  ? '${currentWindSpeed!.toStringAsFixed(1)}/${currentWindGust!.toStringAsFixed(0)}'
                  : currentWindSpeed!.toStringAsFixed(1))
              : '--',
          windUnit,
          Colors.teal,
          isDark,
          subtitle2: currentWindDirection != null ? _getWindDirectionLabel(currentWindDirection!) : null,
        ),
      ],
    );
  }

  Widget _buildConditionItem(
    BuildContext context,
    IconData icon,
    String value,
    String label,
    Color color,
    bool isDark, {
    String? subtitle2,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isDark ? Colors.white60 : Colors.black45,
          ),
        ),
        if (subtitle2 != null)
          Text(
            subtitle2,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.white60 : Colors.black45,
            ),
          ),
      ],
    );
  }

  String _getWindDirectionLabel(double degrees) {
    const directions = ['N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
                        'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'];
    final index = ((degrees + 11.25) % 360 / 22.5).floor();
    return directions[index];
  }

  Widget _buildHourlyForecast(BuildContext context, bool isDark) {
    if (hourlyForecasts.isEmpty) {
      return Center(
        child: Text(
          'No forecast data available',
          style: TextStyle(
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
      );
    }

    final forecasts = hourlyForecasts.take(hoursToShow).toList();

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: forecasts.length,
      itemBuilder: (context, index) {
        final forecast = forecasts[index];
        return _buildHourCard(context, forecast, isDark);
      },
    );
  }

  Widget _buildHourCard(BuildContext context, HourlyForecast forecast, bool isDark) {
    final temp = forecast.temperature;
    final precipProb = forecast.precipProbability;
    final windSpeed = forecast.windSpeed;
    final windDir = forecast.windDirection;

    // Calculate hour label with day abbreviation if different day
    final now = DateTime.now();
    final forecastTime = now.add(Duration(hours: forecast.hour));
    final isToday = forecastTime.day == now.day && forecastTime.month == now.month;
    final dayAbbrevs = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final dayAbbrev = dayAbbrevs[forecastTime.weekday - 1];
    final hourLabel = forecast.hour == 0
        ? 'Now'
        : isToday
            ? '${forecastTime.hour.toString().padLeft(2, '0')}:00'
            : '$dayAbbrev ${forecastTime.hour.toString().padLeft(2, '0')}:00';

    return Container(
      width: 56,
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Hour
          Text(
            hourLabel,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          // Wind direction arrow + speed combined
          if (windDir != null || windSpeed != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (windDir != null)
                  Transform.rotate(
                    angle: (windDir + 180) * 3.14159 / 180,
                    child: Icon(
                      Icons.navigation,
                      size: 12,
                      color: Colors.teal.shade300,
                    ),
                  ),
                if (windSpeed != null)
                  Text(
                    windSpeed.toStringAsFixed(0),
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.teal.shade300,
                    ),
                  ),
              ],
            )
          else
            const SizedBox(height: 12),

          // Weather icon from SVG asset
          SizedBox(
            width: 20,
            height: 20,
            child: SvgPicture.asset(
              forecast.weatherIconAsset,
              width: 20,
              height: 20,
              placeholderBuilder: (context) => Icon(
                forecast.fallbackIcon,
                color: _getWeatherIconColor(forecast.icon),
                size: 20,
              ),
            ),
          ),

          // Temperature
          Text(
            temp != null ? '${temp.toStringAsFixed(0)}°' : '--',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),

          // Precipitation probability
          if (precipProb != null && precipProb > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.water_drop,
                  size: 8,
                  color: Colors.blue.shade300,
                ),
                Text(
                  precipProb.toStringAsFixed(0),
                  style: TextStyle(
                    fontSize: 9,
                    color: Colors.blue.shade300,
                  ),
                ),
              ],
            )
          else
            const SizedBox(height: 10),
        ],
      ),
    );
  }

  Color _getWeatherIconColor(String? iconCode) {
    final code = iconCode?.toLowerCase() ?? '';
    if (code.contains('clear')) return Colors.amber;
    if (code.contains('partly-cloudy')) return Colors.blueGrey;
    if (code.contains('cloudy')) return Colors.grey;
    if (code.contains('rainy') || code.contains('rain')) return Colors.blue;
    if (code.contains('thunder')) return Colors.deepPurple;
    if (code.contains('snow')) return Colors.lightBlue.shade100;
    if (code.contains('sleet')) return Colors.cyan;
    if (code.contains('foggy')) return Colors.blueGrey;
    if (code.contains('windy')) return Colors.teal;
    return Colors.grey;
  }
}
