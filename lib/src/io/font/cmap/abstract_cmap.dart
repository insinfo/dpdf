import 'dart:typed_data';
import '../pdf_encodings.dart';
import 'cmap_object.dart';

abstract class AbstractCMap {
  String? cmapName;
  String? registry;
  String? ordering;
  int supplement = 0;

  String? getName() => cmapName;

  void setName(String cmapName) {
    this.cmapName = cmapName;
  }

  String? characterCollection() => ordering;

  void assignCharacterCollection(String ordering) {
    this.ordering = ordering;
  }

  String? characterRegistry() => registry;

  void assignCharacterRegistry(String registry) {
    this.registry = registry;
  }

  int collectionSupplement() => supplement;

  void assignCollectionSupplement(int supplement) {
    this.supplement = supplement;
  }

  void registerMappedCode(String mark, CMapObject code);

  void registerCodeInterval(Uint8List low, Uint8List high) {}

  /// Expands a byte-code interval after validating its destination payload.
  void expandMappingInterval(String from, String to, CMapObject code) {
    if (from.isEmpty ||
        from.length != to.length ||
        from.codeUnits.any((unit) => unit > 255) ||
        to.codeUnits.any((unit) => unit > 255)) {
      throw ArgumentError(
          'Mapping endpoints must contain equally sized byte sequences.');
    }
    final cursor = mappingCodeBytes(from);
    final last = mappingCodeBytes(to);
    BigInt unsignedValue(Uint8List bytes) => bytes.fold(
        BigInt.zero, (value, byte) => (value << 8) + BigInt.from(byte));
    final span = unsignedValue(last) - unsignedValue(cursor) + BigInt.one;
    if (span <= BigInt.zero) {
      throw ArgumentError('Mapping interval ends before its first code.');
    }

    final payload = code.getValue();
    List<CMapObject>? entries;
    Uint8List? destination;
    int? firstNumber;
    if (code.isArray()) {
      if (payload is! List<CMapObject> || BigInt.from(payload.length) < span) {
        throw ArgumentError(
            'Mapping interval requires a destination for every code.');
      }
      entries = payload;
    } else if (code.isNumber() && payload is int) {
      firstNumber = payload;
    } else if (code.isString()) {
      destination = mappingCodeBytes(code.toString());
      if (destination.isEmpty) {
        throw ArgumentError('Sequential text destinations cannot be empty.');
      }
    } else {
      throw ArgumentError(
          'Mapping destinations must be text, integers, or an array.');
    }

    var offset = 0;
    while (true) {
      final mapped = entries != null
          ? entries[offset]
          : destination != null
              ? CMapObject(
                  CMapObject.hexString, Uint8List.fromList(destination))
              : CMapObject(CMapObject.number, firstNumber! + offset);
      registerMappedCode(String.fromCharCodes(cursor), mapped);
      if (_sameBytes(cursor, last)) break;
      _advanceBytes(cursor);
      if (destination != null) _advanceBytes(destination);
      offset++;
    }
  }

  static bool _sameBytes(Uint8List left, Uint8List right) {
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  // Carry directly through the byte string, including destinations wider than
  // a machine integer (for example, several UTF-16 code units).
  static void _advanceBytes(Uint8List bytes) {
    var position = bytes.length;
    while (position > 0) {
      position--;
      if (bytes[position] != 255) {
        bytes[position]++;
        return;
      }
      bytes[position] = 0;
    }
  }

  static Uint8List mappingCodeBytes(String range) =>
      Uint8List.fromList(range.codeUnits);

  String decodeMappingText(String value, bool isHexWriting) {
    final bytes = mappingCodeBytes(value);
    final hasBigEndianMarker =
        String.fromCharCodes(bytes.take(2)) == '\u00fe\u00ff';
    final String encoding;
    if (isHexWriting) {
      encoding = PdfEncodings.UNICODE_BIG_UNMARKED;
    } else if (hasBigEndianMarker) {
      encoding = PdfEncodings.UNICODE_BIG;
    } else {
      encoding = PdfEncodings.PDF_DOC_ENCODING;
    }
    return PdfEncodings.convertToString(bytes, encoding);
  }

  static void writeMappingInteger(int n, Uint8List b) {
    final signedValue = BigInt.from(n);
    final octetMask = BigInt.from(255);
    b.setAll(
        0,
        Iterable<int>.generate(b.length, (position) {
          final shift = (b.length - position - 1) * 8;
          return ((signedValue >> shift) & octetMask).toInt();
        }));
  }

  static int readMappingInteger(Uint8List b) =>
      b.fold<int>(0, (prefix, octet) => prefix * 256 + octet);
}
