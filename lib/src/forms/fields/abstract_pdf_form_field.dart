import '../../kernel/pdf/pdf_dictionary.dart';
import '../../kernel/pdf/pdf_object.dart';
import '../../kernel/pdf/pdf_object_wrapper.dart';
import '../../kernel/pdf/pdf_name.dart';
import '../../kernel/pdf/pdf_string.dart';
import '../../kernel/pdf/pdf_document.dart';
import '../../kernel/font/pdf_font.dart';
import '../../kernel/colors/color.dart';
import '../../kernel/colors/device_gray.dart';
import '../../kernel/colors/device_rgb.dart';
import '../../kernel/colors/device_cmyk.dart';
import '../../io/source/pdf_tokenizer.dart';
import '../../io/source/random_access_file_or_array.dart';
import '../../commons/utils/encoding_util.dart';

import 'pdf_form_field.dart';

abstract class CraftAbstractPdfFormField
    extends CraftPdfObjectWrapper<CraftPdfDictionary> {
  static const int defaultFontSize = 12;
  static const int minFontSize = 4;

  static const int _daFont = 0;
  static const int _daSize = 1;
  static const int _daColor = 2;

  CraftPdfFont? _font;
  double _fontSize = -1;
  CraftColor? _color;
  CraftPdfFormField? _parent;

  CraftAbstractPdfFormField(CraftPdfDictionary pdfObject) : super(pdfObject) {
    if (requiresIndirectStorage()) {
      CraftPdfObjectWrapper.markObjectAsIndirect(pdfObject);
    }
    setForbidRelease();
    _retrieveStyles();
  }

  @override
  bool requiresIndirectStorage() => true;

  void setParent(CraftPdfFormField parent) {
    put(CraftPdfName.parent, parent.pdfRepresentation());
    _parent = parent;
  }

  Future<CraftPdfDictionary?> getParent() async {
    final p = await pdfRepresentation().dictionaryEntry(CraftPdfName.parent);
    if (p != null) return p;
    return _parent?.pdfRepresentation();
  }

  CraftPdfFormField? getParentField() => _parent;

  Future<CraftPdfString?> getFieldName() async {
    return pdfRepresentation().stringEntry(CraftPdfName.t); // T = Terminal Name
  }

  Future<CraftPdfString?> getDefaultAppearance() async {
    // Inheritable
    CraftPdfString? da = await pdfRepresentation().stringEntry(CraftPdfName.da);
    if (da == null && _parent != null) {
      return await _parent!.getDefaultAppearance();
    }
    return da;
  }

  CraftPdfFont? resolveTypeface() => _font;
  double getFontSize() => _fontSize;
  CraftColor? getColor() => _color;

  void _retrieveStyles() async {
    final da = await getDefaultAppearance();
    if (da != null) {
      final fontData = await _splitDAelements(da.getValue());
      if (fontData[_daSize] != null && fontData[_daFont] != null) {
        _fontSize = (fontData[_daSize] as num).toDouble();
        _color = fontData[_daColor] as CraftColor?;
        final fontName = fontData[_daFont] as String;
        _font = await resolveFontName(fontName);
      }
    }
  }

  static Future<List<Object?>> _splitDAelements(String da) async {
    final bytes = CraftEncodingUtil.convertToBytes(da, "Latin1");
    final tokenizer = CraftPdfTokenizer(CraftRandomAccessFileOrArray(bytes));
    final stack = <String>[];
    final ret = List<Object?>.filled(3, null);

    try {
      while (await tokenizer.nextToken()) {
        if (tokenizer.getTokenType() == TokenType.comment) continue;
        if (tokenizer.getTokenType() == TokenType.other) {
          final operator = tokenizer.getStringValue();
          switch (operator) {
            case "Tf":
              if (stack.length >= 2) {
                ret[_daFont] = stack[stack.length - 2];
                ret[_daSize] = double.tryParse(stack.last) ?? 0.0;
              }
              break;
            case "g":
              if (stack.isNotEmpty) {
                final gray = double.tryParse(stack.last) ?? 0.0;
                if (gray != 0) {
                  ret[_daColor] = CraftDeviceGray(gray);
                }
              }
              break;
            case "rg":
              if (stack.length >= 3) {
                final r = double.tryParse(stack[stack.length - 3]) ?? 0.0;
                final g = double.tryParse(stack[stack.length - 2]) ?? 0.0;
                final b = double.tryParse(stack.last) ?? 0.0;
                ret[_daColor] = CraftDeviceRgb(r, g, b);
              }
              break;
            case "k":
              if (stack.length >= 4) {
                final c = double.tryParse(stack[stack.length - 4]) ?? 0.0;
                final m = double.tryParse(stack[stack.length - 3]) ?? 0.0;
                final y = double.tryParse(stack[stack.length - 2]) ?? 0.0;
                final k = double.tryParse(stack.last) ?? 0.0;
                ret[_daColor] = CraftDeviceCmyk(c, m, y, k);
              }
              break;
            default:
              stack.clear();
              break;
          }
        } else {
          stack.add(tokenizer.getStringValue());
        }
      }
    } catch (e) {
      // Ignore
    }
    return ret;
  }

  Future<CraftPdfFont?> resolveFontName(String fontName) async {
    final doc = getDocument();
    if (doc == null) return null;

    final catalog = doc.rootCatalog();
    final acroFormDict = await catalog
        .pdfRepresentation()
        .dictionaryEntry(CraftPdfName.acroForm);
    if (acroFormDict == null) return null;

    final dr = await acroFormDict.dictionaryEntry(CraftPdfName.dr);
    if (dr == null) return null;

    final fontDict = await dr.dictionaryEntry(CraftPdfName.font);
    if (fontDict == null) return null;

    final daFontDict = await fontDict.dictionaryEntry(CraftPdfName(fontName));
    if (daFontDict != null) {
      return await doc.resolveTypeface(daFontDict);
    }
    return null;
  }

  @override
  CraftPdfDocument? getDocument() {
    final ref = pdfRepresentation().indirectHandle();
    return ref?.getDocument();
  }

  CraftPdfObject put(CraftPdfName key, CraftPdfObject value) {
    pdfRepresentation().put(key, value);
    markChanged();
    return pdfRepresentation();
  }

  Future<bool> regenerateField();
  Future<List<String>> getAppearanceStates();
}
