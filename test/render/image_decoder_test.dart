import 'dart:typed_data';

import 'package:dpdf/src/io/image/jpeg_encoder.dart';
import 'package:dpdf/src/io/image/jpeg_decoder.dart' show JpegPixelFormat;
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_boolean.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'package:dpdf/src/render/image_decoder.dart';
import 'package:test/test.dart';

CraftPdfStream _image({
  required int width,
  required int height,
  required Uint8List data,
  required Object colorSpace,
  int bits = 8,
  CraftPdfArray? decode,
  bool imageMask = false,
  CraftPdfName? filter,
}) {
  final stream = CraftPdfStream.withBytes(data, 0)
    ..put(CraftPdfName.subtype, CraftPdfName('Image'))
    ..put(CraftPdfName.width, CraftPdfNumber.fromInt(width))
    ..put(CraftPdfName.height, CraftPdfNumber.fromInt(height));
  if (imageMask) {
    stream.put(CraftPdfName('ImageMask'), CraftPdfBoolean(true));
  } else {
    stream
      ..put(CraftPdfName('BitsPerComponent'), CraftPdfNumber.fromInt(bits))
      ..put(
          CraftPdfName('ColorSpace'),
          colorSpace is String
              ? CraftPdfName(colorSpace)
              : colorSpace as CraftPdfArray);
  }
  if (decode != null) stream.put(CraftPdfName('Decode'), decode);
  if (filter != null) stream.put(CraftPdfName.filter, filter);
  return stream;
}

/// The RGBA quadruple at (x, y).
List<int> _at(PdfDecodedImage image, int x, int y) {
  final i = (y * image.width + x) * 4;
  return image.rgba!.sublist(i, i + 4);
}

