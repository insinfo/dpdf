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
abstract class PdfAnnotation extends PdfObjectWrapper<PdfDictionary> {
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
  static final PdfName highlightNone = PdfName.n;
  static final PdfName highlightInvert = PdfName.i;
  static final PdfName highlightOutline = PdfName.o;
  static final PdfName highlightPush = PdfName.p;
  static final PdfName highlightToggle = PdfName.t;

  // Border styles
  static final PdfName styleSolid = PdfName.s;
  static final PdfName styleDashed = PdfName.d;
  static final PdfName styleBeveled = PdfName.b;
  static final PdfName styleInset = PdfName.i;
  static final PdfName styleUnderline = PdfName.u;

  PdfPage? _page;

  PdfAnnotation(PdfDictionary pdfObject) : super(pdfObject) {
    if (requiresIndirectStorage()) {
      PdfObjectWrapper.markObjectAsIndirect(pdfRepresentation());
    }
  }

  PdfAnnotation.fromRect(Rectangle rect) : super(PdfDictionary()) {
    put(PdfName.rect, PdfArray.fromRectangle(rect));
    // subtype set by subclass
    if (requiresIndirectStorage()) {
      PdfObjectWrapper.markObjectAsIndirect(pdfRepresentation());
    }
  }

  @override
  bool requiresIndirectStorage() {
    return true;
  }

  /// Factory method that creates the type specific [PdfAnnotation]
  static Future<PdfAnnotation?> makeAnnotation(PdfObject pdfObject) async {
    PdfObject? direct = pdfObject;
    if (pdfObject.isIndirectReference()) {
      direct = await (pdfObject as PdfIndirectReference).targetObject();
    }

    if (direct != null && direct.isDictionary()) {
      final dictionary = direct as PdfDictionary;
      final subtype = await dictionary.nameEntry(PdfName.subtype);

      if (PdfName.widget == subtype) {
        return PdfWidgetAnnotation(dictionary);
      }

      return PdfUnknownAnnotation(dictionary);
    }
    return null;
  }

  PdfName getSubtype();

  Future<PdfString?> getContents() async {
    return await pdfRepresentation().stringEntry(PdfName.contents);
  }

  PdfAnnotation setContents(PdfString contents) {
    put(PdfName.contents, contents);
    return this;
  }

  PdfAnnotation setContentsString(String contents) {
    return setContents(PdfString(contents));
  }

  Future<PdfDictionary?> getPageObject() async {
    return await pdfRepresentation().dictionaryEntry(PdfName.p); // P for Page
  }

  Future<PdfPage?> pageAt() async {
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

  PdfAnnotation setPage(PdfPage page) {
    _page = page;
    put(PdfName.p, page.pdfRepresentation().indirectHandle()!);
    return this;
  }

  Future<PdfAnnotation> setFlag(int flag) async {
    int flags = await getFlags();
    flags |= flag;
    return setFlags(flags);
  }

  Future<PdfAnnotation> resetFlag(int flag) async {
    int flags = await getFlags();
    flags &= ~flag;
    return setFlags(flags);
  }

  PdfAnnotation setFlags(int flags) {
    put(PdfName.f, PdfNumber.fromInt(flags));
    return this;
  }

  Future<int> getFlags() async {
    final f = await pdfRepresentation().numberEntry(PdfName.f);
    return f?.intValue() ?? 0;
  }

  Future<bool> hasFlag(int flag) async {
    if (flag == 0) return false;
    int flags = await getFlags();
    return (flags & flag) != 0;
  }

  PdfAnnotation put(PdfName key, PdfObject value) {
    pdfRepresentation().put(key, value);
    return this;
  }

  Future<PdfDictionary?> getAppearanceDictionary() =>
      pdfRepresentation().dictionaryEntry(PdfName.ap);

  Future<PdfStream?> getNormalAppearanceObject() async {
    PdfDictionary? ap = await getAppearanceDictionary();
    if (ap == null) return null;

    PdfObject? n = await ap.get(PdfName.n);
    if (n == null) return null;

    if (n.isStream()) {
      return n as PdfStream;
    }

    if (n.isDictionary()) {
      PdfName? as = await pdfRepresentation().nameEntry(PdfName.as);
      as ??= PdfName.intern("Off");
      PdfStream? stream = await (n as PdfDictionary).streamEntry(as);
      return stream;
    }
    return null;
  }
}

class PdfUnknownAnnotation extends PdfAnnotation {
  PdfUnknownAnnotation(super.pdfObject);

  @override
  PdfName getSubtype() {
    return PdfName.intern("Unknown");
  }
}
