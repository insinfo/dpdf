import 'dart:typed_data';
import 'package:itext/src/io/font/adobe_glyph_list.dart';

import 'package:itext/src/io/font/font_program.dart';

import 'package:itext/src/io/font/otf/glyph.dart';
import 'package:itext/src/io/font/type1_parser.dart';
import 'package:itext/src/io/source/random_access_file_or_array.dart';
import 'package:itext/src/io/util/string_tokenizer.dart';

class Type1Font extends FontProgram {
  static final List<int> PFB_TYPES = [1, 2, 1];

  Type1Parser? fontParser;
  String? characterSet;
  Map<int, int> kernPairs =
      {}; // long, int? in C#, assuming first<<32 + second key
  Uint8List? fontStreamBytes;
  List<int>? fontStreamLengths;

  Type1Font(
      String metricsPath, String binaryPath, Uint8List? afm, Uint8List? pfb) {
    fontParser = Type1Parser(metricsPath, binaryPath, afm, pfb);
    process();
  }

  // TODO: Constructor from baseFont name only (StandardFonts)

  @override
  int getPdfFontFlags() {
    int flags = 0;
    if (fontMetrics.getIsFixedPitch()) {
      flags |= 1;
    }
    flags |= getIsFontSpecific() ? 4 : 32;
    if (fontMetrics.getItalicAngle() < 0) {
      flags |= 64;
    }
    String? fontName = fontNames.getFontName();
    if (fontName != null &&
        (fontName.contains("Caps") || fontName.endsWith("SC"))) {
      flags |= 131072;
    }
    if (fontNames.isBold() || fontNames.getFontWeight() > 500) {
      flags |= 262144;
    }
    return flags;
  }

  @override
  bool hasKernPairs() => kernPairs.isNotEmpty;

  @override
  int getKerningByGlyph(Glyph first, Glyph second) {
    if (first.hasValidUnicode() && second.hasValidUnicode()) {
      int record = (first.getUnicode() << 32) +
          second.getUnicode(); // TODO: 64-bit int in Dart?
      // Dart ints are 64-bit on VM, but JS is 53-bit.
      // For IO/Server side it's fine.
      // If web, big int issue. But we are targeting VM/Flutter locally now.
      if (kernPairs.containsKey(record)) {
        return kernPairs[record]!;
      }
    }
    return 0;
  }

  // Implementation of abstract getKerning(int, int) is in FontProgram

