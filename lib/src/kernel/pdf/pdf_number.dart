import 'dart:typed_data';

import 'pdf_object.dart';
import '../../io/source/byte_utils.dart';

/// Represents a PDF numeric object.
///
/// PDF numbers can be integers or real (floating point) numbers.
class PdfNumber extends PdfObject {
  /// The numeric value.
  double _value;

  /// Creates a PdfNumber from a double.
  PdfNumber(double value) : _value = value;

  /// Creates a PdfNumber from an int.
  PdfNumber.fromInt(int value) : _value = value.toDouble();

  /// Creates a PdfNumber from bytes.
  factory PdfNumber.fromBytes(Uint8List content) {
    final str = String.fromCharCodes(content);
    return PdfNumber(double.parse(str));
  }

  @override
  int getObjectType() => PdfObjectType.number;

  @override
  PdfObject clone() {
    return PdfNumber(_value);
  }

  @override
  PdfObject newInstance() {
    return PdfNumber(0);
  }

  /// Gets the value as double.
  double getValue() => _value;

  /// Sets the value.
  void setValue(double value) {
    _value = value;
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
  }

  /// Decrements the value.
  void decrement() {
    _value--;
  }

  /// Checks if value has decimal part.
  bool hasDecimalPart() {
    return _value != _value.truncateToDouble();
  }

  /// Generates byte representation for PDF output.
  Uint8List generateContent() {
    if (!hasDecimalPart()) {
      return ByteUtils.getIsoBytesFromInt(intValue());
    }
    return ByteUtils.getIsoBytesFromDouble(_value);
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
    if (other is! PdfNumber) return false;
    return _value == other._value;
  }

  @override
  int get hashCode => _value.hashCode;
}
