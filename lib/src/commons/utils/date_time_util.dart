/// Helper class for internal usage only.
/// TODO ? Be aware that its API and functionality may be changed in future.
class DateTimeUtil {
  DateTimeUtil._();

  static const String _defaultPattern = 'yyyy-MM-dd';

  /// The Unix epoch (January 1, 1970, 00:00:00 UTC).
  static final DateTime _epoch = DateTime.utc(1970, 1, 1, 0, 0, 0);

  /// Gets the date time as UTC milliseconds from the epoch.
  static double getUtcMillisFromEpoch(DateTime? dateTime) {
    dateTime ??= getCurrentUtcTime();
    return dateTime.toUtc().difference(_epoch).inMilliseconds.toDouble();
  }

  /// Gets the calendar date and time of a day.
  static DateTime getCalendar(DateTime dateTime) {
    return dateTime;
  }

  /// Gets the current time in the default time zone.
  static DateTime getCurrentTime() {
    return DateTime.now();
  }

  /// Gets the current UTC time.
  static DateTime getCurrentUtcTime() {
    return DateTime.now().toUtc();
  }

  /// Defines if date is in past.
  static bool isInPast(DateTime date) {
    return date.isBefore(getCurrentTime());
  }

  /// Gets the number of milliseconds since January 1, 1970, 00:00:00 GMT.
  static int getRelativeTime(DateTime date) {
    return date.toUtc().difference(_epoch).inMilliseconds;
  }

  /// Adds provided number of milliseconds to the DateTime.
  static DateTime addMillisToDate(DateTime date, int millis) {
    return date.add(Duration(milliseconds: millis));
  }

  /// Parses passing date with default `yyyy-MM-dd` pattern.
  static DateTime parseWithDefaultPattern(String date) {
    return parse(date, _defaultPattern);
  }

  /// Parses passing date with specified format.
  /// Supports common patterns: yyyy, MM, dd, HH, mm, ss
  static DateTime parse(String date, String pattern) {
    // For simple patterns like yyyy-MM-dd, use Dart's built-in
    if (pattern == 'yyyy-MM-dd') {
      return DateTime.parse(date);
    }
    // For other patterns, try to parse common formats
    return _parseWithPattern(date, pattern);
  }

  /// Format passing date with default yyyy-MM-dd pattern.
  static String formatWithDefaultPattern(DateTime date) {
    return format(date, _defaultPattern);
  }

  /// Format passing date with specified pattern.
  /// Supports: yyyy, yy, MM, M, dd, d, HH, H, mm, m, ss, s
  static String format(DateTime date, String pattern) {
    return _formatWithPattern(date, pattern);
  }

  /// Gets the offset of time zone from UTC at the specified date.
  static int getCurrentTimeZoneOffset(DateTime date) {
    return date.timeZoneOffset.inMilliseconds;
  }

  /// Converts date to string of "yyyy.MM.dd HH:mm:ss z" format.
  static String dateToString(DateTime signDate) {
    final local = signDate.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final mo = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final h = local.hour.toString().padLeft(2, '0');
    final mi = local.minute.toString().padLeft(2, '0');
    final s = local.second.toString().padLeft(2, '0');
    final offset = local.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs().toString().padLeft(2, '0');
    final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return '$y.$mo.$d $h:$mi:$s $sign$hours:$minutes';
  }

  /// Creates a DateTime object with the specified year, month, day, hour, minute, and second.
  static DateTime createDateTime(int year, int month, int day,
      [int hour = 0, int minute = 0, int second = 0]) {
    return DateTime(year, month, day, hour, minute, second);
  }

  /// Gets the DateTime from milliseconds since epoch.
  static DateTime getTimeFromMillis(int milliseconds) {
    return _epoch.add(Duration(milliseconds: milliseconds));
  }

