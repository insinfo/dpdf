import 'dart:convert';

import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

Future<List<PdfPositionedCharacter>> _positions(
    CraftPdfDocument document) async {
  final page = (await document.pageAt(1))!;
  return PdfTextPositions.fromContent(await page.contentPayload(),
      decoder: (_, codes) => latin1.decode(codes), width: (_, __) => 600);
}

PdfPositionedCharacter _firstCharacter(
    List<PdfPositionedCharacter> characters, String character) {
  return characters.firstWhere((position) => position.text == character);
}

void main() {
  test('converts text-flow HTML to an extractable PDF', () async {
    final bytes = await CraftHtmlConverter.convertToBytes('''
      <h1>Relatório</h1><p>Olá <strong>mundo</strong>!</p>
      <ul><li>primeiro item</li><li>segundo item</li></ul>
      <table><tr><th>Chave</th><th>Valor</th></tr><tr><td>A</td><td>1</td></tr></table>
    ''');
    final document =
        await CraftPdfDocument.open(CraftPdfReader.fromBytes(bytes));
    try {
      expect(await document.pageTotal(), 1);
      final page = await document.pageAt(1);
      final text = await PdfTextExtraction.fromPage(page!);
      expect(text, contains('Relatório'));
      expect(text, contains('mundo'));
      expect(text, contains('primeiro item'));
      expect(text, contains('Chave'));
      expect(text, contains('Valor'));
    } finally {
      await document.close();
    }
  });

  test('paginates long content and ignores executable markup', () async {
    final lines = List.filled(200, '<p>linha segura de teste</p>').join();
    final bytes = await CraftHtmlConverter.convertToBytes(
        '<script>throw new Error()</script>$lines');
    final document =
        await CraftPdfDocument.open(CraftPdfReader.fromBytes(bytes));
    try {
      expect(await document.pageTotal(), greaterThan(1));
    } finally {
      await document.close();
    }
  });

  test('resolves tag, class and id rules for flex and grid containers',
      () async {
    final bytes = await CraftHtmlConverter.convertToBytes('''
      <style>
        section { display: flex; flex-direction: row; }
        .grid { display: grid; grid-template-columns: repeat(2, 1fr); }
        #title { font-size: 18pt; }
      </style>
      <h1 id="title">Catálogo</h1>
      <section><div>Flex A</div><div>Flex B</div></section>
      <div class="grid"><div>Grid 1</div><div>Grid 2</div><div>Grid 3</div></div>
    ''');
    final document =
        await CraftPdfDocument.open(CraftPdfReader.fromBytes(bytes));
    try {
      final text =
          await PdfTextExtraction.fromPage((await document.pageAt(1))!);
      expect(text, contains('Catálogo'));
      expect(text, contains('Flex A'));
      expect(text, contains('Flex B'));
      expect(text, contains('Grid 1'));
      expect(text, contains('Grid 2'));
      expect(text, contains('Grid 3'));
    } finally {
      await document.close();
    }
  });

  test('writes text for an HTML box with CSS paint properties', () async {
    final bytes = await CraftHtmlConverter.convertToBytes('''
      <style>.paint { color:#f00; background-color:#00ff00; border:1pt solid #0000ff; }</style>
      <div class="paint">conteúdo colorido</div>
    ''');
    final document =
        await CraftPdfDocument.open(CraftPdfReader.fromBytes(bytes));
    try {
      final text =
          await PdfTextExtraction.fromPage((await document.pageAt(1))!);
      expect(text, contains('conteúdo colorido'));
    } finally {
      await document.close();
    }
  });

  test('writes ordered list markers including start reversed and li value',
      () async {
    final bytes = await CraftHtmlConverter.convertToBytes('''
      <ol start="3"><li>três</li><li value="9">nove</li><li>dez</li></ol>
      <ol reversed><li>fim</li><li value="7">sete</li><li>seis</li></ol>
    ''');
    final document =
        await CraftPdfDocument.open(CraftPdfReader.fromBytes(bytes));
    try {
      final text =
          await PdfTextExtraction.fromPage((await document.pageAt(1))!);
      expect(text, contains('3. três'));
      expect(text, contains('9. nove'));
      expect(text, contains('10. dez'));
      expect(text, contains('3. fim'));
      expect(text, contains('7. sete'));
      expect(text, contains('6. seis'));
    } finally {
      await document.close();
    }
  });

  test('places flex row children at separate physical X coordinates', () async {
    final bytes = await CraftHtmlConverter.convertToBytes('''
      <style>.row { display: flex; gap: 12pt; }</style>
      <div class="row"><div>north</div><div>east</div></div>
    ''');
    final document =
        await CraftPdfDocument.open(CraftPdfReader.fromBytes(bytes));
    try {
      final positions = await _positions(document);
      final north = _firstCharacter(positions, 'n');
      final east = _firstCharacter(positions, 'e');
      // Flex items retain their intrinsic widths, so only their distinct
      // physical columns are contractual here.
      expect(east.x, greaterThan(north.x + 20));
      expect(east.y, closeTo(north.y, .001));
    } finally {
      await document.close();
    }
  });

  test('places grid cells by column and subsequent rows by baseline', () async {
    final bytes = await CraftHtmlConverter.convertToBytes('''
      <style>.grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 8pt; }</style>
      <div class="grid"><div>one</div><div>two</div><div>three</div></div>
    ''');
    final document =
        await CraftPdfDocument.open(CraftPdfReader.fromBytes(bytes));
    try {
      final positions = await _positions(document);
      final one = _firstCharacter(positions, 'o');
      final two = _firstCharacter(positions, 't');
      // The second `t` belongs to `three`; it starts the second grid row.
      final rowTwo = positions.where((position) => position.text == 't').last;
      expect(two.x, greaterThan(one.x + 100));
      expect(two.y, closeTo(one.y, .001));
      expect(rowTwo.x, closeTo(one.x, .001));
      expect(rowTwo.y, lessThan(one.y - 10));
    } finally {
      await document.close();
    }
  });

  test('turns anchor text into an invisible URI link annotation', () async {
    final bytes = await CraftHtmlConverter.convertToBytes(
        '<p>Leia <a href="https://example.test/manual"><strong>manual</strong></a>.</p>');
    final document =
        await CraftPdfDocument.open(CraftPdfReader.fromBytes(bytes));
    try {
      final page = (await document.pageAt(1))!;
      final annotations =
          await page.pdfRepresentation().arrayEntry(CraftPdfName.annots);
      expect(annotations, isNotNull);
      expect(annotations!.size(), 1);
      final annotation = (await annotations.dictionaryEntry(0))!;
      expect((await annotation.nameEntry(CraftPdfName.subtype))!.getValue(),
          'Link');
      final action = (await annotation.dictionaryEntry(CraftPdfName.a))!;
      expect((await action.nameEntry(CraftPdfName.s))!.getValue(), 'URI');
      expect((await action.stringEntry(CraftPdfName.uri))!.getValue(),
          'https://example.test/manual');
      expect(await annotation.arrayEntry(CraftPdfName.rect), isNotNull);
    } finally {
      await document.close();
    }
  });

  test('embeds a PNG data URI as a PDF image XObject', () async {
    const pixel =
        'iVBORw0KGgoAAAANSUhEUgAAAEAAAAAwCAAAAACEICPDAAAAXElEQVR4nO3QwQmAABDEQBWT/hsWLCKPBfEKGLJ3Xke7mwr4F9wfeCIVcF5ABZwXUAHnBVTAeQEVcF5ABZwXUAHnBVTAeQEVcF5ABZwXUAHnBVTAeQEVqBPOJwIv4oUCsFqUwOcAAAAASUVORK5CYII=';
    final bytes = await CraftHtmlConverter.convertToBytes(
        '<img src="data:image/png;base64,$pixel" width="20" height="10" alt="ignored">');
    final document =
        await CraftPdfDocument.open(CraftPdfReader.fromBytes(bytes));
    try {
      final content = await (await document.pageAt(1))!.contentPayload();
      expect(String.fromCharCodes(content), contains(' Do'));
      expect(String.fromCharCodes(bytes), contains('/Subtype /Image'));
    } finally {
      await document.close();
    }
  });

  test('places structured table cells in PDF columns and rows', () async {
    final bytes = await CraftHtmlConverter.convertToBytes('''
      <table><thead><tr><th>NorthCell</th><th>EastCell</th></tr></thead>
      <tbody><tr><td>LowerCell</td><td>TailCell</td></tr></tbody></table>
    ''');
    final document =
        await CraftPdfDocument.open(CraftPdfReader.fromBytes(bytes));
    try {
      final positions = await _positions(document);
      final north = _firstCharacter(positions, 'N');
      final east = _firstCharacter(positions, 'E');
      final lower = _firstCharacter(positions, 'L');
      expect(east.x, greaterThan(north.x + 100));
      expect(east.y, closeTo(north.y, .001));
      expect(lower.x, closeTo(north.x, .001));
      expect(lower.y, lessThan(north.y - 10));
    } finally {
      await document.close();
    }
  });
}
