import 'dart:typed_data';
import 'package:pdfcraft/src/io/font/open_type_parser.dart';
import 'package:pdfcraft/src/io/font/true_type_font.dart';
import 'package:test/test.dart';

CraftOpenTypeParser parser(int revision, int size, {int? declaredSize}) {
  final bytes = Uint8List(28 + size);
  final view = ByteData.sublistView(bytes);
  view.setUint32(0, 0x00010000);
  view.setUint16(4, 1);
  bytes.setRange(12, 16, 'OS/2'.codeUnits);
  view.setUint32(20, 28);
  view.setUint32(24, declaredSize ?? size);
  if (size >= 2) view.setUint16(28, revision);
  return CraftOpenTypeParser(bytes);
}

ByteData fields(CraftOpenTypeParser parser) =>
    ByteData.sublistView(parser.raf.getBytes(), 28);

void main() {
  test('OS/2 version zero does not read codepage fields outside its table', () {
    final font = parser(0, 78);
    fields(font)
      ..setInt16(68, 750)
      ..setInt16(70, -250)
      ..setUint16(8, 0x8000);
    font.raf.seek(7);
    font.loadWindowsMetrics();
    expect(font.os_2.sTypoAscender, 750);
    expect(font.os_2.sTypoDescender, -250);
    expect(font.os_2.ulCodePageRange1, 0);
    expect(font.os_2.fsType, 0x8000);
    expect(font.raf.getPosition(), 7);
  });
  test('Short historical OS/2 version zero is accepted at 68 bytes', () {
    final font = parser(0, 68);
    fields(font).setUint16(66, 0x1234);
    font.loadWindowsMetrics();
    expect(font.os_2.usLastCharIndex, 0x1234);
    expect(font.os_2.usWinAscent, 0);
  });
  test('OS/2 revision one reads unsigned codepage words', () {
    final font = parser(1, 86);
    fields(font)
      ..setUint32(78, 0x80000000)
      ..setUint32(82, 0xffffffff);
    font.loadWindowsMetrics();
    expect(font.os_2.ulCodePageRange1, 0x80000000);
    expect(font.os_2.ulCodePageRange2, 0xffffffff);
    expect(font.os_2.sCapHeight, 0);
  });
  test('OS/2 extended revisions read height and script fields by fixed offsets',
      () {
    for (final revision in [2, 3, 4, 5]) {
      final font = parser(revision, revision == 5 ? 100 : 96);
      fields(font)
        ..setInt16(10, 320)
        ..setInt16(24, 460)
        ..setInt16(86, 480)
        ..setInt16(88, 720);
      font.loadWindowsMetrics();
      expect(font.os_2.ySubscriptXSize, 320);
      expect(font.os_2.ySuperscriptYOffset, 460);
      expect(font.os_2.sxHeight, 480);
      expect(font.os_2.sCapHeight, 720);
    }
  });
  test(
      'Malformed OS/2 spans and incomplete versions fail without partial state',
      () {
    for (final font in [
      parser(0, 70),
      parser(1, 78),
      parser(2, 90),
      parser(5, 96),
      parser(0, 78, declaredSize: 100)
    ]) {
      font.os_2 = WindowsMetrics()..usWeightClass = 321;
      expect(font.loadWindowsMetrics, throwsFormatException);
      expect(font.os_2.usWeightClass, 321);
    }
    expect(parser(6, 100).loadWindowsMetrics, throwsUnsupportedError);
  });
  test('Font metric snapshot consistently scales geometry and decorations', () {
    final font = CraftTrueTypeFont.fromFile('test/assets/ABeeZee-Regular.ttf');
    final source = font.fontParser;
    source.head
      ..unitsPerEm = 2000
      ..xMin = -100
      ..yMin = -400
      ..xMax = 1800
      ..yMax = 1600;
    source.os_2
      ..ySuperscriptYSize = 700
      ..ySubscriptYSize = 600
      ..ySubscriptYOffset = 200
      ..sCapHeight = 1400;
    source.post
      ..underlinePosition = -200
      ..underlineThickness = 100;
    font.refreshParsedMetrics();
    final metric = font.getFontMetrics();
    expect(metric.getBbox(), [-50, -200, 900, 800]);
    expect(metric.getCapHeight(), 700);
    expect(metric.getSuperscriptSize(), 350);
    expect(metric.getSubscriptSize(), 300);
    expect(metric.getSubscriptOffset(), -100);
    expect(metric.getUnderlineThickness(), 50);
    expect(metric.getUnderlinePosition(), -125);
    expect(metric.getGlyphWidths(), isNotEmpty);
    expect(
        identical(metric.getGlyphWidths(), source.glyphWidthsByIndex), isFalse);
  });
}
