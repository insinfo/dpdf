import '../pdf_array.dart';
import '../pdf_boolean.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_object.dart';
import '../pdf_number.dart';
import '../pdf_stream.dart';
import '../pdf_string.dart';
import '../multimedia/pdf_3d.dart';
import '../../geom/rectangle.dart';

import 'pdf_annotation.dart';
import 'pdf_annotation_border.dart';

/// 3D annotation.
///
/// Listed in ISO 32000-1:2008, Table 169 and specified in 13.6.2
/// "3D Annotations", Table 298.
class Pdf3DAnnotation extends PdfAnnotation {
  /// `/3DD` is required; it is the 3D stream or 3D reference dictionary that
  /// specifies the artwork.
  Pdf3DAnnotation(super.pdfObject);

  Pdf3DAnnotation.fromRect(super.rect, PdfObject artwork) : super.fromRect() {
    put(PdfName.subtype, PdfName.threeD);
    setArtwork(artwork);
  }

  @override
  PdfName getSubtype() => PdfName.threeD;

  /// Sets `/3DD`, the 3D stream or 3D reference dictionary.
  Pdf3DAnnotation setArtwork(PdfObject artwork) {
    put(PdfName.intern('3DD'), artwork);
    return this;
  }

  /// Gets `/3DD` as written.
  Future<PdfObject?> getArtwork() async =>
      await pdfRepresentation().get(PdfName.intern('3DD'), true);

  /// Sets `/3DV`, the default initial view of the 3D artwork.
  Pdf3DAnnotation setDefaultView(PdfObject view) {
    put(PdfName.intern('3DV'), view);
    return this;
  }

  /// Gets `/3DV` as written.
  Future<PdfObject?> getDefaultView() async =>
      await pdfRepresentation().get(PdfName.intern('3DV'), true);

  /// Sets `/3DA`, the activation dictionary of Table 299.
  Pdf3DAnnotation setActivation(PdfDictionary activation) {
    put(PdfName.intern('3DA'), activation);
    return this;
  }

  /// Gets `/3DA`.
  Future<PdfDictionary?> getActivation() async =>
      await pdfRepresentation().dictionaryEntry(PdfName.intern('3DA'));

  /// Sets `/3DI`, whether the annotation intercepts mouse clicks.
  Pdf3DAnnotation setInteractive(bool interactive) {
    put(PdfName.intern('3DI'), PdfBoolean(interactive));
    return this;
  }

  /// Gets `/3DI`; the default is true per Table 298.
  Future<bool> isInteractive() async =>
      (await pdfRepresentation().booleanEntry(PdfName.intern('3DI')))
          ?.getValue() ??
      true;

  /// Sets `/3DB`, the 3D view box in annotation coordinates.
  Pdf3DAnnotation setViewBox(List<double> viewBox) {
    if (viewBox.length != 4) {
      throw ArgumentError.value(
          viewBox, 'viewBox', '/3DB shall contain four numbers');
    }
    put(PdfName.intern('3DB'), PdfArray.fromDoubles(viewBox));
    return this;
  }

  /// Gets `/3DB`.
  Future<List<double>?> getViewBox() =>
      readNumberArray(pdfRepresentation(), PdfName.intern('3DB'));

  /// Builds a minimal 3D stream (`/Type /3D`) carrying [artwork] bytes with
  /// the given `/Subtype` (`/U3D` or `/PRC`), as described in Table 300.
  static PdfStream createArtworkStream(PdfStream stream, PdfName subtype) {
    stream.put(PdfName.type, PdfName.threeD);
    stream.put(PdfName.subtype, subtype);
    return stream;
  }

  /// Creates a 3D annotation whose `/3DD` is the 3D stream [artwork], giving
  /// the annotation its own run-time instance of the artwork (13.6.3.3).
  factory Pdf3DAnnotation.forStream(Rectangle rect, Pdf3DStream artwork) =>
      Pdf3DAnnotation.fromRect(rect, artwork.pdfRepresentation());

  /// Creates a 3D annotation whose `/3DD` is the 3D reference dictionary
  /// [reference], making it share one run-time instance of the artwork with
  /// every other annotation using the same reference (13.6.3.3).
  factory Pdf3DAnnotation.forReference(
          Rectangle rect, Pdf3DReference reference) =>
      Pdf3DAnnotation.fromRect(rect, reference.pdfRepresentation());

