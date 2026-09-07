import 'package:dpdf/src/io/util/text_util.dart';

class SvgTextUtil {
  SvgTextUtil._();

  /// Removes horizontal whitespace while preserving line boundaries.
  static String trimLeadingWhitespace(String? text) =>
      String.fromCharCodes((text ?? '').codeUnits.skipWhile(_horizontalSpace));

  /// Removes horizontal whitespace at the end, stopping at CR or LF.
  static String trimTrailingWhitespace(String? text) =>
      String.fromCharCodes((text ?? '')
          .codeUnits
          .reversed
          .skipWhile(_horizontalSpace)
          .toList()
          .reversed);

  static bool _horizontalSpace(int unit) =>
      unit != 10 && unit != 13 && TextUtil.isWhiteSpace(unit);

  /// Normalizes a reference by removing its fragment or URL wrapper.
  static String filterReferenceValue(String name) {
    return name
        .replaceAll("#", "")
        .replaceAll("url(", "")
        .replaceAll(")", "")
        .trim();
  }
}
