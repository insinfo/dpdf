import 'dart:typed_data';
import 'pdf_text_extraction.dart' show PdfGraphicsEnvelope;

import '../kernel/geom/rectangle.dart';
import '../kernel/pdf/canvas/pdf_canvas.dart';
import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_object.dart';
import '../kernel/pdf/pdf_page.dart';
import '../kernel/pdf/pdf_resources.dart';
import '../kernel/pdf/pdf_stream.dart';

/// Adds drawing in a separate Form XObject, in unrotated PDF page coordinates.
/// Original content is retained. This does not remove or redact existing data.
/// Tagged page content requires structural reconciliation and is rejected.
/// Inline images must be converted to image XObjects before using this API.
class PdfPageOverlay {
  static final _prepared = Expando<bool>();

  static Future<PdfCanvas> create(PdfPage page) async {
    final dictionary = page.pdfRepresentation();
    final document = page.getDocument();
    if (document == null || document.outputWriter() == null) {
      throw StateError(
          'Overlay drawing requires a document opened for writing.');
    }
    if (dictionary.containsKey(PdfName.structParents) ||
        document
            .rootCatalog()
            .pdfRepresentation()
            .containsKey(PdfName.structTreeRoot)) {
      throw UnsupportedError(
          'Overlay drawing does not yet reconcile tagged content.');
    }
    final media = await _inherited(dictionary, PdfName.mediaBox);
    final bounds =
        media is PdfArray ? await Rectangle.fromPdfArray(media) : null;
    if (bounds == null) {
      throw FormatException('Page has no valid inherited MediaBox.');
    }

    if (_prepared[dictionary] != true) {
      final previous = await page.contentPayload();
      final originalResources = await _inherited(dictionary, PdfName.resources);
      final local = PdfResources();
      // Original operators keep their own resource namespace. Drawing into a
      // separate form also keeps transforms, clipping and text state local.
      final calls = PdfStream();
      calls.attachToDocument(document);
      if (previous.isNotEmpty) {
        final base = _form(
            bounds,
            PdfGraphicsEnvelope.wrap(previous),
            originalResources is PdfDictionary
                ? originalResources
                : PdfDictionary());
        final name = await local.addXObject(document, base);
        calls
            .getOutputStream()
            .writeBytes('q ${name.toString()} Do Q\n'.codeUnits);
      }
      page.replaceResourceDirectory(local);
      dictionary.put(PdfName.contents, PdfArray()..add(calls));
      dictionary.markChanged();
      _prepared[dictionary] = true;
    }

    final layerResources = PdfResources();
    final layer =
        _form(bounds, Uint8List(0), layerResources.pdfRepresentation());
    final resources = await page.resourceDirectory();
    final name = await resources.addXObject(document, layer);
    final invocation = PdfStream.withBytes(
        Uint8List.fromList('q ${name.toString()} Do Q\n'.codeUnits));
    invocation.attachToDocument(document);
    final contents = await dictionary.arrayEntry(PdfName.contents);
    contents!.add(invocation);
    contents.markChanged();
    resources.markChanged();
    dictionary.markChanged();
    return PdfCanvas(layer, layerResources, document);
  }

  static PdfStream _form(
          Rectangle bounds, Uint8List bytes, PdfDictionary resources) =>
      PdfStream.withBytes(bytes)
        ..put(PdfName.type, PdfName.xObject)
        ..put(PdfName.subtype, PdfName.form)
        ..put(PdfName.bBox, bounds.toPdfArray())
        ..put(PdfName.resources, resources);

  static Future<PdfObject?> _inherited(PdfDictionary page, PdfName key) async {
    final visited = <PdfDictionary>{};
    PdfDictionary? current = page;
    while (current != null) {
      if (!visited.add(current) || visited.length > 256) {
        throw FormatException(
            'Invalid ancestor chain while resolving page resources.');
      }
      final value = await current.get(key, true);
      if (value != null) return value;
      current = await current.dictionaryEntry(PdfName.parent);
    }
    return null;
  }
}