  void process() {
    if (fontParser == null) return;
    RandomAccessFileOrArray raf = fontParser!.getMetricsFile();
    String? line;
    bool startKernPairs = false;

    try {
      while (!startKernPairs && (line = raf.readLine()) != null) {
        StringTokenizer tok = StringTokenizer(line!, " ,\n\r\t\f");
        if (!tok.hasMoreTokens()) continue;

        String ident = tok.nextToken();
        switch (ident) {
          case "FontName":
            fontNames.setFontName(tok.nextToken("\u00ff").substring(1));
            break;
          case "FullName":
            fontNames.setFullNameString(tok.nextToken("\u00ff").substring(1));
            break;
          case "FamilyName":
            fontNames.setFamilyNameString(tok.nextToken("\u00ff").substring(1));
            break;
          case "Weight":
            // fontNames.setFontWeight(FontWeights.fromType1FontWeight(...)); // TODO implement helper
            break;
          case "ItalicAngle":
            fontMetrics.setItalicAngle(double.parse(tok.nextToken()));
            break;
          case "IsFixedPitch":
            fontMetrics.setIsFixedPitch(tok.nextToken() == "true");
            break;
          case "CharacterSet":
            characterSet = tok.nextToken("\u00ff").substring(1);
            break;
          case "FontBBox":
            int llx = double.parse(tok.nextToken()).toInt();
            int lly = double.parse(tok.nextToken()).toInt();
            int urx = double.parse(tok.nextToken()).toInt();
            int ury = double.parse(tok.nextToken()).toInt();
            fontMetrics.setBbox(llx, lly, urx, ury);
            break;
          case "UnderlinePosition":
            fontMetrics
                .setUnderlinePosition(double.parse(tok.nextToken()).toInt());
            break;
          case "UnderlineThickness":
            fontMetrics
                .setUnderlineThickness(double.parse(tok.nextToken()).toInt());
            break;
          case "EncodingScheme":
            encodingScheme = tok.nextToken("\u00ff").substring(1).trim();
            break;
          case "CapHeight":
            fontMetrics.setCapHeight(double.parse(tok.nextToken()).toInt());
            break;
          case "XHeight":
            fontMetrics.setXHeight(double.parse(tok.nextToken()).toInt());
            break;
          case "Ascender":
            fontMetrics.setTypoAscender(double.parse(tok.nextToken()).toInt());
            break;
          case "Descender":
            fontMetrics.setTypoDescender(double.parse(tok.nextToken()).toInt());
            break;
          case "StdHW":
            fontMetrics.setStemH(double.parse(tok.nextToken()).toInt());
            break;
          case "StdVW":
            fontMetrics.setStemV(double.parse(tok.nextToken()).toInt());
            break;
          case "StartCharMetrics":
            startKernPairs = true;
            break;
        }
      }

      if (!startKernPairs) {
        throw Exception("startcharmetrics is missing in the metrics file.");
      }

      avgWidth = 0;
      int widthCount = 0;

      while ((line = raf.readLine()) != null) {
        StringTokenizer tok = StringTokenizer(line!);
        if (!tok.hasMoreTokens()) continue;

        String ident = tok.nextToken();
        if (ident == "EndCharMetrics") {
          startKernPairs = false;
          break;
        }

        int C = -1;
        int WX = 250;
        String N = "";
        List<int>? B;

        StringTokenizer tokLine = StringTokenizer(line, ";");
        while (tokLine.hasMoreTokens()) {
          StringTokenizer tokc = StringTokenizer(tokLine.nextToken());
          if (!tokc.hasMoreTokens()) continue;

          ident = tokc.nextToken();
          switch (ident) {
            case "C":
              C = int.parse(tokc.nextToken());
              break;
            case "WX":
              WX = double.parse(tokc.nextToken()).toInt();
              break;
            case "N":
              N = tokc.nextToken();
              break;
            case "B":
              B = [
                int.parse(tokc.nextToken()),
                int.parse(tokc.nextToken()),
                int.parse(tokc.nextToken()),
                int.parse(tokc.nextToken())
              ];
              break;
          }
        }

        int unicode = AdobeGlyphList.nameToUnicode(N);
        Glyph glyph = Glyph(C, WX, unicode, B);

        if (C >= 0) {
          codeToGlyph[C] = glyph;
        }
        if (unicode != -1) {
          unicodeToGlyph[unicode] = glyph;
        }
        avgWidth += WX;
        widthCount++;
      }

      if (widthCount != 0) avgWidth ~/= widthCount;

      // Add 00A0 non breaking space if missing
      if (!unicodeToGlyph.containsKey(0x00A0)) {
        if (unicodeToGlyph.containsKey(0x0020)) {
          Glyph space = unicodeToGlyph[0x0020]!;
          unicodeToGlyph[0x00A0] =
              Glyph(space.getCode(), space.getWidth(), 0x00A0, space.getBbox());
        }
      }

      while ((line = raf.readLine()) != null) {
        StringTokenizer tok = StringTokenizer(line!);
        if (!tok.hasMoreTokens()) continue;
        String ident = tok.nextToken();
        if (ident == "EndFontMetrics") {
          break;
        } else if (ident == "StartKernPairs") {
          startKernPairs = true;
          break;
        }
      }

      if (startKernPairs) {
        while ((line = raf.readLine()) != null) {
          StringTokenizer tok = StringTokenizer(line!);
          if (!tok.hasMoreTokens()) continue;
          String ident = tok.nextToken();
          if (ident == "KPX") {
            String first = tok.nextToken();
            String second = tok.nextToken();
            int width = double.parse(tok.nextToken()).toInt();
            int u1 = AdobeGlyphList.nameToUnicode(first);
            int u2 = AdobeGlyphList.nameToUnicode(second);
            if (u1 != -1 && u2 != -1) {
              // Dart ints are 64-bit signed
              int record = (u1 << 32) + u2;
              kernPairs[record] = width;
            }
          } else if (ident == "EndKernPairs") {
            startKernPairs = false;
            break;
          }
        }
      }
    } finally {
      raf.close();
    }

    isFontSpecific = !(encodingScheme == "AdobeStandardEncoding" ||
        encodingScheme == "StandardEncoding");
  }

  Uint8List? getFontStreamBytes() {
    // TODO: Implement stream reading from PFB
    if (fontStreamBytes == null && fontParser != null) {
      // The original try-catch block for reading stream bytes was empty and commented out.
      // As per instruction "remove unused code", this block is removed.
    }
    return fontStreamBytes;
  }

  bool isBuiltInFont() {
    return fontParser?.isBuiltInFont() ?? false;
  }
}
