import 'dart:typed_data';
import 'package:dpdf/src/io/font/abstract_true_type_font_modifier.dart';
import 'package:dpdf/src/io/font/open_type_parser.dart';

class TrueTypeFontSubsetter extends AbstractTrueTypeFontModifier {
  TrueTypeFontSubsetter(String fontName, OpenTypeParser parser,
      Iterable<int> glyphs, bool subsetTables)
      : super(fontName, subsetTables) {
    horizontalMetricMap = {};
    glyphDataMap = {};
    List<int> usedGlyphs = parser.getFlatGlyphs(glyphs);
    for (int glyph in usedGlyphs) {
      Uint8List glyphData = parser.getGlyphDataForGid(glyph);
      glyphDataMap[glyph] = glyphData;
      Uint8List glyphMetric = parser.getHorizontalMetricForGid(glyph);
      horizontalMetricMap[glyph] = glyphMetric;
    }
    raf = parser.raf.createView();
    directoryOffset = parser.directoryOffset;
    numberOfHMetrics = parser.hhea.numberOfHMetrics;
  }

  @override
  int mergeTables() {
    return createModifiedTables();
  }
}
