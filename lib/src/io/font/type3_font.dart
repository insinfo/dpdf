import 'font_program.dart';
import 'otf/glyph.dart';

class Type3Font extends FontProgram {
  int firstChar = 0;
  int lastChar = 0;
  List<double>? widths;
  List<double> fontMatrix = [0.001, 0, 0, 0.001, 0, 0];
  List<double>? fontBBox;

  // Type3 specific properties
  // CharProcs is a dictionary of streams, but here we might just store keys/names?
  // Or maybe we don't store CharProcs here but use them to create Glyphs.

  Type3Font() {
    // Type3 fonts are typically FontSpecific
    encodingScheme = "FontSpecific";
  }

  @override
  int getPdfFontFlags() {
    return 0; // Flags aren't usually set for Type3
  }

  @override
  int getKerningByGlyph(Glyph first, Glyph second) {
    return 0;
  }
}
