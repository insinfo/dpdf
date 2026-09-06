import 'package:dpdf/src/kernel/font/pdf_font.dart';

class FontInfo {
  // Stub
}

class FontSet {
  final List<FontInfo> _fonts = [];
  List<FontInfo> getFonts() => _fonts;
  bool isEmpty() => _fonts.isEmpty;
}

class FontProvider {
  final FontSet fontSet;
  FontProvider([FontSet? fontSet]) : this.fontSet = fontSet ?? FontSet();

  PdfFont? getPdfFont(FontInfo fontInfo) => null;
}

class BasicFontProvider extends FontProvider {
  BasicFontProvider() : super();
}
