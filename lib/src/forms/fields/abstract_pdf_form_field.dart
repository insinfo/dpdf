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

abstract class AbstractPdfFormField extends PdfObjectWrapper<PdfDictionary> {
  static const int defaultFontSize = 12;
  static const int minFontSize = 4;

  static const int _daFont = 0;
  static const int _daSize = 1;
  static const int _daColor = 2;

  PdfFont? _font;
  double _fontSize = -1;
  Color? _color;
  PdfFormField? _parent;

  AbstractPdfFormField(PdfDictionary pdfObject) : super(pdfObject) {
    if (isWrappedObjectMustBeIndirect()) {
      PdfObjectWrapper.markObjectAsIndirect(pdfObject);
    }
    // SetForbidRelease(); // TODO
    _retrieveStyles();
  }

  @override
  bool isWrappedObjectMustBeIndirect() => true;

  void setParent(PdfFormField parent) {
    put(PdfName.parent, parent.getPdfObject());
    _parent = parent;
  }

  Future<PdfDictionary?> getParent() async {
    final p = await getPdfObject().getAsDictionary(PdfName.parent);
    if (p != null) return p;
    return _parent?.getPdfObject();
  }

  PdfFormField? getParentField() => _parent;

  Future<PdfString?> getFieldName() async {
    return getPdfObject().getAsString(PdfName.t); // T = Terminal Name
  }

  Future<PdfString?> getDefaultAppearance() async {
    // Inheritable
    PdfString? da = await getPdfObject().getAsString(PdfName.da);
    if (da == null && _parent != null) {
      return await _parent!.getDefaultAppearance();
    }
    return da;
  }

  PdfFont? getFont() => _font;
  double getFontSize() => _fontSize;
  Color? getColor() => _color;

  void _retrieveStyles() async {
    final da = await getDefaultAppearance();
    if (da != null) {
      final fontData = await _splitDAelements(da.getValue());
      if (fontData[_daSize] != null && fontData[_daFont] != null) {
        _fontSize = (fontData[_daSize] as num).toDouble();
        _color = fontData[_daColor] as Color?;
        final fontName = fontData[_daFont] as String;
        _font = await resolveFontName(fontName);
      }
    }
  }

  static Future<List<Object?>> _splitDAelements(String da) async {
    final bytes = EncodingUtil.convertToBytes(da, "Latin1");
    final tokenizer = PdfTokenizer(RandomAccessFileOrArray(bytes));
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
                  ret[_daColor] = DeviceGray(gray);
                }
              }
              break;
            case "rg":
              if (stack.length >= 3) {
                final r = double.tryParse(stack[stack.length - 3]) ?? 0.0;
                final g = double.tryParse(stack[stack.length - 2]) ?? 0.0;
                final b = double.tryParse(stack.last) ?? 0.0;
                ret[_daColor] = DeviceRgb(r, g, b);
              }
              break;
            case "k":
              if (stack.length >= 4) {
                final c = double.tryParse(stack[stack.length - 4]) ?? 0.0;
                final m = double.tryParse(stack[stack.length - 3]) ?? 0.0;
                final y = double.tryParse(stack[stack.length - 2]) ?? 0.0;
                final k = double.tryParse(stack.last) ?? 0.0;
                ret[_daColor] = DeviceCmyk(c, m, y, k);
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

  Future<PdfFont?> resolveFontName(String fontName) async {
    final doc = await getDocument();
    if (doc == null) return null;

    final catalog = doc.getCatalog();
    final acroFormDict =
        await catalog.getPdfObject().getAsDictionary(PdfName.acroForm);
    if (acroFormDict == null) return null;

    final dr = await acroFormDict.getAsDictionary(PdfName.dr);
    if (dr == null) return null;

    final fontDict = await dr.getAsDictionary(PdfName.font);
    if (fontDict == null) return null;

    final daFontDict = await fontDict.getAsDictionary(PdfName(fontName));
    if (daFontDict != null) {
      return await doc.getFont(daFontDict);
    }
    return null;
  }

  Future<PdfDocument?> getDocument() async {
    final ref = getPdfObject().getIndirectReference();
    return ref?.getDocument();
  }

  PdfObject put(PdfName key, PdfObject value) {
    getPdfObject().put(key, value);
    setModified();
    return getPdfObject();
  }

  Future<bool> regenerateField();
  Future<List<String>> getAppearanceStates();
}