void main() {
  group('PdfImageDecoder', () {
    test('expands 8-bit DeviceRGB straight through', () async {
      final data = Uint8List.fromList([
        255, 0, 0, 0, 255, 0, //
        0, 0, 255, 255, 255, 255,
      ]);

      final image = (await PdfImageDecoder.decode(_image(
        width: 2,
        height: 2,
        data: data,
        colorSpace: 'DeviceRGB',
      )))!;

      expect(image.width, equals(2));
      expect(_at(image, 0, 0), equals([255, 0, 0, 255]));
      expect(_at(image, 1, 0), equals([0, 255, 0, 255]));
      expect(_at(image, 0, 1), equals([0, 0, 255, 255]));
      expect(_at(image, 1, 1), equals([255, 255, 255, 255]));
    });

    test('expands 8-bit DeviceGray to grey RGBA', () async {
      final data = Uint8List.fromList([0, 128, 255, 64]);

      final image = (await PdfImageDecoder.decode(_image(
        width: 2,
        height: 2,
        data: data,
        colorSpace: 'DeviceGray',
      )))!;

      expect(_at(image, 0, 0), equals([0, 0, 0, 255]));
      expect(_at(image, 1, 0), equals([128, 128, 128, 255]));
      expect(_at(image, 0, 1), equals([255, 255, 255, 255]));
    });

    test('unpacks 1, 2 and 4 bits per component, rows byte-aligned', () async {
      // 1 bit, 4 pixels wide: 1010 in the top nibble, rest padding.
      final oneBit = (await PdfImageDecoder.decode(_image(
        width: 4,
        height: 1,
        bits: 1,
        data: Uint8List.fromList([0xA0]),
        colorSpace: 'DeviceGray',
      )))!;
      expect(_at(oneBit, 0, 0)[0], equals(255));
      expect(_at(oneBit, 1, 0)[0], equals(0));
      expect(_at(oneBit, 2, 0)[0], equals(255));
      expect(_at(oneBit, 3, 0)[0], equals(0));

      // 4 bits: 0x0F -> 0 then 15, which maps to 0 and 255.
      final fourBit = (await PdfImageDecoder.decode(_image(
        width: 2,
        height: 1,
        bits: 4,
        data: Uint8List.fromList([0x0F]),
        colorSpace: 'DeviceGray',
      )))!;
      expect(_at(fourBit, 0, 0)[0], equals(0));
      expect(_at(fourBit, 1, 0)[0], equals(255));

      // Two rows of 2-bit samples, each row padded to a whole byte.
      final twoBit = (await PdfImageDecoder.decode(_image(
        width: 2,
        height: 2,
        bits: 2,
        data: Uint8List.fromList([0x30, 0xC0]), // 00 11 | 11 00
        colorSpace: 'DeviceGray',
      )))!;
      expect(_at(twoBit, 0, 0)[0], equals(0));
      expect(_at(twoBit, 1, 0)[0], equals(255));
      expect(_at(twoBit, 0, 1)[0], equals(255));
      expect(_at(twoBit, 1, 1)[0], equals(0));
    });

    test('applies an inverting /Decode array', () async {
      final image = (await PdfImageDecoder.decode(_image(
        width: 2,
        height: 1,
        data: Uint8List.fromList([0, 255]),
        colorSpace: 'DeviceGray',
        decode: CraftPdfArray.fromDoubles([1, 0]),
      )))!;

      expect(_at(image, 0, 0)[0], equals(255));
      expect(_at(image, 1, 0)[0], equals(0));
    });

    test('resolves an Indexed palette', () async {
      final palette = CraftPdfArray()
        ..add(CraftPdfName('Indexed'))
        ..add(CraftPdfName('DeviceRGB'))
        ..add(CraftPdfNumber.fromInt(2))
        ..add(CraftPdfString.fromBytes(Uint8List.fromList([
          255, 0, 0, //
          0, 255, 0,
          0, 0, 255,
        ])));

      final image = (await PdfImageDecoder.decode(_image(
        width: 3,
        height: 1,
        data: Uint8List.fromList([0, 1, 2]),
        colorSpace: palette,
      )))!;

      expect(_at(image, 0, 0), equals([255, 0, 0, 255]));
      expect(_at(image, 1, 0), equals([0, 255, 0, 255]));
      expect(_at(image, 2, 0), equals([0, 0, 255, 255]));
    });

    test('converts DeviceCMYK', () async {
      // Cyan=0 Magenta=1 Yellow=1 Black=0 is pure red.
      final image = (await PdfImageDecoder.decode(_image(
        width: 1,
        height: 1,
        data: Uint8List.fromList([0, 255, 255, 0]),
        colorSpace: 'DeviceCMYK',
      )))!;

      expect(_at(image, 0, 0), equals([255, 0, 0, 255]));
    });

    test('reads a stencil mask, and honours /Decode [1 0]', () async {
      final normal = (await PdfImageDecoder.decode(_image(
        width: 4,
        height: 1,
        data: Uint8List.fromList([0xA0]), // 1010
        colorSpace: 'DeviceGray',
        imageMask: true,
      )))!;

      expect(normal.isStencil, isTrue);
      expect(normal.rgba, isNull);
      // A 0 bit paints by default.
      expect(normal.stencil!.sublist(0, 4), equals([0, 255, 0, 255]));

      final inverted = (await PdfImageDecoder.decode(_image(
        width: 4,
        height: 1,
        data: Uint8List.fromList([0xA0]),
        colorSpace: 'DeviceGray',
        imageMask: true,
        decode: CraftPdfArray.fromDoubles([1, 0]),
      )))!;
      expect(inverted.stencil!.sublist(0, 4), equals([255, 0, 255, 0]));
    });

    test('folds an /SMask into the alpha channel', () async {
      final base = _image(
        width: 2,
        height: 1,
        data: Uint8List.fromList([255, 0, 0, 0, 255, 0]),
        colorSpace: 'DeviceRGB',
      );
      final soft = _image(
        width: 2,
        height: 1,
        data: Uint8List.fromList([0, 255]),
        colorSpace: 'DeviceGray',
      );
      base.put(CraftPdfName('SMask'), soft);

      final image = (await PdfImageDecoder.decode(base))!;

      expect(_at(image, 0, 0), equals([255, 0, 0, 0]));
      expect(_at(image, 1, 0), equals([0, 255, 0, 255]));
    });

    test('scales an /SMask that has its own resolution', () async {
      final base = _image(
        width: 4,
        height: 1,
        data: Uint8List.fromList(List.filled(12, 200)),
        colorSpace: 'DeviceRGB',
      );
      base.put(
          CraftPdfName('SMask'),
          _image(
            width: 2,
            height: 1,
            data: Uint8List.fromList([0, 255]),
            colorSpace: 'DeviceGray',
          ));

      final image = (await PdfImageDecoder.decode(base))!;

      expect(_at(image, 0, 0)[3], equals(0));
      expect(_at(image, 1, 0)[3], equals(0));
      expect(_at(image, 2, 0)[3], equals(255));
      expect(_at(image, 3, 0)[3], equals(255));
    });

    test('decodes a DCTDecode image through the JPEG decoder', () async {
      const width = 16, height = 16;
      final samples = Uint8List(width * height * 3);
      for (var i = 0; i < samples.length; i += 3) {
        samples[i] = 200;
        samples[i + 1] = 100;
        samples[i + 2] = 50;
      }
      final jpeg = JpegEncoder.encode(samples,
          width: width,
          height: height,
          quality: 100,
          subsampling: JpegSubsampling.none);

      final image = (await PdfImageDecoder.decode(_image(
        width: width,
        height: height,
        data: jpeg,
        colorSpace: 'DeviceRGB',
        filter: CraftPdfName('DCTDecode'),
      )))!;

      expect(image.width, equals(width));
      final pixel = _at(image, 8, 8);
      expect(pixel[0], closeTo(200, 3));
      expect(pixel[1], closeTo(100, 3));
      expect(pixel[2], closeTo(50, 3));
      expect(pixel[3], equals(255));
    });

    test('decodes a grayscale JPEG', () async {
      const width = 16, height = 16;
      final samples = Uint8List(width * height)..fillRange(0, 256, 140);
      final jpeg = JpegEncoder.encode(samples,
          width: width,
          height: height,
          format: JpegPixelFormat.grayscale,
          quality: 100);

      final image = (await PdfImageDecoder.decode(_image(
        width: width,
        height: height,
        data: jpeg,
        colorSpace: 'DeviceGray',
        filter: CraftPdfName('DCTDecode'),
      )))!;

      final pixel = _at(image, 8, 8);
      expect(pixel[0], closeTo(140, 3));
      expect(pixel[0], equals(pixel[1]));
      expect(pixel[1], equals(pixel[2]));
    });

    test('returns null rather than throwing on an unusable image', () async {
      expect(
          await PdfImageDecoder.decode(_image(
            width: 0,
            height: 4,
            data: Uint8List(4),
            colorSpace: 'DeviceGray',
          )),
          isNull);

      // Not enough samples for the declared geometry.
      expect(
          await PdfImageDecoder.decode(_image(
            width: 100,
            height: 100,
            data: Uint8List(4),
            colorSpace: 'DeviceGray',
          )),
          isNull);

      // A bit depth the format does not define.
      expect(
          await PdfImageDecoder.decode(_image(
            width: 2,
            height: 2,
            bits: 3,
            data: Uint8List(4),
            colorSpace: 'DeviceGray',
          )),
          isNull);
    });
  });

  group('inlineImageToStream', () {
    test('expands the abbreviated keys and values', () async {
      final dictionary = CraftPdfDictionary()
        ..put(CraftPdfName('W'), CraftPdfNumber.fromInt(2))
        ..put(CraftPdfName('H'), CraftPdfNumber.fromInt(1))
        ..put(CraftPdfName('BPC'), CraftPdfNumber.fromInt(8))
        ..put(CraftPdfName('CS'), CraftPdfName('RGB'));

      final stream = inlineImageToStream(
          dictionary, Uint8List.fromList([255, 0, 0, 0, 0, 255]));

      expect(await stream.integerEntry(CraftPdfName.width), equals(2));
      expect(await stream.integerEntry(CraftPdfName.height), equals(1));
      expect((await stream.nameEntry(CraftPdfName('ColorSpace')))?.getValue(),
          equals('DeviceRGB'));
      expect((await stream.nameEntry(CraftPdfName.subtype))?.getValue(),
          equals('Image'));

      final image = (await PdfImageDecoder.decode(stream))!;
      expect(_at(image, 0, 0), equals([255, 0, 0, 255]));
      expect(_at(image, 1, 0), equals([0, 0, 255, 255]));
    });

    test('expands abbreviated filter names', () async {
      final dictionary = CraftPdfDictionary()
        ..put(CraftPdfName('W'), CraftPdfNumber.fromInt(1))
        ..put(CraftPdfName('H'), CraftPdfNumber.fromInt(1))
        ..put(CraftPdfName('F'), CraftPdfName('Fl'));

      final stream = inlineImageToStream(dictionary, Uint8List(0));

      expect((await stream.nameEntry(CraftPdfName.filter))?.getValue(),
          equals('FlateDecode'));
    });
  });
}
