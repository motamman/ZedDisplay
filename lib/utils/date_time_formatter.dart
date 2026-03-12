/// Centralized DateTime Formatting Utility
/// Provides consistent date/time formatting across all widgets
library;

class DateTimeFormatter {
  // Month abbreviations
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  // Full month names
  static const _monthsFull = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  // Day abbreviations (Monday = index 0, matching DateTime.weekday - 1)
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  // Full day names
  static const _daysFull = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];

  /// Format time: "3:45 PM" or "15:45"
  ///
  /// - [use24Hour]: If true, returns "15:45" format; if false, returns "3:45 PM"
  /// - [includeMinutes]: If false and minutes are 0, returns "3 PM" instead of "3:00 PM"
  static String formatTime(DateTime time, {bool use24Hour = false, bool includeMinutes = true}) {
    final hour = time.hour;
    final minute = time.minute;

    if (use24Hour) {
      if (includeMinutes) {
        return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
      } else {
        return '${hour.toString().padLeft(2, '0')}:00';
      }
    } else {
      final ampm = hour < 12 ? 'AM' : 'PM';
      final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
      if (includeMinutes && minute != 0) {
        return '$displayHour:${minute.toString().padLeft(2, '0')} $ampm';
      } else if (includeMinutes) {
        return '$displayHour:00 $ampm';
      } else {
        return '$displayHour $ampm';
      }
    }
  }

  /// Format date short: "Dec 22"
  static String formatDateShort(DateTime time) {
    return '${_months[time.month - 1]} ${time.day}';
  }

  /// Format date full: "December 22, 2024"
  static String formatDateFull(DateTime time) {
    return '${_monthsFull[time.month - 1]} ${time.day}, ${time.year}';
  }

  /// Format datetime: "Mon, Dec 22 at 3:45 PM"
  static String formatDateTime(DateTime time, {bool use24Hour = false}) {
    final dayAbbrev = getDayAbbrev(time);
    final dateShort = formatDateShort(time);
    final timeStr = formatTime(time, use24Hour: use24Hour);
    return '$dayAbbrev, $dateShort at $timeStr';
  }

  /// Format date range: "Dec 22 - Dec 25"
  static String formatDateRange(DateTime start, DateTime end) {
    return '${formatDateShort(start)} - ${formatDateShort(end)}';
  }

  /// Format time range: "3:00 PM - 5:30 PM"
  static String formatTimeRange(DateTime start, DateTime end, {bool use24Hour = false}) {
    return '${formatTime(start, use24Hour: use24Hour)} - ${formatTime(end, use24Hour: use24Hour)}';
  }

  /// Format for API calls: "2024-12-22"
  static String formatApiDate(DateTime time) {
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
  }

  /// Get day abbreviation: "Mon", "Tue", etc.
  static String getDayAbbrev(DateTime time) {
    return _days[time.weekday - 1];
  }

  /// Get full day name: "Monday", "Tuesday", etc.
  static String getDayFull(DateTime time) {
    return _daysFull[time.weekday - 1];
  }

  /// Get month abbreviation: "Jan", "Feb", etc.
  static String getMonthAbbrev(DateTime time) {
    return _months[time.month - 1];
  }

  /// Get full month name: "January", "February", etc.
  static String getMonthFull(DateTime time) {
    return _monthsFull[time.month - 1];
  }

  /// Format relative day: "Today", "Tomorrow", "Yesterday", or day name
  static String formatRelativeDay(DateTime time, DateTime reference) {
    final timeDate = DateTime.utc(time.year, time.month, time.day);
    final refDate = DateTime.utc(reference.year, reference.month, reference.day);
    final diff = timeDate.difference(refDate).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tmrw';
    if (diff == -1) return 'Ystd';
    if (diff > 0 && diff < 7) return getDayAbbrev(time);
    return formatDateShort(time);
  }
}
