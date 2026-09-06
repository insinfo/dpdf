/// PdfDate is the PDF date object.
///
/// PDF defines a standard date format: (D:YYYYMMDDHHmmSSOHH'mm')
/// See ISO-320001 7.9.4, "Dates".
class CraftPdfDate {
  final String _value;

  /// Constructs a PdfDate from a DateTime.
  CraftPdfDate(DateTime d) : _value = _generateStringByDateTime(d);

  /// Constructs a PdfDate representing the current time.
  CraftPdfDate.now() : this(DateTime.now());

  /// Constructs a PdfDate from a PDF date string.
  CraftPdfDate.fromString(String s) : _value = s;

  /// Gets the PDF date string.
  String getValue() => _value;

  /// Gets the W3C format of the PdfDate.
  String getW3CDate() => getW3CDateFromString(_value);

  /// Converts a PDF date string to W3C format.
  static String getW3CDateFromString(String d) {
    if (d.startsWith('D:')) {
      d = d.substring(2);
    }
    final sb = StringBuffer();
    if (d.length < 4) return '0000';

    // year
    sb.write(d.substring(0, 4));
    d = d.substring(4);
    if (d.length < 2) return sb.toString();

    // month
    sb.write('-');
    sb.write(d.substring(0, 2));
    d = d.substring(2);
    if (d.length < 2) return sb.toString();

    // day
    sb.write('-');
    sb.write(d.substring(0, 2));
    d = d.substring(2);
    if (d.length < 2) return sb.toString();

    // hour
    sb.write('T');
    sb.write(d.substring(0, 2));
    d = d.substring(2);
    if (d.length < 2) {
      sb.write(':00Z');
      return sb.toString();
    }

    // minute
    sb.write(':');
    sb.write(d.substring(0, 2));
    d = d.substring(2);
    if (d.length < 2) {
      sb.write('Z');
      return sb.toString();
    }

    // second
    sb.write(':');
    sb.write(d.substring(0, 2));
    d = d.substring(2);

    if (d.startsWith('-') || d.startsWith('+')) {
      final sign = d.substring(0, 1);
      d = d.substring(1);
      if (d.length >= 2) {
        final h = d.substring(0, 2);
        var m = '00';
        if (d.length > 2) {
          d = d.substring(3);
          if (d.length >= 2) {
            m = d.substring(0, 2);
          }
        }
        sb.write(sign);
        sb.write(h);
        sb.write(':');
        sb.write(m);
        return sb.toString();
      }
    }
    sb.write('Z');
    return sb.toString();
  }

  /// Explicit offsets are returned as UTC instants. An absent timezone keeps
  /// local-time semantics because the input does not identify a UTC offset.
  static DateTime decode(String value) {
    final match = RegExp(
            r"^(?:D:)?([0-9]{4})((?:[0-9]{2}){0,5})(Z(?:00'00'?)?|[+-][0-9]{2}(?:'?[0-9]{2}'?)?)?$")
        .firstMatch(value);
    if (match == null) throw FormatException('Malformed PDF date.', value);
    final year = int.parse(match.group(1)!);
    final fields = match.group(2)!;
    int field(int index, int fallback) => fields.length >= (index + 1) * 2
        ? int.parse(fields.substring(index * 2, index * 2 + 2))
        : fallback;
    final month = field(0, 1),
        day = field(1, 1),
        hour = field(2, 0),
        minute = field(3, 0),
        second = field(4, 0);
    final wall = DateTime.utc(year, month, day, hour, minute, second);
    if (wall.year != year ||
        wall.month != month ||
        wall.day != day ||
        wall.hour != hour ||
        wall.minute != minute ||
        wall.second != second) {
      throw FormatException('PDF date contains an out-of-range field.', value);
    }
    final zone = match.group(3);
    if (zone == null) return DateTime(year, month, day, hour, minute, second);
    if (zone.startsWith('Z')) return wall;
    final digits = zone.substring(1).replaceAll("'", '');
    final hours = int.parse(digits.substring(0, 2));
    final minutes = digits.length == 4 ? int.parse(digits.substring(2)) : 0;
    if (hours > 23 || minutes > 59) {
      throw FormatException('PDF date contains an invalid UTC offset.', value);
    }
    final offset = Duration(hours: hours, minutes: minutes);
    return zone.startsWith('-') ? wall.add(offset) : wall.subtract(offset);
  }

  static String _generateStringByDateTime(DateTime d) {
    final year = d.year.toString().padLeft(4, '0');
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final hour = d.hour.toString().padLeft(2, '0');
    final minute = d.minute.toString().padLeft(2, '0');
    final second = d.second.toString().padLeft(2, '0');

    // Calculate timezone offset
    final offset = d.timeZoneOffset;
    final offsetHours = offset.inHours.abs().toString().padLeft(2, '0');
    final offsetMinutes =
        (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    final sign = offset.isNegative ? '-' : '+';

    return "D:$year$month$day$hour$minute$second$sign$offsetHours'$offsetMinutes'";
  }

  @override
  String toString() => _value;
}
