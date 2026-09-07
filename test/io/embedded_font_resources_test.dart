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
      expect(CraftAdobeGlyphList.nameToUnicode(entry.key), entry.value,
          reason: entry.key);
    }
    for (final entry in reverse.entries) {
      expect(CraftAdobeGlyphList.unicodeToName(entry.key), entry.value,
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
  if (CraftAdobeGlyphList.nameToUnicode('A') != 65 ||
      CraftAdobeGlyphList.nameToUnicode('Delta') != 0x394 ||
      CraftAdobeGlyphList.nameToUnicode('Omega') != 0x3a9 ||
      CraftAdobeGlyphList.nameToUnicode('mu') != 0x3bc ||
      CraftAdobeGlyphList.nameToUnicode('uni20AC') != 0x20ac ||
      CraftAdobeGlyphList.unicodeToName(65) != 'A') throw StateError('CraftGlyph mapping mismatch');
  final font=CraftType1Font.createBuiltInFont('Helvetica');
  if(font.getWidth(65)!=667 || font.getWidth(97)!=556 || font.getWidth(32)!=278) throw StateError('Helvetica widths changed');
  if(font.getFontNames().getFontName()!='Helvetica') throw StateError('Font name changed');
  final pdf=await CraftPdfDocument.create(CraftPdfWriter.toFile('consumer.pdf'));
  final doc=CraftDocument(pdf);
  await doc.add(CraftParagraph('Helvetica outside repository'));
  await doc.close(); await pdf.close();
  if(!File('consumer.pdf').readAsStringSync(encoding:systemEncoding).startsWith('%PDF-')) throw StateError('PDF missing');
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
