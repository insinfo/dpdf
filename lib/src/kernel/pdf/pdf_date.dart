/// PdfDate is the PDF date object.
///
/// PDF defines a standard date format: (D:YYYYMMDDHHmmSSOHH'mm')
/// See ISO-320001 7.9.4, "Dates".
class PdfDate {
  final String _value;

  /// Constructs a PdfDate from a DateTime.
  PdfDate(DateTime d) : _value = _generateStringByDateTime(d);

  /// Constructs a PdfDate representing the current time.
  PdfDate.now() : this(DateTime.now());

  /// Constructs a PdfDate from a PDF date string.
  PdfDate.fromString(String s) : _value = s;

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

  /// Decodes a PDF date string to DateTime.
  static DateTime decode(String s) {
    if (s.startsWith('D:')) {
      s = s.substring(2);
    }

    int year = int.parse(s.substring(0, 4));
    int month = 1, day = 1, hour = 0, minute = 0, second = 0;
    int offsetHour = 0, offsetMinute = 0;
    String? variation;

    if (s.length >= 6) {
      month = int.parse(s.substring(4, 6));
      if (s.length >= 8) {
        day = int.parse(s.substring(6, 8));
        if (s.length >= 10) {
          hour = int.parse(s.substring(8, 10));
          if (s.length >= 12) {
            minute = int.parse(s.substring(10, 12));
            if (s.length >= 14) {
              second = int.parse(s.substring(12, 14));
            }
          }
        }
      }
    }

    var d = DateTime(year, month, day, hour, minute, second);
    if (s.length <= 14) return d;

    variation = s[14];
    if (variation == 'Z') return d.toLocal();

    if (s.length >= 17) {
      offsetHour = int.parse(s.substring(15, 17));
      if (s.length >= 20) {
        offsetMinute = int.parse(s.substring(18, 20));
      }
    }

    final offset = Duration(hours: offsetHour, minutes: offsetMinute);
    if (variation == '-') {
      d = d.add(offset);
    } else {
      d = d.subtract(offset);
    }
    return d.toLocal();
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
