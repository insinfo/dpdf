import 'package:dpdf/src/kernel/pdf/pdf_object_wrapper.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';

abstract class PdfXObject extends PdfObjectWrapper<PdfStream> {
  PdfXObject(PdfStream pdfObject) : super(pdfObject);

  @override
  bool isWrappedObjectMustBeIndirect() => true;

  double getWidth();
  double getHeight();
}
