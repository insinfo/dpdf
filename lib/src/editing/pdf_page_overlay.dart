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

  static Future<CraftPdfCanvas> create(CraftPdfPage page) async {
    final dictionary = page.pdfRepresentation();
    final document = page.getDocument();
    if (document == null || document.outputWriter() == null) {
      throw StateError(
          'Overlay drawing requires a document opened for writing.');
    }
    if (dictionary.containsKey(CraftPdfName.structParents) ||
        document
            .rootCatalog()
            .pdfRepresentation()
            .containsKey(CraftPdfName.structTreeRoot)) {
      throw UnsupportedError(
          'Overlay drawing does not yet reconcile tagged content.');
    }
    final media = await _inherited(dictionary, CraftPdfName.mediaBox);
    final bounds = media is CraftPdfArray
        ? await CraftRectangle.fromPdfArray(media)
        : null;
    if (bounds == null) {
      throw FormatException('Page has no valid inherited MediaBox.');
    }

    if (_prepared[dictionary] != true) {
      final previous = await page.contentPayload();
      final originalResources =
          await _inherited(dictionary, CraftPdfName.resources);
      final local = CraftPdfResources();
      // Original operators keep their own resource namespace. Drawing into a
      // separate form also keeps transforms, clipping and text state local.
      final calls = CraftPdfStream();
      calls.attachToDocument(document);
      if (previous.isNotEmpty) {
        final base = _form(
            bounds,
            PdfGraphicsEnvelope.wrap(previous),
            originalResources is CraftPdfDictionary
                ? originalResources
                : CraftPdfDictionary());
        final name = await local.addXObject(document, base);
        calls
            .getOutputStream()
            .writeBytes('q ${name.toString()} Do Q\n'.codeUnits);
      }
      page.replaceResourceDirectory(local);
      dictionary.put(CraftPdfName.contents, CraftPdfArray()..add(calls));
      dictionary.markChanged();
      _prepared[dictionary] = true;
    }

    final layerResources = CraftPdfResources();
    final layer =
        _form(bounds, Uint8List(0), layerResources.pdfRepresentation());
    final resources = await page.resourceDirectory();
    final name = await resources.addXObject(document, layer);
    final invocation = CraftPdfStream.withBytes(
        Uint8List.fromList('q ${name.toString()} Do Q\n'.codeUnits));
    invocation.attachToDocument(document);
    final contents = await dictionary.arrayEntry(CraftPdfName.contents);
    contents!.add(invocation);
    contents.markChanged();
    resources.markChanged();
    dictionary.markChanged();
    return CraftPdfCanvas(layer, layerResources, document);
  }

  static CraftPdfStream _form(CraftRectangle bounds, Uint8List bytes,
          CraftPdfDictionary resources) =>
      CraftPdfStream.withBytes(bytes)
        ..put(CraftPdfName.type, CraftPdfName.xObject)
        ..put(CraftPdfName.subtype, CraftPdfName.form)
        ..put(CraftPdfName.bBox, bounds.toPdfArray())
        ..put(CraftPdfName.resources, resources);

  static Future<CraftPdfObject?> _inherited(
      CraftPdfDictionary page, CraftPdfName key) async {
    final visited = <CraftPdfDictionary>{};
    CraftPdfDictionary? current = page;
    while (current != null) {
      if (!visited.add(current) || visited.length > 256) {
        throw FormatException(
            'Invalid ancestor chain while resolving page resources.');
      }
      final value = await current.get(key, true);
      if (value != null) return value;
      current = await current.dictionaryEntry(CraftPdfName.parent);
    }
    return null;
  }
}
