import '../../source/pdf_tokenizer.dart';

abstract class ICMapLocation {
  Future<PdfTokenizer> getLocation(String location);
  PdfTokenizer getLocationSync(String location);
}
