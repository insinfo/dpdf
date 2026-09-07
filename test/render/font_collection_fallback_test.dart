import 'dart:io';

import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

void main() {
  test('catálogo dgfx alimenta o fallback público do renderizador', () async {
    final bytes = await File('test/assets/ABeeZee-Regular.ttf').readAsBytes();
    final collection = BLFontCollection()..addBytes(bytes, familyName: 'Arial');
    final fallback = pdfFontFallbackFromCollection(collection);

    final resolved = await fallback(const PdfFontRequest(
      baseFont: 'ABCDEF+Arial',
      flags: 0,
      composite: false,
    ));

    expect(resolved, same(collection.faces.single.data));
  });

  test('provedor assíncrono pode representar URL, FontFace ou Google Fonts',
      () async {
    final bytes = await File('test/assets/ABeeZee-Regular.ttf').readAsBytes();
    BLFontQuery? received;
    final collection = BLFontCollection()
      ..addProvider(BLCallbackFontProvider((query) async {
        received = query;
        return bytes;
      }));

    final resolved = await pdfFontFallbackFromCollection(collection)(
      const PdfFontRequest(
        baseFont: 'Arial-BoldItalic',
        flags: 0,
        composite: false,
      ),
    );

    expect(resolved, isNotNull);
    expect(received!.families.first, 'Arial');
    expect(received!.weight, 700);
    expect(received!.slant, BLFontSlant.italic);
  });
}
