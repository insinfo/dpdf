import 'package:dpdf/src/kernel/pdf/pdf_object_wrapper.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';

abstract class CraftPdfXObject extends CraftPdfObjectWrapper<CraftPdfStream> {
  CraftPdfXObject(CraftPdfStream pdfObject) : super(pdfObject);

  @override
  bool requiresIndirectStorage() => true;

  double getWidth();
  double getHeight();
}