  /// Gets `/3DD` as the 3D stream holding the artwork, following a 3D
  /// reference dictionary when one is present (13.6.3.3).
  Future<Pdf3DStream?> getArtworkStream() async {
    final artwork = await getArtwork();
    if (artwork is PdfStream) return Pdf3DStream(artwork);
    if (artwork is PdfDictionary) {
      return await Pdf3DReference(artwork).getArtworkStream();
    }
    return null;
  }

  /// Gets `/3DD` as a 3D reference dictionary, or null when `/3DD` names a
  /// 3D stream directly.
  Future<Pdf3DReference?> getArtworkReference() async {
    final artwork = await getArtwork();
    if (artwork is PdfStream) return null;
    if (artwork is PdfDictionary) return Pdf3DReference(artwork);
    return null;
  }

  /// Sets `/3DV` to a 3D view dictionary.
  Pdf3DAnnotation setDefaultViewDictionary(Pdf3DView view) =>
      setDefaultView(view.pdfRepresentation());

  /// Sets `/3DV` to an index into the `/VA` array of the 3D stream.
  Pdf3DAnnotation setDefaultViewIndex(int index) {
    if (index < 0) {
      throw ArgumentError.value(index, 'index',
          '/3DV as an integer shall index /VA from zero (Table 298)');
    }
    return setDefaultView(PdfNumber.fromInt(index));
  }

  /// Sets `/3DV` to a text string matching the `/IN` entry of a view in the
  /// `/VA` array.
  Pdf3DAnnotation setDefaultViewName(String internalName) =>
      setDefaultView(PdfString(internalName));

  /// Sets `/3DV` to `/F`, `/L` or `/D`, naming the first, last or default
  /// entry of the `/VA` array (Table 298).
  Pdf3DAnnotation setDefaultViewPosition(PdfName position) {
    const allowed = {'F', 'L', 'D'};
    if (!allowed.contains(position.getValue())) {
      throw ArgumentError.value(position, 'position',
          '/3DV as a name shall be /F, /L or /D (Table 298)');
    }
    return setDefaultView(position);
  }

  /// Resolves `/3DV` against the `/VA` array of the artwork, falling back to
  /// the 3D stream's own `/DV` default as Table 298 prescribes.
  Future<Pdf3DView?> resolveDefaultView() async {
    final stream = await getArtworkStream();
    final value = await getDefaultView();
    if (value == null) return await stream?.resolveDefaultView();
    if (value is PdfStream) return null;
    if (value is PdfDictionary) return Pdf3DView(value);
    final views = await stream?.getViews() ?? const <Pdf3DView>[];
    if (value is PdfNumber) {
      final index = value.getValue().toInt();
      return index >= 0 && index < views.length ? views[index] : null;
    }
    if (value is PdfName) {
      if (views.isEmpty) return null;
      if (value.getValue() == 'F') return views.first;
      if (value.getValue() == 'L') return views.last;
      if (value.getValue() == 'D') return await stream?.resolveDefaultView();
      return null;
    }
    if (value is PdfString) {
      final wanted = value.decodeMappingText();
      for (final view in views) {
        if (await view.getInternalName() == wanted) return view;
      }
    }
    return null;
  }

  /// Sets `/3DA` from a typed activation dictionary (Table 299).
  Pdf3DAnnotation setActivationDictionary(Pdf3DActivation activation) =>
      setActivation(activation.pdfRepresentation());

  /// Gets `/3DA` as a typed activation dictionary; Table 298 defaults it to
  /// an activation dictionary whose entries all hold their default values.
  Future<Pdf3DActivation?> getActivationDictionary() async {
    final dictionary = await getActivation();
    return dictionary == null ? null : Pdf3DActivation(dictionary);
  }

  /// The default `/3DB` view box of Table 298, `[-w/2 -h/2 w/2 h/2]` in the
  /// annotation's target coordinate system, derived from `/Rect`.
  Future<List<double>?> defaultViewBox() async {
    final rect = await readNumberArray(pdfRepresentation(), PdfName.rect);
    if (rect == null || rect.length != 4) return null;
    final width = (rect[2] - rect[0]).abs();
    final height = (rect[3] - rect[1]).abs();
    return [-width / 2, -height / 2, width / 2, height / 2];
  }

  /// Gets `/3DB`, falling back to the default of Table 298 when absent.
  Future<List<double>?> getEffectiveViewBox() async =>
      await getViewBox() ?? await defaultViewBox();
}
