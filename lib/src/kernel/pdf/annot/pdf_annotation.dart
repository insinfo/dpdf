import '../pdf_stream.dart';
import '../pdf_object.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_string.dart';
import '../pdf_number.dart';
import '../pdf_array.dart';
import '../pdf_date.dart';
import '../pdf_object_wrapper.dart';
import '../pdf_page.dart';

import '../../geom/rectangle.dart';

import 'pdf_annotation_border.dart';
import 'pdf_3d_annotation.dart';
import 'pdf_caret_annotation.dart';
import 'pdf_file_attachment_annotation.dart';
import 'pdf_free_text_annotation.dart';
import 'pdf_ink_annotation.dart';
import 'pdf_line_annotation.dart';
import 'pdf_link_annotation.dart';
import 'pdf_media_annotations.dart';
import 'pdf_popup_annotation.dart';
import 'pdf_print_annotations.dart';
import 'pdf_redact_annotation.dart';
import 'pdf_shape_annotations.dart';
import 'pdf_stamp_annotation.dart';
import 'pdf_text_annotation.dart';
import 'pdf_text_markup_annotation.dart';
import 'pdf_widget_annotation.dart';

/// This is a super class for the annotation dictionary wrappers.
/// Derived classes represent different standard types of annotations.
/// See ISO 32000-1:2008, 12.5.6 "Annotation Types", Table 169.
abstract class PdfAnnotation extends PdfObjectWrapper<PdfDictionary> {
  // Annotation flags, ISO 32000-1:2008, 12.5.3, Table 165.
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

  PdfAnnotation(super.pdfObject) {
    if (requiresIndirectStorage()) {
      PdfObjectWrapper.markObjectAsIndirect(pdfRepresentation());
    }
  }

