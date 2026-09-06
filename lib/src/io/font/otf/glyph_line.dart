import 'glyph.dart';

class CraftGlyphLine {
  int start = 0;
  int end = 0;
  int idx = 0;
  List<CraftGlyph> glyphs;
  List<ActualText?>? actualText;

  CraftGlyphLine(this.glyphs)
      : start = 0,
        end = glyphs.length;

  CraftGlyphLine.fromSlice(this.glyphs, this.start, this.end);

  CraftGlyphLine.withActualText(
      this.glyphs, this.actualText, this.start, this.end);

  CraftGlyphLine.copy(CraftGlyphLine other)
      : glyphs = other.glyphs,
        actualText = other.actualText,
        start = other.start,
        end = other.end,
        idx = other.idx;

  CraftGlyphLine.copySlice(CraftGlyphLine other, int start, int end)
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

  CraftGlyph get(int index) => glyphs[index];

  CraftGlyph set(int index, CraftGlyph glyph) {
    glyphs[index] = glyph;
    return glyph;
  }

  void add(CraftGlyph glyph) {
    glyphs.add(glyph);
    if (actualText != null) {
      actualText!.add(null);
    }
  }

  int size() => glyphs.length;

  Iterable<GlyphLinePart> iterator() {
    // We will implement ActualTextIterator soon
    return ActualTextIterable(this);
  }

  @override
  String toString() {
    // Mimic 's ToUnicodeString logic
    StringBuffer str = StringBuffer();
    final iter = iterator().iterator;
    while (iter.moveNext()) {
      final part = iter.current;
      if (part.getActualText() != null) {
        str.write(part.getActualText());
      } else {
        for (int i = part.getStart(); i < part.getEnd(); i++) {
          str.write(glyphs[i].getUnicodeString());
        }
      }
    }
    return str.toString();
  }
}

class GlyphLinePart {
  int start;
  int end;
  String? actualText;
  bool reversed = false;

  GlyphLinePart(this.start, this.end, [this.actualText]);

  int getStart() => start;
  void setStart(int start) => this.start = start;

  int getEnd() => end;
  void setEnd(int end) => this.end = end;

  String? getActualText() => actualText;
  void setActualText(String? actualText) => this.actualText = actualText;

  bool isReversed() => reversed;
  void setReversed(bool reversed) => this.reversed = reversed;
}

class ActualText {
  final String value;
  ActualText(this.value);
  String getValue() => value;
}

// Helper classes for iteration
class ActualTextIterable extends Iterable<GlyphLinePart> {
  final CraftGlyphLine glyphLine;
  ActualTextIterable(this.glyphLine);

  @override
  Iterator<GlyphLinePart> get iterator => CraftActualTextIterator(glyphLine);
}

class CraftActualTextIterator implements Iterator<GlyphLinePart> {
  final CraftGlyphLine glyphLine;
  int pos;
  GlyphLinePart? _current;

  CraftActualTextIterator(this.glyphLine) : pos = glyphLine.getStart();

  @override
  GlyphLinePart get current => _current!;

  @override
  bool moveNext() {
    if (pos >= glyphLine.getEnd()) return false;

    if (glyphLine.actualText == null) {
      _current = GlyphLinePart(pos, glyphLine.getEnd(), null);
      pos = glyphLine.getEnd();
      return true;
    } else {
      _current = _nextGlyphLinePart();
      if (_current == null) return false;

      if (!_glyphLinePartNeedsActualText(_current!)) {
        _current!.setActualText(null);
        while (pos < glyphLine.getEnd()) {
          final nextResult = _nextGlyphLinePart(peek: true);
          if (nextResult != null &&
              !_glyphLinePartNeedsActualText(nextResult)) {
            _current!.setEnd(nextResult.getEnd());
            pos = nextResult.getEnd();
          } else {
            break;
          }
        }
      } else {
        pos = _current!.getEnd();
      }
      return true;
    }
  }

  GlyphLinePart? _nextGlyphLinePart({bool peek = false}) {
    int currentPos = peek ? pos : pos; // pos is updated later if not peek
    if (currentPos >= glyphLine.getEnd()) return null;

    int startPos = currentPos;
    ActualText? startActualText = glyphLine.actualText![currentPos];
    int nextPos = currentPos;
    while (nextPos < glyphLine.getEnd() &&
        glyphLine.actualText![nextPos] == startActualText) {
      nextPos++;
    }
    if (!peek) pos = nextPos;
    return GlyphLinePart(startPos, nextPos, startActualText?.getValue());
  }

  bool _glyphLinePartNeedsActualText(GlyphLinePart part) {
    if (part.getActualText() == null) return false;

    bool needsActualText = false;
    StringBuffer toUnicodeMapResult = StringBuffer();
    for (int i = part.getStart(); i < part.getEnd(); i++) {
      final glyph = glyphLine.glyphs[i];
      if (!glyph.hasValidUnicode()) {
        needsActualText = true;
        break;
      }
      toUnicodeMapResult.write(glyph.getUnicodeString());
    }
    return needsActualText ||
        toUnicodeMapResult.toString() != part.getActualText();
  }
}
