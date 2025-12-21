import 'pdf_object.dart';

/// Represents a PDF null object.
class PdfNull extends PdfObject {
  /// Singleton instance.
  static final PdfNull pdfNull = PdfNull._internal();

  /// Private constructor for singleton.
  PdfNull._internal();

  /// Returns the singleton null instance.
  factory PdfNull() => pdfNull;

  @override
  int getObjectType() => PdfObjectType.nullType;

  @override
  PdfObject clone() => pdfNull;

  @override
  PdfObject newInstance() => pdfNull;

  @override
  String toString() => 'null';

  @override
  bool operator ==(Object other) => other is PdfNull;

  @override
  int get hashCode => 0;
}
