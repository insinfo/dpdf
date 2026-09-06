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
class CraftPdfPage extends CraftPdfObjectWrapper<CraftPdfDictionary> {
  CraftPdfResources? _resources;
  CraftPdfPages? _parentPages;

  CraftPdfPage(CraftPdfDictionary pdfObject) : super(pdfObject) {
    pdfObject.put(CraftPdfName.type, CraftPdfName.page);
  }

  @override
  bool requiresIndirectStorage() => true;

  Future<CraftPdfResources> resourceDirectory() async {
    if (_resources == null) {
      final resDict =
          await pdfRepresentation().dictionaryEntry(CraftPdfName.resources);
      if (resDict != null) {
        _resources = CraftPdfResources(resDict);
        await _resources!.init();
      } else {
        _resources = CraftPdfResources();
        pdfRepresentation()
            .put(CraftPdfName.resources, _resources!.pdfRepresentation());
      }
    }
    return _resources!;
  }

  CraftPdfPages? get parentPages => _parentPages;
  set parentPages(CraftPdfPages? value) => _parentPages = value;

  /// Gets the media box for this page.
  Future<CraftRectangle> mediaBounds() async {
    final array = await pdfRepresentation().arrayEntry(CraftPdfName.mediaBox);
    return array != null
        ? await CraftRectangle.fromPdfArray(array) ?? CraftPageSize.defaultSize
        : CraftPageSize.defaultSize;
  }

  /// Sets the media box for this page.
  void setMediaBounds(CraftRectangle rect) {
    pdfRepresentation().put(CraftPdfName.mediaBox, rect.toPdfArray());
  }

  /// Gets the crop box for this page.
  Future<CraftRectangle> cropBounds() async {
    final array = await pdfRepresentation().arrayEntry(CraftPdfName.cropBox);
    if (array != null) {
      final rect = await CraftRectangle.fromPdfArray(array);
      if (rect != null) return rect;
    }
    return await mediaBounds();
  }

  /// Sets the crop box for this page.
  void setCropBounds(CraftRectangle rect) {
    pdfRepresentation().put(CraftPdfName.cropBox, rect.toPdfArray());
  }

  /// Gets the rotation for this page.
  Future<int> rotationDegrees() async {
    final rotate = await pdfRepresentation().numberEntry(CraftPdfName.rotate);
    return rotate != null ? rotate.intValue() % 360 : 0;
  }

  /// Sets the rotation for this page.
  void setRotationDegrees(int rotate) {
    pdfRepresentation()
        .put(CraftPdfName.rotate, CraftPdfNumber.fromInt(rotate));
  }

  /// Gets the content stream at the specified index.
  Future<CraftPdfObject?> contentSegmentAt(int index) async {
    final contents = await pdfRepresentation().get(CraftPdfName.contents, true);
    if (contents is CraftPdfStream) {
      return index == 0 ? contents : null;
    } else if (contents is CraftPdfArray) {
      return await contents.get(index);
    }
    return null;
  }

  /// Gets the count of content streams.
  Future<int> contentSegmentCount() async {
    final contents = await pdfRepresentation().get(CraftPdfName.contents, true);
    if (contents is CraftPdfStream) {
      return 1;
    } else if (contents is CraftPdfArray) {
      return contents.size();
    }
    return 0;
  }

  /// Adds an annotation to the page.
  Future<void> addAnnotation(CraftPdfAnnotation annotation) async {
    CraftPdfArray? annots =
        await pdfRepresentation().arrayEntry(CraftPdfName.annots);
    if (annots == null) {
      annots = CraftPdfArray();
      pdfRepresentation().put(CraftPdfName.annots, annots);
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
    final contents = await pdfRepresentation().get(CraftPdfName.contents, true);
    if (contents is CraftPdfStream) {
      return (await contents.getBytes()) ?? Uint8List(0);
    } else if (contents is CraftPdfArray) {
      final buffer = <int>[];
      for (var i = 0; i < contents.size(); i++) {
        final content = await contents.get(i);
        if (content is CraftPdfStream) {
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
    return (await pdfRepresentation().numberEntry(CraftPdfName.structParents))
        ?.intValue();
  }
}
