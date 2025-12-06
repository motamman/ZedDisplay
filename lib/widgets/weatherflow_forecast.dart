import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Sun/Moon times for arc display
class SunMoonTimes {
  final DateTime? sunrise;
  final DateTime? sunset;
  final DateTime? dawn;
  final DateTime? dusk;
  final DateTime? nauticalDawn;
  final DateTime? nauticalDusk;
  final DateTime? solarNoon;
  final DateTime? goldenHour;
  final DateTime? goldenHourEnd;
  final DateTime? night;
  final DateTime? nightEnd;
  final DateTime? moonrise;
  final DateTime? moonset;
  final double? moonPhase; // 0-1 (0=new, 0.5=full) - determines which side is lit
  final double? moonFraction; // 0-1 illumination fraction - how much is lit
  final double? moonAngle; // radians

  const SunMoonTimes({
    this.sunrise,
    this.sunset,
    this.dawn,
    this.dusk,
    this.nauticalDawn,
    this.nauticalDusk,
    this.solarNoon,
    this.goldenHour,
    this.goldenHourEnd,
    this.night,
    this.nightEnd,
    this.moonrise,
    this.moonset,
    this.moonPhase,
    this.moonFraction,
    this.moonAngle,
  });
}

/// Daily forecast entry
class DailyForecast {
  final int dayIndex; // 0 = today, 1 = tomorrow, etc.
  final double? tempHigh;
  final double? tempLow;
  final String? conditions;
  final String? icon;
  final double? precipProbability;
  final String? precipIcon;
  final DateTime? sunrise;
  final DateTime? sunset;

  DailyForecast({
    required this.dayIndex,
    this.tempHigh,
    this.tempLow,
    this.conditions,
    this.icon,
    this.precipProbability,
    this.precipIcon,
    this.sunrise,
    this.sunset,
  });

  /// Get day name from index
  String get dayName {
    if (dayIndex == 0) return 'Today';
    if (dayIndex == 1) return 'Tomorrow';
    final date = DateTime.now().add(Duration(days: dayIndex));
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }

  /// Get weather icon asset path
  String get weatherIconAsset {
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

/// WeatherFlow Forecast widget showing current conditions and hourly/daily forecast
class WeatherFlowForecast extends StatefulWidget {
  /// Current observations (already converted by ConversionUtils)
  final double? currentTemp;
  final double? currentHumidity;
  final double? currentPressure;
  final double? currentWindSpeed;
  final double? currentWindGust;
  final double? currentWindDirection; // degrees
  final double? rainLastHour; // precipitation in last hour
  final double? rainToday; // today's total precipitation

  /// Unit labels for display
  final String tempUnit;
  final String pressureUnit;
  final String windUnit;
  final String rainUnit;

  /// Hourly forecasts (up to 72 hours)
  final List<HourlyForecast> hourlyForecasts;

  /// Daily forecasts (up to 10 days)
  final List<DailyForecast> dailyForecasts;

  /// Number of hours to display
  final int hoursToShow;

  /// Number of days to display
  final int daysToShow;

  /// Primary color
  final Color primaryColor;

  /// Show current conditions section
  final bool showCurrentConditions;

  /// Sun/Moon times for arc display
  final SunMoonTimes? sunMoonTimes;

  /// Show sun/moon arc
  final bool showSunMoonArc;

  const WeatherFlowForecast({
    super.key,
    this.currentTemp,
    this.currentHumidity,
    this.currentPressure,
    this.currentWindSpeed,
    this.currentWindGust,
    this.currentWindDirection,
    this.rainLastHour,
    this.rainToday,
    this.tempUnit = '°C',
    this.pressureUnit = 'hPa',
    this.windUnit = 'kts',
    this.rainUnit = 'mm',
    this.hourlyForecasts = const [],
    this.dailyForecasts = const [],
    this.hoursToShow = 12,
    this.daysToShow = 7,
    this.primaryColor = Colors.blue,
    this.showCurrentConditions = true,
    this.sunMoonTimes,
    this.showSunMoonArc = true,
  });

  @override
  State<WeatherFlowForecast> createState() => _WeatherFlowForecastState();
}

class _WeatherFlowForecastState extends State<WeatherFlowForecast> {
  int _selectedTab = 0; // 0 = hourly, 1 = daily

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
            const SizedBox(height: 8),

            // Sun/Moon arc (beneath header, above current conditions)
            if (widget.showSunMoonArc && widget.sunMoonTimes != null) ...[
              _SunMoonArc(times: widget.sunMoonTimes!, isDark: isDark),
              const SizedBox(height: 8),
            ],

            // Current conditions
            if (widget.showCurrentConditions) ...[
              _buildCurrentConditions(context, isDark),
              const SizedBox(height: 8),
              Divider(color: isDark ? Colors.white24 : Colors.black12),
              const SizedBox(height: 4),
            ],

            // Tab bar for Hourly / Daily
            _buildForecastTabs(isDark),
            const SizedBox(height: 8),

            // Forecast content based on selected tab
            Expanded(
              child: _selectedTab == 0
                  ? _buildHourlyForecast(context, isDark)
                  : _buildDailyForecast(context, isDark),
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
          color: widget.primaryColor,
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

  Widget _buildForecastTabs(bool isDark) {
    return Row(
      children: [
        _buildTabButton('Hourly', 0, isDark),
        const SizedBox(width: 8),
        _buildTabButton('Daily', 1, isDark),
      ],
    );
  }

  Widget _buildTabButton(String label, int index, bool isDark) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? widget.primaryColor.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? widget.primaryColor
                : (isDark ? Colors.white24 : Colors.black12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected
                ? widget.primaryColor
                : (isDark ? Colors.white70 : Colors.black54),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentConditions(BuildContext context, bool isDark) {
    // Values are already converted by ConversionUtils
    // Format rain display: "1h / today" or just one if other is null/zero
    String rainDisplay = '--';
    if (widget.rainLastHour != null || widget.rainToday != null) {
      final lastHour = widget.rainLastHour ?? 0;
      final today = widget.rainToday ?? 0;
      if (lastHour > 0 || today > 0) {
        rainDisplay = '${lastHour.toStringAsFixed(1)}/${today.toStringAsFixed(1)}';
      } else {
        rainDisplay = '0';
      }
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildConditionItem(
          context,
          Icons.thermostat,
          widget.currentTemp != null ? '${widget.currentTemp!.toStringAsFixed(1)}${widget.tempUnit}' : '--',
          'Temp',
          Colors.orange,
          isDark,
        ),
        _buildConditionItem(
          context,
          Icons.water_drop,
          widget.currentHumidity != null ? '${widget.currentHumidity!.toStringAsFixed(0)}%' : '--',
          'Humidity',
          Colors.cyan,
          isDark,
        ),
        _buildConditionItem(
          context,
          Icons.umbrella,
          rainDisplay,
          '${widget.rainUnit} 1h/day',
          Colors.blue,
          isDark,
        ),
        _buildConditionItem(
          context,
          Icons.speed,
          widget.currentPressure != null ? widget.currentPressure!.toStringAsFixed(0) : '--',
          widget.pressureUnit,
          Colors.purple,
          isDark,
        ),
        _buildConditionItem(
          context,
          Icons.air,
          widget.currentWindSpeed != null
              ? (widget.currentWindGust != null
                  ? '${widget.currentWindSpeed!.toStringAsFixed(1)}/${widget.currentWindGust!.toStringAsFixed(0)}'
                  : widget.currentWindSpeed!.toStringAsFixed(1))
              : '--',
          widget.windUnit,
          Colors.teal,
          isDark,
          subtitle2: widget.currentWindDirection != null ? _getWindDirectionLabel(widget.currentWindDirection!) : null,
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
    if (widget.hourlyForecasts.isEmpty) {
      return Center(
        child: Text(
          'No forecast data available',
          style: TextStyle(
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
      );
    }

    final forecasts = widget.hourlyForecasts.take(widget.hoursToShow).toList();
    final now = DateTime.now();

    // Build list of items (forecasts + sunrise/sunset markers)
    final items = <_HourlyItem>[];

    // Add forecasts
    for (final forecast in forecasts) {
      final forecastTime = now.add(Duration(hours: forecast.hour));
      items.add(_HourlyItem(
        time: forecastTime,
        type: _HourlyItemType.forecast,
        forecast: forecast,
      ));
    }

    // Add sunrise if within range
    if (widget.sunMoonTimes?.sunrise != null) {
      final sunrise = widget.sunMoonTimes!.sunrise!.toLocal();
      final firstHour = now;
      final lastHour = now.add(Duration(hours: widget.hoursToShow));
      if (sunrise.isAfter(firstHour) && sunrise.isBefore(lastHour)) {
        items.add(_HourlyItem(
          time: sunrise,
          type: _HourlyItemType.sunrise,
        ));
      }
    }

    // Add sunset if within range
    if (widget.sunMoonTimes?.sunset != null) {
      final sunset = widget.sunMoonTimes!.sunset!.toLocal();
      final firstHour = now;
      final lastHour = now.add(Duration(hours: widget.hoursToShow));
      if (sunset.isAfter(firstHour) && sunset.isBefore(lastHour)) {
        items.add(_HourlyItem(
          time: sunset,
          type: _HourlyItemType.sunset,
        ));
      }
    }

    // Sort by time
    items.sort((a, b) => a.time.compareTo(b.time));

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        switch (item.type) {
          case _HourlyItemType.forecast:
            return _buildHourCard(context, item.forecast!, isDark);
          case _HourlyItemType.sunrise:
            return _buildSunriseCard(context, item.time, isDark);
          case _HourlyItemType.sunset:
            return _buildSunsetCard(context, item.time, isDark);
        }
      },
    );
  }

  Widget _buildSunriseCard(BuildContext context, DateTime time, bool isDark) {
    return Container(
      width: 48,
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.indigo.shade900.withValues(alpha: 0.3),
            Colors.amber.shade200.withValues(alpha: 0.3),
          ],
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.amber.shade400.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          // Time - fixed at top
          Text(
            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const Spacer(),
          Icon(Icons.wb_sunny, size: 28, color: Colors.amber.shade400),
          const SizedBox(height: 4),
          Text(
            'Sunrise',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: Colors.amber.shade400,
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildSunsetCard(BuildContext context, DateTime time, bool isDark) {
    return Container(
      width: 48,
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.deepOrange.shade300.withValues(alpha: 0.3),
            Colors.indigo.shade900.withValues(alpha: 0.3),
          ],
        ),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.deepOrange.shade400.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          // Time - fixed at top
          Text(
            '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          const Spacer(),
          Icon(Icons.nights_stay, size: 28, color: Colors.deepOrange.shade400),
          const SizedBox(height: 4),
          Text(
            'Sunset',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w500,
              color: Colors.deepOrange.shade400,
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildDailyForecast(BuildContext context, bool isDark) {
    if (widget.dailyForecasts.isEmpty) {
      return Center(
        child: Text(
          'No daily forecast data available',
          style: TextStyle(
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
      );
    }

    final forecasts = widget.dailyForecasts.take(widget.daysToShow).toList();

    return ListView.builder(
      scrollDirection: Axis.vertical,
      itemCount: forecasts.length,
      itemBuilder: (context, index) {
        final forecast = forecasts[index];
        return _buildDayCard(context, forecast, isDark);
      },
    );
  }

  Widget _buildDayCard(BuildContext context, DailyForecast forecast, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
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
      child: Row(
        children: [
          // Day name
          SizedBox(
            width: 65,
            child: Text(
              forecast.dayName,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ),
          // Weather icon
          SizedBox(
            width: 24,
            height: 24,
            child: SvgPicture.asset(
              forecast.weatherIconAsset,
              width: 24,
              height: 24,
              placeholderBuilder: (context) => Icon(
                forecast.fallbackIcon,
                color: _getWeatherIconColor(forecast.icon),
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Conditions
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  forecast.conditions ?? '',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white60 : Colors.black45,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                // Sunrise/Sunset times
                if (forecast.sunrise != null || forecast.sunset != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (forecast.sunrise != null) ...[
                        Icon(Icons.wb_sunny, size: 9, color: Colors.amber.shade400),
                        const SizedBox(width: 2),
                        Text(
                          '${forecast.sunrise!.toLocal().hour.toString().padLeft(2, '0')}:${forecast.sunrise!.toLocal().minute.toString().padLeft(2, '0')}',
                          style: TextStyle(fontSize: 9, color: isDark ? Colors.white38 : Colors.black38),
                        ),
                      ],
                      if (forecast.sunrise != null && forecast.sunset != null)
                        const SizedBox(width: 6),
                      if (forecast.sunset != null) ...[
                        Icon(Icons.nights_stay, size: 9, color: Colors.indigo.shade300),
                        const SizedBox(width: 2),
                        Text(
                          '${forecast.sunset!.toLocal().hour.toString().padLeft(2, '0')}:${forecast.sunset!.toLocal().minute.toString().padLeft(2, '0')}',
                          style: TextStyle(fontSize: 9, color: isDark ? Colors.white38 : Colors.black38),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
          // Precip probability
          if (forecast.precipProbability != null && forecast.precipProbability! > 0)
            Container(
              margin: const EdgeInsets.only(right: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.water_drop,
                    size: 10,
                    color: Colors.blue.shade300,
                  ),
                  Text(
                    '${forecast.precipProbability!.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.blue.shade300,
                    ),
                  ),
                ],
              ),
            ),
          // High/Low temps
          SizedBox(
            width: 80,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  forecast.tempHigh != null ? '${forecast.tempHigh!.toStringAsFixed(0)}${widget.tempUnit}' : '--',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  '/',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white38 : Colors.black26,
                  ),
                ),
                Text(
                  forecast.tempLow != null ? '${forecast.tempLow!.toStringAsFixed(0)}${widget.tempUnit}' : '--',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
      width: 58,
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 3),
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Hour - fixed at top
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
          // Flexible space to push content to fill
          const Spacer(),
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
            ),
          const SizedBox(height: 2),
          // Weather icon from SVG asset
          Expanded(
            flex: 2,
            child: Center(
              child: SvgPicture.asset(
                forecast.weatherIconAsset,
                width: 24,
                height: 24,
                placeholderBuilder: (context) => Icon(
                  forecast.fallbackIcon,
                  color: _getWeatherIconColor(forecast.icon),
                  size: 24,
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          // Temperature
          Text(
            temp != null ? '${temp.toStringAsFixed(0)}${widget.tempUnit}' : '--',
            style: TextStyle(
              fontSize: 13,
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
            ),
          const Spacer(),
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

/// Sun/Moon arc widget showing day progression
class _SunMoonArc extends StatelessWidget {
  final SunMoonTimes times;
  final bool isDark;

  const _SunMoonArc({required this.times, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();

    return SizedBox(
      height: 70,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: _SunMoonArcPainter(
              times: times,
              now: now,
              isDark: isDark,
            ),
            child: _buildIconsOverlay(constraints, now),
          );
        },
      ),
    );
  }

  Widget _buildIconsOverlay(BoxConstraints constraints, DateTime now) {
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;

    // Center arc on "now" with 12 hours before and after
    final arcStart = now.subtract(const Duration(hours: 12));
    const arcDuration = 1440; // 24 hours in minutes

    final children = <Widget>[];

    // Helper to calculate position on arc
    (double x, double y)? getArcPosition(DateTime time, {double size = 16}) {
      final minutesFromStart = time.difference(arcStart).inMinutes;
      final progress = minutesFromStart / arcDuration;
      if (progress < 0 || progress > 1) return null;

      final xPercent = 0.05 + progress * 0.9;
      final normalizedX = (progress - 0.5) * 2;
      final yPercent = 0.15 + (1 - normalizedX * normalizedX) * 0.5;

      final x = width * xPercent - size / 2;
      final y = height * (1 - yPercent) - size / 2;
      return (x, y);
    }

    // Sunrise marker on the arc
    if (times.sunrise != null) {
      final sunrisePos = getArcPosition(times.sunrise!, size: 20);
      if (sunrisePos != null) {
        children.add(
          Positioned(
            left: sunrisePos.$1,
            top: sunrisePos.$2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_upward,
                  color: Colors.amber.shade600,
                  size: 10,
                ),
                const Icon(Icons.wb_sunny, color: Colors.amber, size: 16),
              ],
            ),
          ),
        );
      }
    }

    // Sunset marker on the arc
    if (times.sunset != null) {
      final sunsetPos = getArcPosition(times.sunset!, size: 20);
      if (sunsetPos != null) {
        children.add(
          Positioned(
            left: sunsetPos.$1,
            top: sunsetPos.$2 - 10, // Position above the arc
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wb_sunny, color: Colors.deepOrange, size: 16),
                Icon(
                  Icons.arrow_downward,
                  color: Colors.deepOrange.shade600,
                  size: 10,
                ),
              ],
            ),
          ),
        );
      }
    }

    // Sun icon at current position (if daytime)
    if (times.sunrise != null && times.sunset != null) {
      if (now.isAfter(times.sunrise!) && now.isBefore(times.sunset!)) {
        final pos = getArcPosition(now, size: 20);
        if (pos != null) {
          children.add(
            Positioned(
              left: pos.$1,
              top: pos.$2,
              child: const Icon(Icons.wb_sunny, color: Colors.amber, size: 20),
            ),
          );
        }
      }
    }

    // Moonrise marker below the arc
    if (times.moonrise != null) {
      final moonrisePos = getArcPosition(times.moonrise!, size: 16);
      if (moonrisePos != null) {
        children.add(
          Positioned(
            left: moonrisePos.$1,
            top: moonrisePos.$2 + 5, // Position below the arc
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.arrow_upward,
                  color: Colors.blueGrey.shade300,
                  size: 10,
                ),
                _buildMoonIcon(times.moonPhase, times.moonFraction),
              ],
            ),
          ),
        );
      }
    }

    // Moonset marker above the arc
    if (times.moonset != null) {
      final moonsetPos = getArcPosition(times.moonset!, size: 16);
      if (moonsetPos != null) {
        children.add(
          Positioned(
            left: moonsetPos.$1,
            top: moonsetPos.$2 - 20, // Position above the arc
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildMoonIcon(times.moonPhase, times.moonFraction),
                Icon(
                  Icons.arrow_downward,
                  color: Colors.blueGrey.shade300,
                  size: 10,
                ),
              ],
            ),
          ),
        );
      }
    }

    // "Now" indicator at center (always at 50%) - above the baseline
    final nowX = width * 0.5; // Center of arc
    final baseY = height - 10; // Baseline position (same as painter)
    children.add(
      Positioned(
        left: nowX - 12,
        top: baseY - 20, // Position above baseline
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'now',
              style: TextStyle(
                fontSize: 8,
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
            Container(
              width: 2,
              height: 10,
              color: Colors.red,
            ),
          ],
        ),
      ),
    );

    return Stack(clipBehavior: Clip.none, children: children);
  }

  Widget _buildMoonIcon(double? phase, double? fraction) {
    return CustomPaint(
      size: const Size(16, 16),
      painter: _MoonPhasePainter(
        phase: phase ?? 0.5,
        fraction: fraction ?? 0.5,
      ),
    );
  }
}

/// Custom painter for moon phase showing illumination
class _MoonPhasePainter extends CustomPainter {
  final double phase; // 0-1: determines which side is lit (< 0.5 = waxing/right, > 0.5 = waning/left)
  final double fraction; // 0-1: illumination fraction (0 = new, 1 = full)

  _MoonPhasePainter({required this.phase, required this.fraction});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1;

    // Draw the dark side of the moon (background)
    final darkPaint = Paint()
      ..color = Colors.grey.shade800
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, darkPaint);

    // Draw the illuminated side
    final lightPaint = Paint()
      ..color = Colors.grey.shade200
      ..style = PaintingStyle.fill;

    if (fraction < 0.01) {
      // New moon - no illumination
      return;
    } else if (fraction > 0.99) {
      // Full moon - full illumination
      canvas.drawCircle(center, radius, lightPaint);
      return;
    }

    // Use phase to determine which side is lit
    // phase < 0.5 = waxing (right side lit)
    // phase >= 0.5 = waning (left side lit)
    final bool isWaxing = phase < 0.5;

    // Use fraction directly for illumination amount
    // fraction 0 = new, 0.5 = half, 1 = full
    // Flip so higher fraction = more light
    final termWidth = radius * (2.0 * fraction - 1.0);
    final isGibbous = fraction > 0.5;

    // Build the illuminated area path
    final path = Path();

    if (isWaxing) {
      // Waxing: right side is lit first
      path.moveTo(center.dx, center.dy - radius);
      // Draw right semicircle (clockwise from top to bottom)
      path.arcToPoint(
        Offset(center.dx, center.dy + radius),
        radius: Radius.circular(radius),
        clockwise: true,
      );
      // Draw terminator back to top
      // For gibbous: expand into dark side (clockwise), for crescent: contract (ccw)
      path.arcToPoint(
        Offset(center.dx, center.dy - radius),
        radius: Radius.elliptical(termWidth.abs().clamp(0.1, radius), radius),
        clockwise: isGibbous,
      );
    } else {
      // Waning: left side is lit
      path.moveTo(center.dx, center.dy - radius);
      // Draw left semicircle (counter-clockwise from top to bottom)
      path.arcToPoint(
        Offset(center.dx, center.dy + radius),
        radius: Radius.circular(radius),
        clockwise: false,
      );
      // Draw terminator back to top
      // For gibbous: expand into dark side (ccw), for crescent: contract (clockwise)
      path.arcToPoint(
        Offset(center.dx, center.dy - radius),
        radius: Radius.elliptical(termWidth.abs().clamp(0.1, radius), radius),
        clockwise: !isGibbous,
      );
    }

    path.close();
    canvas.drawPath(path, lightPaint);

    // Draw outline
    final outlinePaint = Paint()
      ..color = Colors.grey.shade400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawCircle(center, radius, outlinePaint);
  }

  @override
  bool shouldRepaint(covariant _MoonPhasePainter oldDelegate) {
    return oldDelegate.phase != phase || oldDelegate.fraction != fraction;
  }
}

/// Custom painter for the sun/moon arc
class _SunMoonArcPainter extends CustomPainter {
  final SunMoonTimes times;
  final DateTime now;
  final bool isDark;

  _SunMoonArcPainter({
    required this.times,
    required this.now,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Center arc on "now" with 12 hours before and after
    final arcStart = now.subtract(const Duration(hours: 12));
    final arcEnd = now.add(const Duration(hours: 12));
    const arcDuration = 1440.0; // 24 hours in minutes

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Draw the arc segments with different colors for different phases
    final segments = <_ArcSegment>[
      // Night (before nautical dawn)
      if (times.nauticalDawn != null)
        _ArcSegment(arcStart, times.nauticalDawn!, Colors.indigo.shade900.withValues(alpha: 0.5)),
      // Nautical twilight (dawn)
      if (times.nauticalDawn != null && times.dawn != null)
        _ArcSegment(times.nauticalDawn!, times.dawn!, Colors.indigo.shade700),
      // Civil twilight (dawn)
      if (times.dawn != null && times.sunrise != null)
        _ArcSegment(times.dawn!, times.sunrise!, Colors.indigo.shade400),
      // Golden hour (morning)
      if (times.sunrise != null && times.goldenHourEnd != null)
        _ArcSegment(times.sunrise!, times.goldenHourEnd!, Colors.orange.shade300),
      // Daylight (morning)
      if (times.goldenHourEnd != null && times.solarNoon != null)
        _ArcSegment(times.goldenHourEnd!, times.solarNoon!, Colors.amber.shade200),
      // Daylight (afternoon)
      if (times.solarNoon != null && times.goldenHour != null)
        _ArcSegment(times.solarNoon!, times.goldenHour!, Colors.amber.shade200),
      // Golden hour (evening)
      if (times.goldenHour != null && times.sunset != null)
        _ArcSegment(times.goldenHour!, times.sunset!, Colors.orange.shade400),
      // Civil twilight (dusk)
      if (times.sunset != null && times.dusk != null)
        _ArcSegment(times.sunset!, times.dusk!, Colors.deepOrange.shade400),
      // Nautical twilight (dusk)
      if (times.dusk != null && times.nauticalDusk != null)
        _ArcSegment(times.dusk!, times.nauticalDusk!, Colors.indigo.shade400),
      // Night (after nautical dusk)
      if (times.nauticalDusk != null)
        _ArcSegment(times.nauticalDusk!, arcEnd, Colors.indigo.shade900.withValues(alpha: 0.5)),
    ];

    // Draw baseline
    final baseY = size.height - 10;
    canvas.drawLine(
      Offset(size.width * 0.05, baseY),
      Offset(size.width * 0.95, baseY),
      Paint()
        ..color = isDark ? Colors.white24 : Colors.black12
        ..strokeWidth = 1,
    );

    // Draw arc segments
    for (final segment in segments) {
      final startProgress = segment.start.difference(arcStart).inMinutes / arcDuration;
      final endProgress = segment.end.difference(arcStart).inMinutes / arcDuration;

      if (startProgress >= 1 || endProgress <= 0) continue;

      final clampedStart = startProgress.clamp(0.0, 1.0);
      final clampedEnd = endProgress.clamp(0.0, 1.0);

      paint.color = segment.color;
      _drawArcSegment(canvas, size, clampedStart, clampedEnd, paint, baseY);
    }

    // Draw time labels
    _drawTimeLabels(canvas, size, arcStart, arcEnd, baseY);
  }

  void _drawArcSegment(Canvas canvas, Size size, double startProgress, double endProgress, Paint paint, double baseY) {
    final path = Path();
    const steps = 20;

    for (int i = 0; i <= steps; i++) {
      final t = startProgress + (endProgress - startProgress) * (i / steps);
      final x = size.width * (0.05 + t * 0.9);
      final normalizedX = (t - 0.5) * 2;
      final arcHeight = (size.height - 20) * 0.7;
      final y = baseY - (1 - normalizedX * normalizedX) * arcHeight;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  void _drawTimeLabels(Canvas canvas, Size size, DateTime arcStart, DateTime arcEnd, double baseY) {
    const arcDuration = 1440.0; // 24 hours in minutes

    // Helper to draw colored time label
    void drawColoredLabel(DateTime? time, String label, Color color, double yOffset) {
      if (time == null) return;
      final progress = time.difference(arcStart).inMinutes / arcDuration;
      if (progress < 0 || progress > 1) return;

      final x = size.width * (0.05 + progress * 0.9);
      final textSpan = TextSpan(
        text: label,
        style: TextStyle(fontSize: 8, color: color, fontWeight: FontWeight.w500),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - textPainter.width / 2, baseY + yOffset));
    }

    // Draw relative time markers at edges (neutral color)
    final neutralColor = isDark ? Colors.white54 : Colors.black45;
    drawColoredLabel(arcStart, '-12h', neutralColor, 2);
    drawColoredLabel(arcEnd.subtract(const Duration(minutes: 1)), '+12h', neutralColor, 2);

    // Draw sunrise time (amber)
    if (times.sunrise != null) {
      final progress = times.sunrise!.difference(arcStart).inMinutes / arcDuration;
      if (progress >= 0 && progress <= 1) {
        final local = times.sunrise!.toLocal();
        final timeStr = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
        drawColoredLabel(times.sunrise, timeStr, Colors.amber, 2);
      }
    }

    // Draw sunset time (deep orange)
    if (times.sunset != null) {
      final progress = times.sunset!.difference(arcStart).inMinutes / arcDuration;
      if (progress >= 0 && progress <= 1) {
        final local = times.sunset!.toLocal();
        final timeStr = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
        drawColoredLabel(times.sunset, timeStr, Colors.deepOrange, 2);
      }
    }

    // Draw moonrise time (blueGrey)
    if (times.moonrise != null) {
      final progress = times.moonrise!.difference(arcStart).inMinutes / arcDuration;
      if (progress >= 0 && progress <= 1) {
        final local = times.moonrise!.toLocal();
        final timeStr = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
        drawColoredLabel(times.moonrise, timeStr, Colors.blueGrey.shade300, 2);
      }
    }

    // Draw moonset time (blueGrey)
    if (times.moonset != null) {
      final progress = times.moonset!.difference(arcStart).inMinutes / arcDuration;
      if (progress >= 0 && progress <= 1) {
        final local = times.moonset!.toLocal();
        final timeStr = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
        drawColoredLabel(times.moonset, timeStr, Colors.blueGrey.shade300, 2);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SunMoonArcPainter oldDelegate) {
    return oldDelegate.now.minute != now.minute;
  }
}

class _ArcSegment {
  final DateTime start;
  final DateTime end;
  final Color color;

  _ArcSegment(this.start, this.end, this.color);
}

/// Types of items in the hourly forecast list
enum _HourlyItemType { forecast, sunrise, sunset }

/// Item in the hourly forecast list (either a forecast or a sun event)
class _HourlyItem {
  final DateTime time;
  final _HourlyItemType type;
  final HourlyForecast? forecast;

  _HourlyItem({
    required this.time,
    required this.type,
    this.forecast,
  });
}
