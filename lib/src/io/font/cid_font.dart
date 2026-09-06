import '../../io/util/string_tokenizer.dart';
import '../../io/util/int_hashtable.dart';
import 'cid_font_properties.dart';
import 'cjk_resource_loader.dart';
import 'cmap/cmap_uni_cid.dart';
import 'font_names.dart';
import 'font_program.dart';
import 'otf/glyph.dart';
import 'pdf_encodings.dart';

class CidFont extends FontProgram {
  final String _fontName;
  int _pdfFontFlags = 0;
  final Set<String>? _compatibleCmaps;

  CidFont(this._fontName, String cmap, [this._compatibleCmaps]) {
    fontNames = FontNames();
    _initializeCidFontNameAndStyle(_fontName);
    Map<String, dynamic>? fontDesc =
        CidFontProperties.getAllFonts()[fontNames.getFontName()];
    if (fontDesc == null) {
      throw Exception("There is no such predefined font: $_fontName");
    }
    _initializeCidFontProperties(fontDesc, cmap);
  }

  bool compatibleWith(String cmap) {
    if (cmap == PdfEncodings.IDENTITY_H || cmap == PdfEncodings.IDENTITY_V) {
      return true;
    } else {
      return _compatibleCmaps != null && _compatibleCmaps.contains(cmap);
    }
  }

  @override
  int getKerningByGlyph(Glyph glyph1, Glyph glyph2) {
    return 0;
  }

  @override
  int getPdfFontFlags() {
    return _pdfFontFlags;
  }

  @override
  bool getIsFontSpecific() {
    return false;
  }

  @override
  bool isBuiltWith(String fontName) {
    return this._fontName == fontName;
  }

  void _initializeCidFontNameAndStyle(String fontName) {
    String? nameBase = FontProgram.trimFontStyle(fontName);
    if (nameBase != null && nameBase.length < fontName.length) {
      fontNames.setFontName(fontName);
      fontNames.setStyle(fontName.substring(nameBase.length));
    } else {
      fontNames.setFontName(fontName);
    }
    fontNames.setFullName([
      ["", "", "", fontNames.getFontName()!]
    ]);
  }

  void _initializeCidFontProperties(
      Map<String, dynamic> fontDesc, String cmap) {
    fontMetrics.setItalicAngle(
        double.tryParse(fontDesc["ItalicAngle"]?.toString() ?? "0") ?? 0.0);
    fontMetrics.setCapHeight(
        int.tryParse(fontDesc["CapHeight"]?.toString() ?? "0") ?? 0);
    fontMetrics.setTypoAscender(
        int.tryParse(fontDesc["Ascent"]?.toString() ?? "0") ?? 0);
    fontMetrics.setTypoDescender(
        int.tryParse(fontDesc["Descent"]?.toString() ?? "0") ?? 0);
    fontMetrics
        .setStemV(int.tryParse(fontDesc["StemV"]?.toString() ?? "0") ?? 0);
    _pdfFontFlags = int.tryParse(fontDesc["Flags"]?.toString() ?? "0") ?? 0;

    String? fontBBox = fontDesc["FontBBox"] as String?;
    if (fontBBox != null) {
      StringTokenizer tk = StringTokenizer(fontBBox, " []\r\n\t\f");
      double llx = double.tryParse(tk.nextToken()) ?? 0.0;
      double lly = double.tryParse(tk.nextToken()) ?? 0.0;
      double urx = double.tryParse(tk.nextToken()) ?? 0.0;
      double ury = double.tryParse(tk.nextToken()) ?? 0.0;
      fontMetrics.updateBbox(llx, lly, urx, ury);
    }

    registry = fontDesc["Registry"] as String?;
    String? uniMap = _getCompatibleUniMap(registry ?? "", cmap);
    if (uniMap != null) {
      IntHashtable? metrics = fontDesc["W"] as IntHashtable?;
      CMapUniCid uni2cid = CjkResourceLoader.getUni2CidCmapSync(uniMap);
      avgWidth = 0;
      for (int cp in uni2cid.getCodePoints()) {
        int cid = uni2cid.lookup(cp);
        int width = (metrics != null && metrics.containsKey(cid))
            ? metrics.get(cid)
            : FontProgram.DEFAULT_WIDTH;
        Glyph glyph = Glyph(cid, width, cp);
        avgWidth += glyph.getWidth();
        codeToGlyph[cid] = glyph;
        unicodeToGlyph[cp] = glyph;
      }
      fixSpaceIssue();
      if (codeToGlyph.isNotEmpty) {
        avgWidth ~/= codeToGlyph.length;
      }
    }
  }

  static String? _getCompatibleUniMap(String registry, String cmap) {
    Set<String>? compatibleUniMaps =
        CidFontProperties.getRegistryNames()["${registry}_Uni"];
    if (compatibleUniMaps == null) return null;
    if (compatibleUniMaps.contains(cmap)) {
      return cmap;
    }
    String? uniMap;
    for (String name in compatibleUniMaps) {
      uniMap = name;
      if (name.endsWith("H")) {
        return name;
      }
    }
    return uniMap;
  }
}
