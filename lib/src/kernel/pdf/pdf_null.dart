import 'dart:typed_data';

import 'pdf_object.dart';
import 'pdf_primitive_object.dart';

/// Represents a PDF null object.
class CraftPdfNull extends CraftPdfPrimitiveObject {
  /// Singleton instance.
  static final CraftPdfNull pdfNull = CraftPdfNull._internal();

  static final Uint8List _nullBytes =
      Uint8List.fromList([110, 117, 108, 108]); // 'null'

  /// Private constructor for singleton.
  CraftPdfNull._internal() {
    setContent(_nullBytes);
  }

  /// Returns the singleton null instance.
  factory CraftPdfNull() => pdfNull;

  @override
  int objectKind() => PdfObjectType.nullType;

  @override
  CraftPdfObject clone() => CraftPdfNull._internal();

  @override
  CraftPdfObject newInstance() => pdfNull;

  @override
  void generateContent() {
    setContent(_nullBytes);
  }

  @override
  String toString() => 'null';

  @override
  bool operator ==(Object other) => other is CraftPdfNull;

  @override
  int get hashCode => 0;
}