  /// Creates UTC Date based on provided parameters.
  /// Note: month is 0-indexed (0 = January) to match Java Calendar behavior.
  static DateTime createUtcDateTime(
      int year, int month, int day, int hour, int minute, int second) {
    return DateTime.utc(year, month + 1, day, hour, minute, second);
  }

  /// Internal format implementation supporting common patterns.
  static String _formatWithPattern(DateTime date, String pattern) {
    var result = pattern;
    result = result.replaceAll('yyyy', date.year.toString().padLeft(4, '0'));
    result =
        result.replaceAll('yy', (date.year % 100).toString().padLeft(2, '0'));
    result = result.replaceAll('MM', date.month.toString().padLeft(2, '0'));
    result = result.replaceAll('M', date.month.toString());
    result = result.replaceAll('dd', date.day.toString().padLeft(2, '0'));
    result = result.replaceAll('d', date.day.toString());
    result = result.replaceAll('HH', date.hour.toString().padLeft(2, '0'));
    result = result.replaceAll('H', date.hour.toString());
    result = result.replaceAll('mm', date.minute.toString().padLeft(2, '0'));
    result = result.replaceAll('m', date.minute.toString());
    result = result.replaceAll('ss', date.second.toString().padLeft(2, '0'));
    result = result.replaceAll('s', date.second.toString());
    return result;
  }

  /// Internal parse implementation for common patterns.
  static DateTime _parseWithPattern(String date, String pattern) {
    // Try ISO format first
    try {
      return DateTime.parse(date);
    } catch (_) {
      // Continue with pattern parsing
    }

    // Simple pattern-based extraction
    int year = 1970, month = 1, day = 1, hour = 0, minute = 0, second = 0;

    // Extract based on pattern positions
    int yearIdx = pattern.indexOf('yyyy');
    if (yearIdx >= 0 && yearIdx + 4 <= date.length) {
      year = int.tryParse(date.substring(yearIdx, yearIdx + 4)) ?? 1970;
    }

    int monthIdx = pattern.indexOf('MM');
    if (monthIdx >= 0 && monthIdx + 2 <= date.length) {
      month = int.tryParse(date.substring(monthIdx, monthIdx + 2)) ?? 1;
    }

    int dayIdx = pattern.indexOf('dd');
    if (dayIdx >= 0 && dayIdx + 2 <= date.length) {
      day = int.tryParse(date.substring(dayIdx, dayIdx + 2)) ?? 1;
    }

    int hourIdx = pattern.indexOf('HH');
    if (hourIdx >= 0 && hourIdx + 2 <= date.length) {
      hour = int.tryParse(date.substring(hourIdx, hourIdx + 2)) ?? 0;
    }

    int minIdx = pattern.indexOf('mm');
    if (minIdx >= 0 && minIdx + 2 <= date.length) {
      minute = int.tryParse(date.substring(minIdx, minIdx + 2)) ?? 0;
    }

    int secIdx = pattern.indexOf('ss');
    if (secIdx >= 0 && secIdx + 2 <= date.length) {
      second = int.tryParse(date.substring(secIdx, secIdx + 2)) ?? 0;
    }

    return DateTime(year, month, day, hour, minute, second);
  }

  /// Formats date to PDF format: D:YYYYMMDDHHmmSSOHH'mm
  static String formatPdfDate(DateTime date) {
    var d = date.toLocal();
    var str = 'D:${d.year.toString().padLeft(4, '0')}'
        '${d.month.toString().padLeft(2, '0')}'
        '${d.day.toString().padLeft(2, '0')}'
        '${d.hour.toString().padLeft(2, '0')}'
        '${d.minute.toString().padLeft(2, '0')}'
        '${d.second.toString().padLeft(2, '0')}';

    var offset = d.timeZoneOffset;
    if (offset.inMinutes == 0) {
      str += 'Z00\'00';
    } else {
      var sign = offset.isNegative ? '-' : '+';
      var hours = offset.inHours.abs().toString().padLeft(2, '0');
      var minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
      str += '$sign$hours\'$minutes';
    }
    return str;
  }
}
