import '../../source/pdf_tokenizer.dart';

abstract class CraftCMapLocation {
  Future<CraftPdfTokenizer> getLocation(String location);
  CraftPdfTokenizer getLocationSync(String location);
}
