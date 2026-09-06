import 'dart:collection';
import 'dart:typed_data';

import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_document.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_object.dart';
import '../kernel/pdf/pdf_page.dart';
import '../kernel/pdf/pdf_reader.dart';
import '../kernel/pdf/pdf_stream.dart';
import '../kernel/pdf/pdf_writer.dart';

/// A source document and an ordered, one-based selection of its pages.
/// A null selection includes every page. Repeated page numbers are allowed.
class PdfPageSelection {
  final Uint8List bytes;
  final List<int>? pages;
  PdfPageSelection(this.bytes, {List<int>? pages})
      : pages = pages == null ? null : List.unmodifiable(pages);
}

/// Assembles static PDF pages without native libraries or external packages.
///
/// This is page assembly, not document-level merging: forms, signatures,
/// outlines, named destinations and tagged structure require reconciliation
/// and are rejected. The source PDFs are never modified.
class PdfPageAssembly {
  static Future<Uint8List> merge(List<PdfPageSelection> sources) async {
    if (sources.isEmpty)
      throw ArgumentError('At least one source is required.');
    final opened = <CraftPdfDocument>[];
    final selected = <List<CraftPdfPage>>[];
    try {
      // Validate every source before allocating the output document.
      for (final source in sources) {
        final reader = CraftPdfReader.fromBytes(source.bytes);
        final doc = await CraftPdfDocument.open(reader);
        opened.add(doc);
        if (reader.encrypted) {
          throw UnsupportedError('Encrypted page assembly is not supported.');
        }
        final catalog = doc.rootCatalog().pdfRepresentation();
        for (final name in [
          'AcroForm',
          'StructTreeRoot',
          'Outlines',
          'Names',
          'Dests',
          'OCProperties',
          'OpenAction',
          'AA',
          'Collection',
        ]) {
          if (catalog.containsKey(CraftPdfName(name))) {
            throw UnsupportedError('Page assembly cannot reconcile /$name.');
          }
        }
        final count = doc.pageTotal();
        final numbers = source.pages ?? List.generate(count, (i) => i + 1);
        final pages = <CraftPdfPage>[];
        for (final number in numbers) {
          if (number < 1 || number > count) {
            throw RangeError.range(number, 1, count, 'page');
          }
          final page = (await doc.pageAt(number))!;
          for (final name in [
            'Annots',
            'AA',
            'B',
            'PresSteps',
            'StructParents'
          ]) {
            if (page.pdfRepresentation().containsKey(CraftPdfName(name))) {
              throw UnsupportedError('Page assembly cannot reconcile /$name.');
            }
          }
          pages.add(page);
        }
        selected.add(pages);
      }
      if (selected.every((pages) => pages.isEmpty)) {
        throw ArgumentError('The page selection is empty.');
      }
      final bytes = BytesBuilder();
      final output =
          await CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(bytes));
      for (final pages in selected) {
        for (final page in pages) {
          // A fresh map per page also isolates repeated pages for future edits.
          final copier = _PageGraphCopy(output);
          final dictionary = CraftPdfDictionary();
          copier.copies[page.pdfRepresentation()] = dictionary;
          dictionary.attachToDocument(output);
          for (final entry in await page.pdfRepresentation().entrySet()) {
            if (entry.key == CraftPdfName.parent) continue;
            dictionary.put(entry.key, await copier.copy(entry.value));
          }
          // PDF page-tree attributes may live on an ancestor, not the leaf.
          for (final name in ['Resources', 'MediaBox', 'CropBox', 'Rotate']) {
            final key = CraftPdfName(name);
            if (dictionary.containsKey(key)) continue;
            CraftPdfDictionary? ancestor = page.pdfRepresentation();
            final visited = HashSet<CraftPdfDictionary>.identity();
            while (ancestor != null && visited.add(ancestor)) {
              final value = await ancestor.get(key);
              if (value != null) {
                dictionary.put(key, await copier.copy(value));
                break;
              }
              ancestor = await ancestor.dictionaryEntry(CraftPdfName.parent);
            }
          }
          await output.appendPageObject(CraftPdfPage(dictionary));
        }
      }
      await output.close();
      return bytes.takeBytes();
    } finally {
      for (final doc in opened) {
        await doc.close();
      }
    }
  }
}

class _PageGraphCopy {
  final CraftPdfDocument destination;
  final copies = HashMap<CraftPdfObject, CraftPdfObject>.identity();
  _PageGraphCopy(this.destination);

  Future<CraftPdfObject> copy(CraftPdfObject object) async {
    if (object is CraftPdfIndirectReference) {
      final target = await object.targetObject(true);
      if (target == null) throw FormatException('Unresolved PDF reference.');
      return copy(target);
    }
    final previous = copies[object];
    if (previous != null) return previous;
    if (object is CraftPdfDictionary) {
      final CraftPdfDictionary result;
      if (object is CraftPdfStream) {
        // Preserve encoded bytes and their matching filter dictionaries.
        result = CraftPdfStream.withBytes(await object.getBytes(false), 0);
      } else {
        result = CraftPdfDictionary();
      }
      copies[object] = result;
      // Indirect containers preserve cycles and sharing without recursion
      // during serialization, even when a source container was direct.
      result.attachToDocument(destination);
      for (final entry in await object.entrySet()) {
        if (object is CraftPdfStream && entry.key == CraftPdfName.length)
          continue;
        result.put(entry.key, await copy(entry.value));
      }
      return result;
    }
    if (object is CraftPdfArray) {
      final result = CraftPdfArray();
      copies[object] = result;
      result.attachToDocument(destination);
      for (var i = 0; i < object.size(); i++) {
        final value = await object.get(i, false);
        if (value == null) throw FormatException('Missing PDF array item.');
        result.add(await copy(value));
      }
      return result;
    }
    final result = object.clone();
    copies[object] = result;
    return result;
  }
}
