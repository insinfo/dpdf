part of 'pdf_text_extraction.dart';

/// Balances q/Q outside strings, names, arrays, dictionaries and comments.
/// Inline image payloads require a separate binary parser and are rejected.
class PdfGraphicsEnvelope {
  static Uint8List wrap(Uint8List content) {
    final tokens = _ContentTokens(content, allowDictionaries: true);
    var depth = 0, minimum = 0;
    for (Object? token; (token = tokens.next()) != null;) {
      if (token is! _Operator) continue;
      switch (token.value) {
        case 'BI':
          throw UnsupportedError(
              'Overlay state repair does not parse inline image payloads.');
        case 'q':
          depth++;
        case 'Q':
          depth--;
      }
      if (depth < minimum) minimum = depth;
      if (depth.abs() > 4096 || minimum < -4096) {
        throw FormatException(
            'Graphics state nesting exceeds the overlay limit.');
      }
    }
    final saves = 1 - minimum;
    return (BytesBuilder(copy: false)
          ..add(ascii.encode('q\n' * saves))
          ..add(content)
          ..add(ascii.encode('\n${'Q\n' * (saves + depth)}')))
        .takeBytes();
  }
}
