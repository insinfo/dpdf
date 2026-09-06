import 'dart:convert';
import 'dart:typed_data';

import 'pdf_object.dart';
import 'pdf_primitive_object.dart';

/// Represents a PDF string object.
///
/// PDF strings can be literal strings (in parentheses) or
/// hexadecimal strings (in angle brackets).
class PdfString extends PdfPrimitiveObject {
  /// The raw value bytes.
  Uint8List? _value;

  /// The decoded string value.
  String? _decodedValue;

  /// Whether this is a hex string.
  bool _hexWriting = false;

  /// The encoding used.
  String? _encoding;

  /// Creates a PdfString from a String.
  PdfString(String value) {
    _decodedValue = value;
    _value = latin1.encode(value);
  }

  /// Creates a PdfString from bytes.
  PdfString.fromBytes(Uint8List value, [bool hexWriting = false]) {
    _value = value;
    _hexWriting = hexWriting;
    setContent(
        value); // For strings, the "internal content" is the raw bytes without () or <>
  }

  /// Creates an empty PdfString.
  PdfString.empty() {
    _value = Uint8List(0);
    setContent(_value);
  }

  @override
  int getObjectType() => PdfObjectType.string;

  @override
  PdfObject clone() {
    final cloned = PdfString.fromBytes(
      Uint8List.fromList(_value ?? []),
      _hexWriting,
    );
    cloned._decodedValue = _decodedValue;
    cloned._encoding = _encoding;
    return cloned;
  }

  @override
  PdfObject newInstance() {
    return PdfString.empty();
  }

  /// Gets the raw value bytes.
  Uint8List? getValueBytes() => _value;

  /// Gets the string value.
  String getValue() {
    if (_decodedValue == null && _value != null) {
      _decodedValue = _decodeContent();
    }
    return _decodedValue ?? '';
  }

  /// Sets the value.
  void setValue(String value) {
    _decodedValue = value;
    _value = latin1.encode(value);
    setContent(_value);
  }

  /// Returns true if this is a hex string.
  bool isHexWriting() => _hexWriting;

  /// Sets hex writing mode.
  PdfString setHexWriting(bool hexWriting) {
    _hexWriting = hexWriting;
    return this;
  }

  /// Gets the encoding.
  String? getEncoding() => _encoding;

  /// Sets the encoding.
  void setEncoding(String? encoding) {
    _encoding = encoding;
  }

  /// Converts to Unicode string.
  String toUnicodeString() {
    if (_value == null || _value!.isEmpty) {
      return '';
    }
    // Check for BOM
    if (_value!.length >= 2) {
      if (_value![0] == 0xFE && _value![1] == 0xFF) {
        // UTF-16BE BOM
        return _decodeUtf16Be(_value!.sublist(2));
      }
      if (_value![0] == 0xFF && _value![1] == 0xFE) {
        // UTF-16LE BOM
        return _decodeUtf16Le(_value!.sublist(2));
      }
    }
    // Try UTF-8 or Latin-1
    return getValue();
  }

  /// Decodes content based on encoding hints.
  String _decodeContent() {
    if (_value == null || _value!.isEmpty) {
      return '';
    }
    try {
      // Check for UTF-16BE BOM
      if (_value!.length >= 2 && _value![0] == 0xFE && _value![1] == 0xFF) {
        return _decodeUtf16Be(_value!.sublist(2));
      }
      // Try Latin-1
      return latin1.decode(_value!);
    } catch (e) {
      return String.fromCharCodes(_value!);
    }
  }

  /// Decodes UTF-16BE bytes.
  String _decodeUtf16Be(Uint8List bytes) {
    if (bytes.length % 2 != 0) {
      bytes = Uint8List.fromList([...bytes, 0]);
    }
    final buffer = StringBuffer();
    for (var i = 0; i < bytes.length; i += 2) {
      final charCode = (bytes[i] << 8) | bytes[i + 1];
      buffer.writeCharCode(charCode);
    }
    return buffer.toString();
  }

  /// Decodes UTF-16LE bytes.
  String _decodeUtf16Le(Uint8List bytes) {
    if (bytes.length % 2 != 0) {
      bytes = Uint8List.fromList([...bytes, 0]);
    }
    final buffer = StringBuffer();
    for (var i = 0; i < bytes.length; i += 2) {
      final charCode = bytes[i] | (bytes[i + 1] << 8);
      buffer.writeCharCode(charCode);
    }
    return buffer.toString();
  }

  /// Encodes to UTF-16BE with BOM.
  static Uint8List encodeToUtf16Be(String str) {
    final bytes = <int>[0xFE, 0xFF]; // BOM
    for (final char in str.codeUnits) {
      bytes.add((char >> 8) & 0xFF);
      bytes.add(char & 0xFF);
    }
    return Uint8List.fromList(bytes);
  }

  @override
  void generateContent() {
    if (_value != null) {
      setContent(_value);
    } else {
      setContent(Uint8List(0));
    }
  }

  @override
  String toString() {
    return getValue();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PdfString) return false;
    return getValue() == other.getValue();
  }

  @override
  int get hashCode => getValue().hashCode;
}
