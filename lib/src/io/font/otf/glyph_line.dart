import 'glyph.dart';

class GlyphLine {
  int start = 0;
  int end = 0;
  int idx = 0;
  List<Glyph> glyphs;
  List<ActualText?>? actualText;

  GlyphLine(this.glyphs)
      : start = 0,
        end = glyphs.length;

  GlyphLine.fromSlice(this.glyphs, this.start, this.end);

  GlyphLine.withActualText(this.glyphs, this.actualText, this.start, this.end);

  GlyphLine.copy(GlyphLine other)
      : glyphs = other.glyphs,
        actualText = other.actualText,
        start = other.start,
        end = other.end,
        idx = other.idx;

  GlyphLine.copySlice(GlyphLine other, int start, int end)
      : glyphs = other.glyphs.sublist(start, end),
        actualText = other.actualText?.sublist(start, end),
        start = 0,
        end = end - start,
        idx = other.idx - start;

  int getStart() => start;
  void setStart(int start) => this.start = start;

  int getEnd() => end;
  void setEnd(int end) => this.end = end;

  int getIdx() => idx;
  void setIdx(int idx) => this.idx = idx;

  Glyph get(int index) => glyphs[index];

  Glyph set(int index, Glyph glyph) {
    glyphs[index] = glyph;
    return glyph;
  }

  void add(Glyph glyph) {
    glyphs.add(glyph);
    if (actualText != null) {
      actualText!.add(null);
    }
  }

  int size() => glyphs.length;

  @override
  String toString() {
    // Simplification: just return unicode string of range
    StringBuffer sb = StringBuffer();
    for (int i = start; i < end; i++) {
      sb.write(glyphs[i].getUnicodeString());
    }
    return sb.toString();
  }
}

class ActualText {
  final String value;
  ActualText(this.value);
  String getValue() => value;
}
