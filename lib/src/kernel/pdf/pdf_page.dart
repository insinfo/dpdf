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

  PdfPage(PdfDictionary pdfObject) : super(pdfObject);

  @override
  bool isWrappedObjectMustBeIndirect() => true;

  Future<PdfResources> getResources() async {
    if (_resources == null) {
      final resDict = await getPdfObject().getAsDictionary(PdfName.resources);
      if (resDict != null) {
        _resources = PdfResources(resDict);
        await _resources!.init();
      } else {
        _resources = PdfResources();
        getPdfObject().put(PdfName.resources, _resources!.getPdfObject());
      }
    }
    return _resources!;
  }

  PdfPages? get parentPages => _parentPages;
  set parentPages(PdfPages? value) => _parentPages = value;

  /// Gets the media box for this page.
  Future<Rectangle> getMediaBox() async {
    final array = await getPdfObject().getAsArray(PdfName.mediaBox);
    return array != null
        ? await Rectangle.fromPdfArray(array) ?? PageSize.defaultSize
        : PageSize.defaultSize;
  }

  /// Sets the media box for this page.
  void setMediaBox(Rectangle rect) {
    getPdfObject().put(PdfName.mediaBox, rect.toPdfArray());
  }

  /// Gets the crop box for this page.
  Future<Rectangle> getCropBox() async {
    final array = await getPdfObject().getAsArray(PdfName.cropBox);
    if (array != null) {
      final rect = await Rectangle.fromPdfArray(array);
      if (rect != null) return rect;
    }
    return await getMediaBox();
  }

  /// Sets the crop box for this page.
  void setCropBox(Rectangle rect) {
    getPdfObject().put(PdfName.cropBox, rect.toPdfArray());
  }

  /// Gets the rotation for this page.
  Future<int> getRotation() async {
    final rotate = await getPdfObject().getAsNumber(PdfName.rotate);
    return rotate != null ? rotate.intValue() % 360 : 0;
  }

  /// Sets the rotation for this page.
  void setRotation(int rotate) {
    getPdfObject().put(PdfName.rotate, PdfNumber.fromInt(rotate));
  }

  /// Gets the content stream at the specified index.
  Future<PdfObject?> getContentStream(int index) async {
    final contents = await getPdfObject().get(PdfName.contents, true);
    if (contents is PdfStream) {
      return index == 0 ? contents : null;
    } else if (contents is PdfArray) {
      return await contents.get(index);
    }
    return null;
  }

  /// Gets the count of content streams.
  Future<int> getContentStreamCount() async {
    final contents = await getPdfObject().get(PdfName.contents, true);
    if (contents is PdfStream) {
      return 1;
    } else if (contents is PdfArray) {
      return contents.size();
    }
    return 0;
  }

  /// Adds an annotation to the page.
  Future<void> addAnnotation(PdfAnnotation annotation) async {
    PdfArray? annots = await getPdfObject().getAsArray(PdfName.annots);
    if (annots == null) {
      annots = PdfArray();
      getPdfObject().put(PdfName.annots, annots);
    }
    annots.add(annotation.getPdfObject());
    annotation.setPage(this);
    if (annotation.getPdfObject().isIndirectReference()) {
      // ensure indirect?
    } else {
      // if we want to ensure it is indirect, we should check/make it.
      // In iText, annotations are usually indirect.
    }
  }

  /// Gets the logical content of the page as a byte array.
  Future<Uint8List> getContentBytes() async {
    final contents = await getPdfObject().get(PdfName.contents, true);
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
}
