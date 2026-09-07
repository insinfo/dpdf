import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_document.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_stream.dart';

/// Metadata for one image stream, collected without decoding its payload.
class PdfImageInventoryEntry {
  final int objectNumber;
  final int generation;
  final int? width;
  final int? height;
  final int? bitsPerComponent;
  final int encodedLength;
  final bool imageMask;
  final List<String> filters;

  const PdfImageInventoryEntry({
    required this.objectNumber,
    required this.generation,
    required this.width,
    required this.height,
    required this.bitsPerComponent,
    required this.encodedLength,
    required this.imageMask,
    required this.filters,
  });
}

/// Result of scanning the xref for image XObjects.
class PdfImageInventoryReport {
  final List<PdfImageInventoryEntry> images;
  final int objectsExamined;
  final int objectsSkipped;

  const PdfImageInventoryReport(
      this.images, this.objectsExamined, this.objectsSkipped);
}

/// Fast image enumeration similar to `mutool extract`'s discovery pass.
///
/// It walks xref entries and reads only object dictionaries. Stream payloads
/// remain deferred until a caller explicitly invokes `PdfStream.getBytes()`.
abstract final class PdfImageInventory {
  static Future<PdfImageInventoryReport> inspect(PdfDocument document) async {
    final reader = document.inputReader();
    if (reader == null) {
      throw StateError(
          'Image inventory requires a document opened for reading.');
    }
    final images = <PdfImageInventoryEntry>[];
    var examined = 0;
    var skipped = 0;
    for (var number = 1; number < reader.xref.size(); number++) {
      final reference = reader.xref.get(number);
      if (reference == null || reference.isFree()) continue;
      examined++;
      try {
        final object = await reader.readObject(number);
        if (object is! PdfStream ||
            (await object.nameEntry(PdfName.subtype))?.getValue() != 'Image') {
          continue;
        }
        images.add(PdfImageInventoryEntry(
          objectNumber: number,
          generation: reference.generationNumber(),
          width: await object.integerEntry(PdfName.width),
          height: await object.integerEntry(PdfName.height),
          bitsPerComponent:
              await object.integerEntry(PdfName('BitsPerComponent')),
          encodedLength: object.getLength(),
          imageMask: await object.flagEntry(PdfName('ImageMask')) ?? false,
          filters: await _filters(object),
        ));
      } on Object {
        skipped++;
      }
    }
    return PdfImageInventoryReport(
        List.unmodifiable(images), examined, skipped);
  }

  static Future<List<String>> _filters(PdfDictionary dictionary) async {
    final filter = await dictionary.get(PdfName.filter, true);
    if (filter is PdfName) return [filter.getValue()];
    if (filter is PdfArray) {
      final names = <String>[];
      for (var index = 0; index < filter.size(); index++) {
        final item = await filter.get(index, true);
        if (item is PdfName) names.add(item.getValue());
      }
      return names;
    }
    return const [];
  }
}
