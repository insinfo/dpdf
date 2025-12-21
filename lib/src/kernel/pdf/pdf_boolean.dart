import 'pdf_object.dart';

/// Represents a PDF boolean object.
class PdfBoolean extends PdfObject {
  /// Singleton for true.
  static final PdfBoolean pdfTrue = PdfBoolean._internal(true);

  /// Singleton for false.
  static final PdfBoolean pdfFalse = PdfBoolean._internal(false);

  /// The boolean value.
  final bool _value;

  /// Private constructor for singletons.
  PdfBoolean._internal(this._value);

  /// Creates a PdfBoolean with the given value.
  ///
  /// Returns singleton instances for true and false.
  factory PdfBoolean(bool value) {
    return value ? pdfTrue : pdfFalse;
  }

  @override
  int getObjectType() => PdfObjectType.boolean;

  @override
  PdfObject clone() {
    return PdfBoolean(_value);
  }

  @override
  PdfObject newInstance() {
    return PdfBoolean(false);
  }

  /// Gets the boolean value.
  bool getValue() => _value;

  @override
  String toString() {
    return _value ? 'true' : 'false';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PdfBoolean) return false;
    return _value == other._value;
  }

  @override
  int get hashCode => _value.hashCode;
}
