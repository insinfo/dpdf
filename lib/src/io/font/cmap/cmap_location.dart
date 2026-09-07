import '../../source/pdf_tokenizer.dart';

abstract class CMapLocation {
  Future<PdfTokenizer> getLocation(String location);
  PdfTokenizer getLocationSync(String location);
}
