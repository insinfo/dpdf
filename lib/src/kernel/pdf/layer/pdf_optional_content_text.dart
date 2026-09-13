import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/src/kernel/pdf/pdf_string.dart';

/// Encodes [value] as a PDF text string (ISO 32000-1, clause 7.9.2.2).
///
/// PDFDocEncoding cannot represent everything a layer name may contain, so a
/// string that does not survive a latin-1 round trip is written as UTF-16BE
/// with a byte order mark, which clause 7.9.2.2 defines as the other legal
/// form of a text string.
PdfString makeOcTextString(String value) {
  final latin1Safe = value.codeUnits.every((unit) => unit <= 0xFF);
  if (latin1Safe) return PdfString(value);

  final units = value.codeUnits;
  final bytes = Uint8List(2 + units.length * 2);
  bytes[0] = 0xFE;
  bytes[1] = 0xFF;
  for (var i = 0; i < units.length; i++) {
    bytes[2 + i * 2] = (units[i] >> 8) & 0xFF;
    bytes[3 + i * 2] = units[i] & 0xFF;
  }
  return PdfString.fromBytes(bytes, false);
}

/// Decodes a PDF text string, honouring a UTF-16 byte order mark.
String readOcTextString(PdfString string) {
  final bytes = string.getValueBytes();
  if (bytes == null || bytes.isEmpty) return '';
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return string.decodeMappingText();
  }
  return latin1.decode(bytes, allowInvalid: true);
}
