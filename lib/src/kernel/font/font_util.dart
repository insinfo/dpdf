import 'dart:typed_data';
import 'package:dpdf/src/io/font/otf/glyph.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/io/font/cmap/cmap_content_parser.dart';

class FontUtil {
  static PdfStream? getToUnicodeStream(Iterable<Glyph> glyphs) {
    BytesBuilder builder = BytesBuilder();
    builder.add(utf8Encode("/CIDInit /ProcSet findresource begin\n"
        "12 dict begin\n"
        "begincmap\n"
        "/CIDSystemInfo\n"
        "<< /Registry (Adobe)\n"
        "/Ordering (UCS)\n"
        "/Supplement 0\n"
        ">> def\n"
        "/CMapName /Adobe-Identity-UCS def\n"
        "/CMapType 2 def\n"
        "1 begincodespacerange\n"
        "<0000><FFFF>\n"
        "endcodespacerange\n"));

    List<Glyph> glyphGroup = [];
    int bfranges = 0;
    for (Glyph glyph in glyphs) {
      if (glyph.getChars() != null) {
        glyphGroup.add(glyph);
        if (glyphGroup.length == 100) {
          bfranges += _writeBfrange(builder, glyphGroup);
        }
      }
    }
    bfranges += _writeBfrange(builder, glyphGroup);

    if (bfranges == 0) {
      return null;
    }

    builder.add(utf8Encode("endcmap\n"
        "CMapName currentdict /CMap defineresource pop\n"
        "end end\n"));

    return PdfStream.withBytes(builder.toBytes());
  }

  static int _writeBfrange(BytesBuilder builder, List<Glyph> range) {
    if (range.isEmpty) {
      return 0;
    }
    builder.add(utf8Encode("${range.length} beginbfrange\n"));
    for (Glyph glyph in range) {
      String fromTo = CMapContentParser.toHex(glyph.getCode());
      builder.add(utf8Encode("$fromTo $fromTo <"));
      for (int ch in glyph.getChars()!) {
        builder.add(
            utf8Encode(ch.toRadixString(16).padLeft(4, '0').toUpperCase()));
      }
      builder.add(utf8Encode(">\n"));
    }
    builder.add(utf8Encode("endbfrange\n"));
    range.clear();
    return 1;
  }

  static List<int> utf8Encode(String s) => Uint8List.fromList(s.codeUnits);
}
