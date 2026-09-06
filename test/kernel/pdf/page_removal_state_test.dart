import 'dart:typed_data';
import 'package:pdfcraft/src/commons/actions/event_manager.dart';
import 'package:pdfcraft/src/kernel/pdf/event/pdf_document_event.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_document.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_name.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_writer.dart';
import 'package:test/test.dart';

class _Observer implements CraftEventHandler {
  final void Function(CraftEvent) inspect;
  _Observer(this.inspect);
  @override
  void onEvent(CraftEvent event) => inspect(event);
}

void main() {
  test('Removal notification sees the committed page collection', () async {
    final doc = await CraftPdfDocument.create(
        CraftPdfWriter.fromBytesBuilder(BytesBuilder()));
    final removed = await doc.appendBlankPage();
    final survivor = await doc.appendBlankPage();
    final dictionary = removed.pdfRepresentation();
    var notifications = 0;
    doc.subscribeEvent(CraftPdfDocumentEvent.detachPage, _Observer((event) {
      notifications++;
      expect(doc.pageTotal(), 1);
      expect((event as CraftPdfDocumentEvent).pageAt(), same(dictionary));
      expect(dictionary.containsKey(CraftPdfName.parent), isFalse);
      expect(removed.parentPages, isNull);
      expect(dictionary.indirectHandle()!.isFree(), isTrue);
    }));
    await doc.deletePageAt(1);
    expect(notifications, 1);
    expect(await doc.pageAt(1), same(survivor));
    await doc.close();
  });

  test('Invalid page ordinals leave all page state intact', () async {
    final doc = await CraftPdfDocument.create(
        CraftPdfWriter.fromBytesBuilder(BytesBuilder()));
    final page = await doc.appendBlankPage();
    final dictionary = page.pdfRepresentation();
    final parent = await dictionary.get(CraftPdfName.parent);
    var notifications = 0;
    doc.subscribeEvent(
        CraftPdfDocumentEvent.detachPage, _Observer((_) => notifications++));
    for (final ordinal in [-1, 0, 2]) {
      await expectLater(doc.deletePageAt(ordinal), throwsRangeError);
      expect(doc.pageTotal(), 1);
      expect(await doc.pageAt(1), same(page));
      expect(await dictionary.get(CraftPdfName.parent), same(parent));
      expect(dictionary.indirectHandle()!.isFree(), isFalse);
    }
    expect(notifications, 0);
    await doc.close();
  });
}
