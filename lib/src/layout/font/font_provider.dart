import 'package:dpdf/src/kernel/font/pdf_font.dart';

class CraftFontInfo {
  // Stub
}

class CraftFontSet {
  final List<CraftFontInfo> _fonts = [];
  List<CraftFontInfo> getFonts() => _fonts;
  bool isEmpty() => _fonts.isEmpty;
}

class CraftFontProvider {
  final CraftFontSet fontSet;
  CraftFontProvider([CraftFontSet? fontSet])
      : this.fontSet = fontSet ?? CraftFontSet();

  CraftPdfFont? getPdfFont(CraftFontInfo fontInfo) => null;
}

class CraftBasicFontProvider extends CraftFontProvider {
  CraftBasicFontProvider() : super();
}
