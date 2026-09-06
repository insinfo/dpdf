import 'dart:typed_data';

import 'pdf_object.dart';
import 'pdf_primitive_object.dart';

/// Represents a PDF null object.
class PdfNull extends PdfPrimitiveObject {
  /// Singleton instance.
  static final PdfNull pdfNull = PdfNull._internal();

  static final Uint8List _nullBytes =
      Uint8List.fromList([110, 117, 108, 108]); // 'null'

  /// Private constructor for singleton.
  PdfNull._internal() {
    setContent(_nullBytes);
  }

  /// Returns the singleton null instance.
  factory PdfNull() => pdfNull;

  @override
  int getObjectType() => PdfObjectType.nullType;

  @override
  PdfObject clone() => pdfNull;

  @override
  PdfObject newInstance() => pdfNull;

  @override
  void generateContent() {
    setContent(_nullBytes);
  }

  @override
  String toString() => 'null';

  @override
  bool operator ==(Object other) => other is PdfNull;

  @override
  int get hashCode => 0;
}
