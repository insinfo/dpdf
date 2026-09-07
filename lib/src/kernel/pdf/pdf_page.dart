import 'dart:typed_data';

import '../geom/rectangle.dart';
import '../geom/page_size.dart';
import 'pdf_object.dart';
import 'pdf_dictionary.dart';
import 'pdf_array.dart';
import 'pdf_name.dart';
import 'pdf_number.dart';
import 'pdf_stream.dart';
import 'pdf_object_wrapper.dart';
import 'pdf_resources.dart';
import 'pdf_pages.dart';
import 'annot/pdf_annotation.dart';

/// Wrapper class that represents a page in a PDF document.
class PdfPage extends PdfObjectWrapper<PdfDictionary> {
  PdfResources? _resources;
  PdfPages? _parentPages;

  PdfPage(PdfDictionary pdfObject) : super(pdfObject) {
    pdfObject.put(PdfName.type, PdfName.page);
  }

  @override
  bool requiresIndirectStorage() => true;

  Future<PdfResources> resourceDirectory() async {
    if (_resources == null) {
      final resDict =
          await pdfRepresentation().dictionaryEntry(PdfName.resources);
      if (resDict != null) {
        _resources = PdfResources(resDict);
        await _resources!.init();
      } else {
        _resources = PdfResources();
        pdfRepresentation()
            .put(PdfName.resources, _resources!.pdfRepresentation());
      }
    }
    return _resources!;
  }

  /// Installs a page-local resource dictionary and refreshes the cached wrapper.
  void replaceResourceDirectory(PdfResources resources) {
    _resources = resources;
    pdfRepresentation().put(PdfName.resources, resources.pdfRepresentation());
    pdfRepresentation().markChanged();
  }

  PdfPages? get parentPages => _parentPages;
  set parentPages(PdfPages? value) => _parentPages = value;

  /// Gets the media box for this page.
  Future<Rectangle> mediaBounds() async {
    final array = await pdfRepresentation().arrayEntry(PdfName.mediaBox);
    return array != null
        ? await Rectangle.fromPdfArray(array) ?? PageSize.defaultSize
        : PageSize.defaultSize;
  }

  /// Sets the media box for this page.
  void setMediaBounds(Rectangle rect) {
    pdfRepresentation().put(PdfName.mediaBox, rect.toPdfArray());
    pdfRepresentation().markChanged();
  }

  /// Gets the crop box for this page.
  Future<Rectangle> cropBounds() async {
    final array = await pdfRepresentation().arrayEntry(PdfName.cropBox);
    if (array != null) {
      final rect = await Rectangle.fromPdfArray(array);
      if (rect != null) return rect;
    }
    return await mediaBounds();
  }

  /// Sets the crop box for this page.
  void setCropBounds(Rectangle rect) {
    pdfRepresentation().put(PdfName.cropBox, rect.toPdfArray());
    pdfRepresentation().markChanged();
  }

  /// Gets the rotation for this page.
  Future<int> rotationDegrees() async {
    final rotate = await pdfRepresentation().numberEntry(PdfName.rotate);
    return rotate != null ? rotate.intValue() % 360 : 0;
  }

  /// Sets the rotation for this page.
  void setRotationDegrees(int rotate) {
    pdfRepresentation().put(PdfName.rotate, PdfNumber.fromInt(rotate));
    pdfRepresentation().markChanged();
  }

  /// Gets the content stream at the specified index.
  Future<PdfObject?> contentSegmentAt(int index) async {
    final contents = await pdfRepresentation().get(PdfName.contents, true);
    if (contents is PdfStream) {
      return index == 0 ? contents : null;
    } else if (contents is PdfArray) {
      return await contents.get(index);
    }
    return null;
  }

  /// Gets the count of content streams.
  Future<int> contentSegmentCount() async {
    final contents = await pdfRepresentation().get(PdfName.contents, true);
    if (contents is PdfStream) {
      return 1;
    } else if (contents is PdfArray) {
      return contents.size();
    }
    return 0;
  }

  /// Adds an annotation to the page.
  Future<void> addAnnotation(PdfAnnotation annotation) async {
    PdfArray? annots = await pdfRepresentation().arrayEntry(PdfName.annots);
    if (annots == null) {
      annots = PdfArray();
      pdfRepresentation().put(PdfName.annots, annots);
    }
    annots.add(annotation.pdfRepresentation());
    annotation.setPage(this);

    // Mark page as modified for incremental updates (append mode)
    pdfRepresentation().markChanged();

    if (annotation.pdfRepresentation().isIndirectReference()) {
      // ensure indirect?
    } else {
      // if we want to ensure it is indirect, we should check/make it.
      // In , annotations are usually indirect.
    }
  }

  /// Gets the logical content of the page as a byte array.
  Future<Uint8List> contentPayload() async {
    final contents = await pdfRepresentation().get(PdfName.contents, true);
    if (contents is PdfStream) {
      return (await contents.getBytes()) ?? Uint8List(0);
    } else if (contents is PdfArray) {
      final buffer = <int>[];
      for (var i = 0; i < contents.size(); i++) {
        final content = await contents.get(i);
        if (content is PdfStream) {
          buffer.addAll((await content.getBytes()) ?? Uint8List(0));
          // Separate streams with whitespace if needed, PDF ref says concatenation.
          // Usually a whitespace or newline is safer to prevent operator merging.
          buffer.add(0x0A); // Newline
        }
      }
      return Uint8List.fromList(buffer);
    }
    return Uint8List(0);
  }

  /// Gets the next MCID for this page.
  Future<int> getNextMcid() async {
    final doc = getDocument();
    if (doc == null) return -1;
    return await doc.structureRoot().getNextMcidForPage(this);
  }

  /// Gets the StructParents entry for this page.
  Future<int?> getStructParents() async {
    return (await pdfRepresentation().numberEntry(PdfName.structParents))
        ?.intValue();
  }
}
