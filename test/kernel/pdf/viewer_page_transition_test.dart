import 'dart:typed_data';

import 'package:dpdf/src/kernel/exceptions/pdf_exception.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_page.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/viewer/pdf_transition.dart';
import 'package:test/test.dart';

/// Builds a one page document, lets [build] set up the presentation entries,
/// closes it and reopens the bytes, returning the reloaded page.
Future<PdfPage> roundtrip(Future<void> Function(PdfPage) build) async {
  final bytes = BytesBuilder();
  final doc = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
  final page = await doc.appendBlankPage();
  await build(page);
  await doc.close();

  final reopened = await PdfDocument.open(PdfReader.fromBytes(bytes.toBytes()));
  addTearDown(reopened.close);
  return (await reopened.firstPage())!;
}

void main() {
  group('page transitions (ISO 32000-1:2008, 12.4.4, Tables 30 and 162)', () {
    test('all twelve Table 162 styles survive a roundtrip', () async {
      for (final style in PdfPageTransitionStyle.values) {
        final page = await roundtrip((page) async {
          page.setTransition(PdfTransition(style));
        });
        final transition = await page.getTransition();
        expect(transition, isNotNull, reason: style.pdfName);
        expect(transition!.getStyle(), style, reason: style.pdfName);
        expect(await transition.pdfRepresentation().nameEntry(PdfName.type),
            PdfTransition.trans,
            reason: style.pdfName);
      }
    });

    test('the Table 162 example of 12.4.4.1 roundtrips', () async {
      // 10 0 obj << /Type /Page /Dur 5
      //   /Trans << /Type /Trans /D 3.5 /S /Split /Dm /V /M /O >> >>
      final page = await roundtrip((page) async {
        page.setDisplayDuration(5);
        page.setTransition(PdfTransition(PdfPageTransitionStyle.split)
          ..setDuration(3.5)
          ..setDimension(PdfTransitionDimension.vertical)
          ..setMotion(PdfTransitionMotion.outward));
      });

      expect(await page.getDisplayDuration(), 5);
      final transition = (await page.getTransition())!;
      expect(transition.getStyle(), PdfPageTransitionStyle.split);
      expect(await transition.getDuration(), 3.5);
      expect(await transition.getDimension(), PdfTransitionDimension.vertical);
      expect(await transition.getMotion(), PdfTransitionMotion.outward);
    });

    test('absent entries read back as the Table 162 defaults', () async {
      final page = await roundtrip((page) async {
        page.setTransition(PdfTransition(PdfPageTransitionStyle.dissolve));
      });

      final transition = (await page.getTransition())!;
      expect(await transition.getDuration(), 1.0);
      expect(
          await transition.getDimension(), PdfTransitionDimension.horizontal);
      expect(await transition.getMotion(), PdfTransitionMotion.inward);
      expect(await transition.getDirection(), 0);
      expect(await transition.getScale(), 1.0);
      expect(await transition.getOpaque(), isFalse);
      // No /Dur means the page does not advance automatically.
      expect(await page.getDisplayDuration(), isNull);
    });

    test('a transition dictionary without /S reads as the default /R',
        () async {
      final transition = PdfTransition.wrap(
          PdfTransition().pdfRepresentation()..remove(PdfTransition.style));
      expect(transition.getStyle(), PdfPageTransitionStyle.replace);
    });

    test('Fly carries /Di /None, /SS and /B', () async {
      final page = await roundtrip((page) async {
        page.setTransition(PdfTransition(PdfPageTransitionStyle.fly)
          ..setDirectionNone()
          ..setScale(0.25)
          ..setOpaque(true));
      });

      final transition = (await page.getTransition())!;
      expect(await transition.isDirectionNone(), isTrue);
      expect(await transition.getDirection(), isNull);
      expect(await transition.getScale(), 0.25);
      expect(await transition.getOpaque(), isTrue);
    });

    test('Wipe accepts the four Table 162 angles', () async {
      for (final degrees in [0, 90, 180, 270]) {
        final page = await roundtrip((page) async {
          page.setTransition(PdfTransition(PdfPageTransitionStyle.wipe)
            ..setDirection(degrees));
        });
        expect(await (await page.getTransition())!.getDirection(), degrees);
      }
    });

    test('Glitter accepts 315 but Wipe does not', () {
      expect(PdfTransition(PdfPageTransitionStyle.glitter).setDirection(315),
          isNotNull);
      expect(() => PdfTransition(PdfPageTransitionStyle.wipe).setDirection(315),
          throwsA(isA<PdfException>()));
    });

    test('Push rejects the angles reserved for Wipe', () {
      final push = PdfTransition(PdfPageTransitionStyle.push);
      expect(() => push.setDirection(90), throwsA(isA<PdfException>()));
      expect(() => push.setDirection(180), throwsA(isA<PdfException>()));
      expect(push.setDirection(270), isNotNull);
    });

    test('/Dm is rejected outside Split and Blinds', () {
      expect(
          () => PdfTransition(PdfPageTransitionStyle.box)
              .setDimension(PdfTransitionDimension.vertical),
          throwsA(isA<PdfException>()));
      expect(
          PdfTransition(PdfPageTransitionStyle.blinds)
              .setDimension(PdfTransitionDimension.vertical),
          isNotNull);
    });

    test('/M is rejected outside Split, Box and Fly', () {
      expect(
          () => PdfTransition(PdfPageTransitionStyle.blinds)
              .setMotion(PdfTransitionMotion.outward),
          throwsA(isA<PdfException>()));
      expect(
          PdfTransition(PdfPageTransitionStyle.box)
              .setMotion(PdfTransitionMotion.outward),
          isNotNull);
    });

    test('/Di is rejected for styles that have no direction', () {
      expect(
          () => PdfTransition(PdfPageTransitionStyle.dissolve).setDirection(0),
          throwsA(isA<PdfException>()));
      expect(() => PdfTransition(PdfPageTransitionStyle.split).setDirection(0),
          throwsA(isA<PdfException>()));
    });

    test('/Di /None, /SS and /B are rejected outside Fly', () {
      final cover = PdfTransition(PdfPageTransitionStyle.cover);
      expect(cover.setDirectionNone, throwsA(isA<PdfException>()));
      expect(() => cover.setScale(0.5), throwsA(isA<PdfException>()));
      expect(() => cover.setOpaque(true), throwsA(isA<PdfException>()));
    });

    test('negative durations and scales are rejected', () {
      expect(() => PdfTransition().setDuration(-0.5),
          throwsA(isA<PdfException>()));
      expect(() => PdfTransition(PdfPageTransitionStyle.fly).setScale(-1),
          throwsA(isA<PdfException>()));
    });

    test('a negative /Dur is rejected', () async {
      final bytes = BytesBuilder();
      final doc = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final page = await doc.appendBlankPage();
      expect(() => page.setDisplayDuration(-1), throwsA(isA<PdfException>()));
      await doc.close();
    });

    test('changing the style drops the entries it no longer allows', () async {
      final transition = PdfTransition(PdfPageTransitionStyle.split)
        ..setDimension(PdfTransitionDimension.vertical)
        ..setMotion(PdfTransitionMotion.outward);
      expect(
          transition.pdfRepresentation().containsKey(PdfTransition.dimension),
          isTrue);

      transition.setStyle(PdfPageTransitionStyle.wipe);
      expect(
          transition.pdfRepresentation().containsKey(PdfTransition.dimension),
          isFalse);
      expect(transition.pdfRepresentation().containsKey(PdfTransition.motion),
          isFalse);
      expect(transition.setDirection(180), isNotNull);
    });

    test('removeTransition drops /Trans', () async {
      final page = await roundtrip((page) async {
        page.setTransition(PdfTransition(PdfPageTransitionStyle.fade));
        page.removeTransition();
      });

      expect(await page.getTransition(), isNull);
    });
  });
}
