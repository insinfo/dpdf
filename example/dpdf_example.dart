import 'dart:io';
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:dgfx/dgfx_io.dart';

/// A tour of the four things the library is asked for most often: converting
/// HTML, inspecting a file, verifying conformance and redacting.
///
/// Run it from the root of the package:
///
/// ```
/// dart run example/dpdf_example.dart
/// ```
///
/// With no argument it writes its artefacts to the current directory. Pass
/// another directory as the argument to choose where they go.
Future<void> main(List<String> arguments) async {
  final destination =
      arguments.isEmpty ? Directory.current : Directory(arguments.first);

  final report = await _convertHtml();
  await _save(destination, 'report.html.pdf', report);

  await _inspect(report);
  await _verifyConformance(report);

  final redacted = await _redactArea();
  await _save(destination, 'redacted.pdf', redacted);
  final fonts = BLFontCollection();
  final fallback = await const BLFontLoader().loadSystemFont(
    fonts,
    const BLFontQuery([
      'Arial',
      'Liberation Sans',
      'DejaVu Sans',
      'Noto Sans',
    ]),
  );
  print('fallback font ......: ${fallback?.familyName ?? 'not found'}');
  print('fonts examined .....: ${fonts.faces.length}');
  final document = await PdfDocument.open(PdfReader.fromBytes(redacted));
  final page = await document.pageAt(1);
  if (page == null) {
    await document.close();
    throw StateError('The redacted PDF has no first page.');
  }
  final result = await PdfPageRenderer.render(page,
      options:
          PdfRenderOptions(fontFallback: pdfFontFallbackFromCollection(fonts)));
  print('text skipped .......: ${result.report.glyphsSkipped}');
  final png = result.toPng();
  await document.close();
  await _save(destination, 'redacted.png', png);
}

/// HTML to PDF. The converter measures the text with the metrics of the very
/// face it is going to draw, so line breaking and alignment are exact.
Future<Uint8List> _convertHtml() async {
  const html = '''
    <html><body>
      <h1 style="font-family: serif">Quarterly report</h1>
      <p>This paragraph is broken into lines using the real widths of
         Helvetica, not an estimated average width.</p>
      <table>
        <tr><th>Item</th><th>Value</th></tr>
        <tr><td>Licenses</td><td>12,400</td></tr>
        <tr><td>Support</td><td>3,100</td></tr>
      </table>
      <p style="font-family: monospace">Footer in Courier.</p>
    </body></html>
  ''';

  final bytes = await HtmlConverter.convertToBytes(html);
  print('HTML converted: ${bytes.length} bytes');
  return bytes;
}

/// Structural inspection: whether the file opens, and what would break a
/// reader.
Future<void> _inspect(Uint8List bytes) async {
  final report = await PdfIntegrityChecker.inspect(bytes);

  print('\nIntegrity');
  print('  readable ........... ${report.readable}');
  print('  damaged ............ ${report.isDamaged}');
  print('  pages .............. ${report.reachablePageCount}');
  print('  objects ............ ${report.objectCount}');
  print('  header version ..... ${report.headerVersion}');
  for (final finding in report.findings) {
    print('  $finding');
  }
}

/// PDF/A conformance: the report also says what was not evaluated, so a clean
/// result is not mistaken for a certification.
Future<void> _verifyConformance(Uint8List bytes) async {
  final report = await PdfAVerifier.verify(
    bytes,
    level: PdfAConformanceLevel.a2b,
  );

  print('\nConformance ${report.profile}');
  print('  claimed in the XMP . ${report.claimedProfile ?? 'none'}');
  print('  conforming ......... ${report.isConforming}');
  for (final violation in report.violations) {
    print('  ${violation.code} (${violation.clause})');
  }
  print('  rules not evaluated: ${report.unverifiedRules.length}');
}

/// Area redaction: removes the characters inside the rectangle from the
/// content stream and covers the region with an opaque bar.
Future<Uint8List> _redactArea() async {
  final output = BytesBuilder(copy: false);
  final document = PdfDocument.create(PdfWriter.fromBytesBuilder(output));
  final page = await document.appendBlankPage();
  final canvas = await PdfCanvas.fromPage(page);
  canvas.beginText();
  await canvas.setFontAndSize(PdfFontFactory.createFont('Helvetica'), 12);
  canvas
      .moveText(72, 700)
      .showText('Customer: Maria Souza')
      .moveText(0, -20)
      .showText('Tax id: 123.456.789-00')
      .moveText(0, -20)
      .showText('Total: 1,250.00')
      .endText();
  await document.close();
  final original = output.takeBytes();

  final redacted = await PdfAreaRedaction.apply(original, [
    // The tax id line, in the page's user space coordinates.
    PdfRedactionArea(1, left: 70, bottom: 675, right: 300, top: 693),
  ]);

  final reader = PdfReader.fromBytes(redacted);
  final reopened = await PdfDocument.open(reader);
  try {
    final text = await PdfTextExtraction.fromPage((await reopened.pageAt(1))!);
    print('\nRedaction');
    print('  tax id still there: ${text.contains('123.456.789-00')}');
    print('  name preserved ...: ${text.contains('Maria Souza')}');
  } finally {
    await reopened.close();
  }
  return redacted;
}

Future<void> _save(Directory? destination, String name, Uint8List bytes) async {
  if (destination == null) return;
  await destination.create(recursive: true);
  final file = File('${destination.path}/$name');
  await file.writeAsBytes(bytes);
  print('written: ${file.path}');
}