  PdfAnnotation.fromRect(Rectangle rect) : super(PdfDictionary()) {
    put(PdfName.type, PdfName.annot);
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

  /// Factory method that creates the type specific [PdfAnnotation].
  ///
  /// Dispatch follows the `/Subtype` values of ISO 32000-1:2008, Table 169.
  static Future<PdfAnnotation?> makeAnnotation(PdfObject pdfObject) async {
    PdfObject? direct = pdfObject;
    if (pdfObject.isIndirectReference()) {
      direct = await (pdfObject as PdfIndirectReference).targetObject();
    }

    if (direct != null && direct.isDictionary()) {
      final dictionary = direct as PdfDictionary;
      final subtype = await dictionary.nameEntry(PdfName.subtype);
      switch (subtype?.getValue()) {
        case 'Text':
          return PdfTextAnnotation(dictionary);
        case 'Link':
          return PdfLinkAnnotation(dictionary);
        case 'FreeText':
          return PdfFreeTextAnnotation(dictionary);
        case 'Line':
          return PdfLineAnnotation(dictionary);
        case 'Square':
          return PdfSquareAnnotation(dictionary);
        case 'Circle':
          return PdfCircleAnnotation(dictionary);
        case 'Polygon':
          return PdfPolygonAnnotation(dictionary);
        case 'PolyLine':
          return PdfPolyLineAnnotation(dictionary);
        case 'Highlight':
        case 'Underline':
        case 'Squiggly':
        case 'StrikeOut':
          return PdfTextMarkupAnnotation(dictionary);
        case 'Stamp':
          return PdfStampAnnotation(dictionary);
        case 'Caret':
          return PdfCaretAnnotation(dictionary);
        case 'Ink':
          return PdfInkAnnotation(dictionary);
        case 'Popup':
          return PdfPopupAnnotation(dictionary);
        case 'FileAttachment':
          return PdfFileAttachmentAnnotation(dictionary);
        case 'Sound':
          return PdfSoundAnnotation(dictionary);
        case 'Movie':
          return PdfMovieAnnotation(dictionary);
        case 'Widget':
          return PdfWidgetAnnotation(dictionary);
        case 'Screen':
          return PdfScreenAnnotation(dictionary);
        case 'PrinterMark':
          return PdfPrinterMarkAnnotation(dictionary);
        case 'TrapNet':
          return PdfTrapNetworkAnnotation(dictionary);
        case 'Watermark':
          return PdfWatermarkAnnotation(dictionary);
        case '3D':
          return Pdf3DAnnotation(dictionary);
        case 'Redact':
          return PdfRedactAnnotation(dictionary);
      }
      return PdfUnknownAnnotation(dictionary);
    }
    return null;
  }

  PdfName getSubtype();

  /// Gets the annotation rectangle (`/Rect`, Table 164).
  Future<Rectangle?> getRectangle() async {
    return await Rectangle.fromPdfArray(
        await pdfRepresentation().arrayEntry(PdfName.rect));
  }

  /// Sets the annotation rectangle (`/Rect`, Table 164).
  PdfAnnotation setRectangle(Rectangle rect) {
    return put(PdfName.rect, PdfArray.fromRectangle(rect));
  }

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

  /// Sets the annotation name (`/NM`, Table 164): a text string that uniquely
  /// identifies the annotation among all annotations on its page.
  PdfAnnotation setName(PdfString name) => put(PdfName.nm, name);

  /// Gets `/NM`.
  Future<PdfString?> getName() async =>
      await pdfRepresentation().stringEntry(PdfName.nm);

  /// Sets `/M`, the date and time when the annotation was last modified.
  PdfAnnotation setModifiedDate(PdfDate date) =>
      put(PdfName.m, PdfString(date.getValue()));

  /// Gets `/M` as written. Conforming readers accept any format (Table 164),
  /// so the raw string is returned.
  Future<PdfString?> getModifiedDate() async =>
      await pdfRepresentation().stringEntry(PdfName.m);

  /// Sets `/Border`: horizontal corner radius, vertical corner radius and
  /// border width, plus an optional dash array (Table 164).
  PdfAnnotation setBorder(double horizontalRadius, double verticalRadius,
      double width, List<double>? dashPattern) {
    final array =
        PdfArray.fromDoubles([horizontalRadius, verticalRadius, width]);
    if (dashPattern != null) {
      array.add(PdfArray.fromDoubles(dashPattern));
    }
    return put(PdfName.border, array);
  }

  /// Gets `/Border` as written.
  Future<PdfArray?> getBorder() async =>
      await pdfRepresentation().arrayEntry(PdfName.border);

  /// Sets the border style dictionary `/BS` (Table 166).
  PdfAnnotation setBorderStyle(PdfBorderStyle style) =>
      put(PdfName.bs, style.pdfRepresentation());

  /// Gets `/BS`.
  Future<PdfBorderStyle?> getBorderStyle() async {
    final dictionary = await pdfRepresentation().dictionaryEntry(PdfName.bs);
    return dictionary == null ? null : PdfBorderStyle(dictionary);
  }

  /// Sets `/C`, the annotation colour (Table 164). An empty list writes an
  /// empty array, meaning "no colour; transparent".
  PdfAnnotation setColor(List<double> components) =>
      put(PdfName.c, PdfAnnotationColor.toArray(components));

  /// Gets `/C`.
  Future<List<double>?> getColor() =>
      PdfAnnotationColor.fromEntry(pdfRepresentation(), PdfName.c);

  /// Sets `/StructParent`, required when the annotation is a structural
  /// content item (Table 164).
  PdfAnnotation setStructParentIndex(int index) =>
      put(PdfName.structParent, PdfNumber.fromInt(index));

  /// Gets `/StructParent`.
  Future<int?> getStructParentIndex() async =>
      await pdfRepresentation().integerEntry(PdfName.structParent);

  /// Sets `/OC`, an optional content group or membership dictionary.
  PdfAnnotation setOptionalContent(PdfObject group) => put(PdfName.oc, group);

  /// Gets `/OC`.
  Future<PdfObject?> getOptionalContent() async =>
      await pdfRepresentation().get(PdfName.oc);

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

  /// Removes an entry from the annotation dictionary.
  PdfAnnotation remove(PdfName key) {
    pdfRepresentation().remove(key);
    return this;
  }

  // --- Appearance streams, ISO 32000-1:2008, 12.5.5, Table 168. ----------

  Future<PdfDictionary?> getAppearanceDictionary() =>
      pdfRepresentation().dictionaryEntry(PdfName.ap);

  /// Returns (creating when needed) the `/AP` appearance dictionary.
  Future<PdfDictionary> ensureAppearanceDictionary() async {
    var ap = await getAppearanceDictionary();
    if (ap == null) {
      ap = PdfDictionary();
      put(PdfName.ap, ap);
    }
    return ap;
  }

  /// Sets `/AP /N`, the normal appearance (Table 168).
  Future<PdfAnnotation> setNormalAppearance(PdfObject appearance) =>
      _setAppearance(PdfName.n, appearance);

  /// Sets `/AP /R`, the rollover appearance (Table 168).
  Future<PdfAnnotation> setRolloverAppearance(PdfObject appearance) =>
      _setAppearance(PdfName.r, appearance);

  /// Sets `/AP /D`, the down appearance (Table 168).
  Future<PdfAnnotation> setDownAppearance(PdfObject appearance) =>
      _setAppearance(PdfName.d, appearance);

  Future<PdfAnnotation> _setAppearance(
      PdfName key, PdfObject appearance) async {
    (await ensureAppearanceDictionary()).put(key, appearance);
    markChanged();
    return this;
  }

  /// Adds a state-specific appearance stream, producing the appearance
  /// subdictionary form of Table 168 (`/AP << /N << /On ... /Off ... >> >>`).
  Future<PdfAnnotation> setAppearanceState(
      PdfName appearanceKind, PdfName state, PdfStream appearance) async {
    final ap = await ensureAppearanceDictionary();
    final existing = await ap.get(appearanceKind, true);
    PdfDictionary states;
    if (existing is PdfDictionary && existing is! PdfStream) {
      states = existing;
    } else {
      states = PdfDictionary();
      ap.put(appearanceKind, states);
    }
    states.put(state, appearance);
    markChanged();
    return this;
  }

  /// Sets `/AS`, the appearance state selecting a stream from an appearance
  /// subdictionary (Table 164).
  PdfAnnotation setAppearanceStateName(PdfName state) => put(PdfName.as, state);

  /// Gets `/AS`.
  Future<PdfName?> getAppearanceStateName() async =>
      await pdfRepresentation().nameEntry(PdfName.as);

  Future<PdfStream?> getNormalAppearanceObject() =>
      _appearanceObject(PdfName.n);

  /// Gets the rollover appearance; per Table 168 it defaults to `/N`.
  Future<PdfStream?> getRolloverAppearanceObject() async =>
      await _appearanceObject(PdfName.r) ?? await _appearanceObject(PdfName.n);

  /// Gets the down appearance; per Table 168 it defaults to `/N`.
  Future<PdfStream?> getDownAppearanceObject() async =>
      await _appearanceObject(PdfName.d) ?? await _appearanceObject(PdfName.n);

  Future<PdfStream?> _appearanceObject(PdfName kind) async {
    PdfDictionary? ap = await getAppearanceDictionary();
    if (ap == null) return null;

    PdfObject? entry = await ap.get(kind, true);
    if (entry == null) return null;

    if (entry.isStream()) {
      return entry as PdfStream;
    }

    if (entry.isDictionary()) {
      PdfName? as = await pdfRepresentation().nameEntry(PdfName.as);
      as ??= PdfName.intern("Off");
      return await (entry as PdfDictionary).streamEntry(as);
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
