import 'dart:typed_data';

import 'pdf_object.dart';
import 'pdf_primitive_object.dart';
import '../../io/source/byte_utils.dart';

/// Represents a PDF numeric object.
///
/// PDF numbers can be integers or real (floating point) numbers.
class CraftPdfNumber extends CraftPdfPrimitiveObject {
  /// The numeric value.
  double _value;

  /// Creates a PdfNumber from a double.
  CraftPdfNumber(double value) : _value = value;

  /// Creates a PdfNumber from an int.
  CraftPdfNumber.fromInt(int value) : _value = value.toDouble();

  /// Creates a PdfNumber from bytes.
  factory CraftPdfNumber.fromBytes(Uint8List content) {
    final str = String.fromCharCodes(content);
    return CraftPdfNumber(double.parse(str));
  }

  /// Creates a PdfNumber from a string.
  factory CraftPdfNumber.fromString(String value) {
    return CraftPdfNumber(double.parse(value));
  }

  @override
  int objectKind() => PdfObjectType.number;

  @override
  CraftPdfObject clone() {
    return CraftPdfNumber(_value);
  }

  @override
  CraftPdfObject newInstance() {
    return CraftPdfNumber(0);
  }

  /// Gets the value as double.
  double getValue() => _value;

  /// Sets the value.
  void setValue(double value) {
    _value = value;
    setContent(null); // Force regeneration
  }

  /// Gets the value as int.
  int intValue() => _value.toInt();

  /// Gets the value as double.
  double doubleValue() => _value;

  /// Gets the value as float (same as double in Dart).
  double floatValue() => _value;

  /// Increments the value.
  void increment() {
    _value++;
    setContent(null);
  }

  /// Decrements the value.
  void decrement() {
    _value--;
    setContent(null);
  }

  /// Checks if value has decimal part.
  bool hasDecimalPart() {
    return _value != _value.truncateToDouble();
  }

  /// Checks if this matches an integer exactly. (Helper for PdfOutputStream)
  bool isDoubleNumber() => hasDecimalPart();

  @override
  void generateContent() {
    if (!hasDecimalPart()) {
      setContent(CraftByteUtils.getIsoBytesFromInt(intValue()));
    } else {
      setContent(CraftByteUtils.getIsoBytesFromDouble(_value));
    }
  }

  @override
  String toString() {
    if (!hasDecimalPart()) {
      return intValue().toString();
    }
    return _value.toString();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CraftPdfNumber) return false;
    return _value == other._value;
  }

  @override
  int get hashCode => _value.hashCode;
}
