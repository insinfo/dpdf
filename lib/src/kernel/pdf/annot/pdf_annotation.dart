import '../pdf_stream.dart';
import '../pdf_object.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_string.dart';
import '../pdf_number.dart';
import '../pdf_array.dart';
import '../pdf_object_wrapper.dart';
import '../pdf_page.dart';

import '../../geom/rectangle.dart';

import 'pdf_widget_annotation.dart';

/// This is a super class for the annotation dictionary wrappers.
/// Derived classes represent different standard types of annotations.
/// See ISO-320001 12.5.6, "Annotation Types."
abstract class CraftPdfAnnotation
    extends CraftPdfObjectWrapper<CraftPdfDictionary> {
  // Annotation flags
  static const int invisible = 1;
  static const int hidden = 2;
  static const int print = 4;
  static const int noZoom = 8;
  static const int noRotate = 16;
  static const int noView = 32;
  static const int readOnly = 64;
  static const int locked = 128;
  static const int toggleNoView = 256;
  static const int lockedContents = 512;

  // Highlight modes
  static final CraftPdfName highlightNone = CraftPdfName.n;
  static final CraftPdfName highlightInvert = CraftPdfName.i;
  static final CraftPdfName highlightOutline = CraftPdfName.o;
  static final CraftPdfName highlightPush = CraftPdfName.p;
  static final CraftPdfName highlightToggle = CraftPdfName.t;

  // Border styles
  static final CraftPdfName styleSolid = CraftPdfName.s;
  static final CraftPdfName styleDashed = CraftPdfName.d;
  static final CraftPdfName styleBeveled = CraftPdfName.b;
  static final CraftPdfName styleInset = CraftPdfName.i;
  static final CraftPdfName styleUnderline = CraftPdfName.u;

  CraftPdfPage? _page;

  CraftPdfAnnotation(CraftPdfDictionary pdfObject) : super(pdfObject) {
    if (requiresIndirectStorage()) {
      CraftPdfObjectWrapper.markObjectAsIndirect(pdfRepresentation());
    }
  }

  CraftPdfAnnotation.fromRect(CraftRectangle rect)
      : super(CraftPdfDictionary()) {
    put(CraftPdfName.rect, CraftPdfArray.fromRectangle(rect));
    // subtype set by subclass
    if (requiresIndirectStorage()) {
      CraftPdfObjectWrapper.markObjectAsIndirect(pdfRepresentation());
    }
  }

  @override
  bool requiresIndirectStorage() {
    return true;
  }

  /// Factory method that creates the type specific [PdfAnnotation]
  static Future<CraftPdfAnnotation?> makeAnnotation(
      CraftPdfObject pdfObject) async {
    CraftPdfObject? direct = pdfObject;
    if (pdfObject.isIndirectReference()) {
      direct = await (pdfObject as CraftPdfIndirectReference).targetObject();
    }

    if (direct != null && direct.isDictionary()) {
      final dictionary = direct as CraftPdfDictionary;
      final subtype = await dictionary.nameEntry(CraftPdfName.subtype);

      if (CraftPdfName.widget == subtype) {
        return CraftPdfWidgetAnnotation(dictionary);
      }

      return PdfUnknownAnnotation(dictionary);
    }
    return null;
  }

  CraftPdfName getSubtype();

  Future<CraftPdfString?> getContents() async {
    return await pdfRepresentation().stringEntry(CraftPdfName.contents);
  }

  CraftPdfAnnotation setContents(CraftPdfString contents) {
    put(CraftPdfName.contents, contents);
    return this;
  }

  CraftPdfAnnotation setContentsString(String contents) {
    return setContents(CraftPdfString(contents));
  }

  Future<CraftPdfDictionary?> getPageObject() async {
    return await pdfRepresentation()
        .dictionaryEntry(CraftPdfName.p); // P for Page
  }

  Future<CraftPdfPage?> pageAt() async {
    if (_page == null) {
      final ref = pdfRepresentation().indirectHandle();
      if (ref != null) {
        final doc = ref.getDocument();
        final pageDict = await getPageObject();

        if (doc != null && pageDict != null) {
          _page = await doc.findPageObject(pageDict);
        }
      }
    }
    return _page;
  }

  CraftPdfAnnotation setPage(CraftPdfPage page) {
    this._page = page;
    put(CraftPdfName.p, page.pdfRepresentation().indirectHandle()!);
    return this;
  }

  Future<CraftPdfAnnotation> setFlag(int flag) async {
    int flags = await getFlags();
    flags |= flag;
    return setFlags(flags);
  }

  Future<CraftPdfAnnotation> resetFlag(int flag) async {
    int flags = await getFlags();
    flags &= ~flag;
    return setFlags(flags);
  }

  CraftPdfAnnotation setFlags(int flags) {
    put(CraftPdfName.f, CraftPdfNumber.fromInt(flags));
    return this;
  }

  Future<int> getFlags() async {
    final f = await pdfRepresentation().numberEntry(CraftPdfName.f);
    return f?.intValue() ?? 0;
  }

  Future<bool> hasFlag(int flag) async {
    if (flag == 0) return false;
    int flags = await getFlags();
    return (flags & flag) != 0;
  }

  CraftPdfAnnotation put(CraftPdfName key, CraftPdfObject value) {
    pdfRepresentation().put(key, value);
    return this;
  }

  Future<CraftPdfDictionary?> getAppearanceDictionary() =>
      pdfRepresentation().dictionaryEntry(CraftPdfName.ap);

  Future<CraftPdfStream?> getNormalAppearanceObject() async {
    CraftPdfDictionary? ap = await getAppearanceDictionary();
    if (ap == null) return null;

    CraftPdfObject? n = await ap.get(CraftPdfName.n);
    if (n == null) return null;

    if (n.isStream()) {
      return n as CraftPdfStream;
    }

    if (n.isDictionary()) {
      CraftPdfName? as = await pdfRepresentation().nameEntry(CraftPdfName.as);
      if (as == null) {
        // Fallback to "Off" or typically existing state?
        // For now try 'Off' which is standard for unchecked.
        as = CraftPdfName.intern("Off");
      }
      CraftPdfStream? stream = await (n as CraftPdfDictionary).streamEntry(as);
      return stream;
    }
    return null;
  }
}

class PdfUnknownAnnotation extends CraftPdfAnnotation {
  PdfUnknownAnnotation(CraftPdfDictionary pdfObject) : super(pdfObject);

  @override
  CraftPdfName getSubtype() {
    return CraftPdfName.intern("Unknown");
  }
}
