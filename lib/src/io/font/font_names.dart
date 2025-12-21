import 'constants/font_weights.dart';
import 'constants/font_stretches.dart';
import 'constants/font_mac_style_flags.dart';

class FontNames {
  Map<int, List<List<String>>>? allNames;

  List<List<String>>? fullName;
  List<List<String>>? familyName;
  List<List<String>>? familyName2;
  List<List<String>>? subfamily;

  String? fontName;
  String style = "";
  String? cidFontName;

  int weight = FontWeights.NORMAL;
  String fontStretch = FontStretches.NORMAL;
  int macStyle = 0;
  bool allowEmbedding = false;

  List<List<String>>? getNames(int id) {
    var names = allNames?[id];
    return (names != null && names.isNotEmpty) ? names : null;
  }

  List<List<String>>? getFullName() => fullName;

  String? getFontName() => fontName;

  String? getCidFontName() => cidFontName;

  List<List<String>>? getFamilyName() => familyName;

  List<List<String>>? getFamilyName2() => familyName2;

  String getStyle() => style;

  String getSubfamily() =>
      (subfamily != null && subfamily!.isNotEmpty) ? subfamily![0][3] : "";

  int getFontWeight() => weight;

  void setFontWeight(int weight) {
    this.weight = FontWeights.normalizeFontWeight(weight);
  }

  String getFontStretch() => fontStretch;

  void setFontStretch(String fontStretch) {
    this.fontStretch = fontStretch;
  }

  bool isAllowEmbedding() => allowEmbedding;

  bool isBold() => (macStyle & FontMacStyleFlags.BOLD) != 0;

  bool isItalic() => (macStyle & FontMacStyleFlags.ITALIC) != 0;

  bool isUnderline() => (macStyle & FontMacStyleFlags.UNDERLINE) != 0;

  bool isOutline() => (macStyle & FontMacStyleFlags.OUTLINE) != 0;

  bool isShadow() => (macStyle & FontMacStyleFlags.SHADOW) != 0;

  bool isCondensed() => (macStyle & FontMacStyleFlags.CONDENSED) != 0;

  bool isExtended() => (macStyle & FontMacStyleFlags.EXTENDED) != 0;

  void setAllNames(Map<int, List<List<String>>> allNames) {
    this.allNames = allNames;
  }

  void setFullName(List<List<String>> fullName) {
    this.fullName = fullName;
  }

  void setFullNameString(String fullName) {
    this.fullName = [
      ["", "", "", fullName]
    ];
  }

  void setFontName(String psFontName) {
    this.fontName = psFontName;
  }

  void setCidFontName(String cidFontName) {
    this.cidFontName = cidFontName;
  }

  void setFamilyName(List<List<String>> familyName) {
    this.familyName = familyName;
  }

  void setFamilyName2(List<List<String>> familyName2) {
    this.familyName2 = familyName2;
  }

  void setFamilyNameString(String familyName) {
    this.familyName = [
      ["", "", "", familyName]
    ];
  }

  void setStyle(String style) {
    this.style = style;
  }

  void setSubfamilyString(String subfamily) {
    this.subfamily = [
      ["", "", "", subfamily]
    ];
  }

  void setSubfamily(List<List<String>> subfamily) {
    this.subfamily = subfamily;
  }

  void setMacStyle(int macStyle) {
    this.macStyle = macStyle;
  }

  int getMacStyle() => macStyle;

  void setAllowEmbedding(bool allowEmbedding) {
    this.allowEmbedding = allowEmbedding;
  }

  @override
  String toString() {
    return fontName != null && fontName!.isNotEmpty
        ? fontName!
        : super.toString();
  }
}
