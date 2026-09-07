import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:test/test.dart';
import 'package:dpdf/src/io/font/adobe_glyph_list.dart';
import 'package:dpdf/src/io/resources/embedded_font_resources.dart';

void main() {
  test(
      'Embedded glyph and metric resources preserve exact source bytes and aliases',
      () async {
    final glyphUri = await Isolate.resolvePackageUri(
        Uri.parse('package:dpdf/src/io/resources/AdobeGlyphList.txt'));
    final source = File.fromUri(glyphUri!).readAsStringSync();
    expect(EmbeddedFontResources.glyphList, source);
    final afmUri = await Isolate.resolvePackageUri(
        Uri.parse('package:dpdf/src/io/resources/afm/Helvetica.afm'));
    expect(EmbeddedFontResources.metrics('Helvetica'),
        File.fromUri(afmUri!).readAsBytesSync());
    final forward = <String, int>{}, reverse = <int, String>{};
    for (final line in const LineSplitter().convert(source)) {
      if (line.startsWith('#') || line.trim().isEmpty) continue;
      final parts = line.split(';');
      if (parts[1].trim().contains(' ')) continue;
      final value = int.parse(parts[1].trim(), radix: 16);
      forward[parts[0]] = value;
      reverse[value] = parts[0];
    }
    for (final entry in forward.entries) {
      expect(AdobeGlyphList.nameToUnicode(entry.key), entry.value,
          reason: entry.key);
    }
    for (final entry in reverse.entries) {
      expect(AdobeGlyphList.unicodeToName(entry.key), entry.value,
          reason: 'U+${entry.key.toRadixString(16)}');
    }
  });
  test('A consumer creates Helvetica PDF outside repository cwd', () async {
    final packageConfig = File('.dart_tool/package_config.json').absolute;
    final temporary =
        Directory.systemTemp.createTempSync('dpdf_font_consumer_');
    addTearDown(() => temporary.deleteSync(recursive: true));
    final script = File('${temporary.path}/consumer.dart');
    script.writeAsStringSync(r'''
import 'dart:io';
import 'package:dpdf/src/io/font/adobe_glyph_list.dart';
import 'package:dpdf/src/io/font/type1_font.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/layout/document.dart';
import 'package:dpdf/src/layout/element/paragraph.dart';
Future<void> main() async {
  if (AdobeGlyphList.nameToUnicode('A') != 65 ||
      AdobeGlyphList.nameToUnicode('Delta') != 0x394 ||
      AdobeGlyphList.nameToUnicode('Omega') != 0x3a9 ||
      AdobeGlyphList.nameToUnicode('mu') != 0x3bc ||
      AdobeGlyphList.nameToUnicode('uni20AC') != 0x20ac ||
      AdobeGlyphList.unicodeToName(65) != 'A') throw StateError('Glyph mapping mismatch');
  final font=Type1Font.createBuiltInFont('Helvetica');
  if(font.getWidth(65)!=667 || font.getWidth(97)!=556 || font.getWidth(32)!=278) throw StateError('Helvetica widths changed');
  if(font.getFontNames().getFontName()!='Helvetica') throw StateError('Font name changed');
  final pdf=await PdfDocument.create(PdfWriter.toFile('consumer.pdf'));
  final doc=Document(pdf);
  await doc.add(Paragraph('Helvetica outside repository'));
  await doc.close(); await pdf.close();
  // Ler bytes, nao texto: um PDF tem dados binarios, e decodifica-lo com
  // systemEncoding so funciona onde essa codificacao aceita qualquer byte.
  // Em Linux e macOS ela e UTF-8, e a leitura lanca.
  final header = File('consumer.pdf').readAsBytesSync().take(5).toList();
  if(String.fromCharCodes(header) != '%PDF-') throw StateError('PDF missing');
  stdout.write('consumer-fonts-ok');
}
''');
    final result = await Process.run(Platform.resolvedExecutable,
        ['--packages=${packageConfig.path}', script.path],
        workingDirectory: temporary.path);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('consumer-fonts-ok'));
    expect(
        File('${temporary.path}/consumer.pdf').lengthSync(), greaterThan(100));
  });
}
