import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/src/kernel/colors/device_cmyk.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_cie_based_cs.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_color_space.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_device_cs.dart';
import 'package:dpdf/src/kernel/pdf/colorspace/pdf_special_cs.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'package:test/test.dart';

CraftPdfName _n(String value) => CraftPdfName.intern(value);

/// Asserts that [actual] matches [expected] channel by channel.
void expectRgb(List<double> actual, List<double> expected,
    {double tolerance = 1e-9}) {
  expect(actual, hasLength(3));
  for (var i = 0; i < 3; i++) {
    expect(actual[i], closeTo(expected[i], tolerance),
        reason: 'channel $i of $actual should be $expected');
  }
}

/// A type 2 tint transform ramping from [c0] to [c1].
CraftPdfDictionary _tint(List<double> c0, List<double> c1,
    {List<double> domain = const [0.0, 1.0]}) {
  final dict = CraftPdfDictionary();
  dict.put(_n('FunctionType'), CraftPdfNumber.fromInt(2));
  dict.put(_n('Domain'), CraftPdfArray.fromDoubles(domain));
  dict.put(_n('C0'), CraftPdfArray.fromDoubles(c0));
  dict.put(_n('C1'), CraftPdfArray.fromDoubles(c1));
  dict.put(_n('N'), CraftPdfNumber(1.0));
  return dict;
}

/// A type 4 tint transform running [program].
CraftPdfStream _postScriptTint(
    String program, List<double> domain, List<double> range) {
  final stream =
      CraftPdfStream.withBytes(Uint8List.fromList(latin1.encode(program)));
  stream.put(_n('FunctionType'), CraftPdfNumber.fromInt(4));
  stream.put(_n('Domain'), CraftPdfArray.fromDoubles(domain));
  stream.put(_n('Range'), CraftPdfArray.fromDoubles(range));
  return stream;
}

Future<CraftPdfColorSpace> _make(CraftPdfObject definition) async {
  final space = await CraftPdfColorSpace.makeColorSpace(definition);
  expect(space, isNotNull, reason: 'the colour space should have resolved');
  return space!;
}

void main() {
  group('device spaces', () {
    test('DeviceGray repeats the grey on all three channels', () {
      expectRgb(PdfDeviceCsGray().toRgb([0.25]), [0.25, 0.25, 0.25]);
      expectRgb(PdfDeviceCsGray().toRgb([1.0]), [1.0, 1.0, 1.0]);
    });

    test('DeviceRGB passes its components through', () {
      expectRgb(PdfDeviceCsRgb().toRgb([0.1, 0.2, 0.3]), [0.1, 0.2, 0.3]);
    });

    test('out of range components are clamped', () {
      expectRgb(PdfDeviceCsRgb().toRgb([-1.0, 2.0, 0.5]), [0.0, 1.0, 0.5]);
      expectRgb(PdfDeviceCsGray().toRgb([]), [0.0, 0.0, 0.0]);
    });

    test('DeviceCMYK uses the naive conversion', () {
      expectRgb(PdfDeviceCsCmyk().toRgb([0.0, 0.0, 0.0, 0.0]), [1.0, 1.0, 1.0]);
      expectRgb(PdfDeviceCsCmyk().toRgb([0.0, 0.0, 0.0, 1.0]), [0.0, 0.0, 0.0]);
      expectRgb(PdfDeviceCsCmyk().toRgb([1.0, 0.0, 0.0, 0.0]), [0.0, 1.0, 1.0]);
      // (1 - 0.5) * (1 - 0.2) on the cyan channel.
      expectRgb(PdfDeviceCsCmyk().toRgb([0.5, 0.0, 0.0, 0.2]), [0.4, 0.8, 0.8]);
    });

    test('the colour space and CraftDeviceCmyk agree', () {
      // CraftDeviceCmyk.makeLighter goes through the same private conversion,
      // so a colour that is already white must stay white.
      final white = CraftDeviceCmyk(0.0, 0.0, 0.0, 0.0);
      expectRgb(
          PdfDeviceCsCmyk().toRgb(white.getColorValue()), [1.0, 1.0, 1.0]);
      expect(CraftDeviceCmyk.makeLighter(white).getColorValue(),
          white.getColorValue());
    });

    test('makeColorSpace resolves the device families', () async {
      expect(await _make(CraftPdfName.deviceGray), isA<PdfDeviceCsGray>());
      expect(await _make(CraftPdfName.deviceRgb), isA<PdfDeviceCsRgb>());
      expect(await _make(CraftPdfName.deviceCmyk), isA<PdfDeviceCsCmyk>());
    });
  });

  group('CIE based spaces', () {
    test('CalGray and CalRGB behave like their device counterparts', () async {
      final calGray = await _make(CraftPdfArray.fromList([
        CraftPdfName.calGray,
        CraftPdfDictionary(),
      ]));
      expect(calGray.getNumberOfComponents(), 1);
      expectRgb(calGray.toRgb([0.4]), [0.4, 0.4, 0.4]);

      final calRgb = await _make(CraftPdfArray.fromList([
        CraftPdfName.calRgb,
        CraftPdfDictionary(),
      ]));
      expect(calRgb.getNumberOfComponents(), 3);
      expectRgb(calRgb.toRgb([0.1, 0.2, 0.3]), [0.1, 0.2, 0.3]);
    });

    test('ICCBased follows its /N', () async {
      Future<CraftPdfColorSpace> iccBased(int n) async {
        final profile = CraftPdfStream.withBytes(Uint8List.fromList([0]));
        profile.put(CraftPdfName.n, CraftPdfNumber.fromInt(n));
        return _make(CraftPdfArray.fromList([CraftPdfName.iccBased, profile]));
      }

      final gray = await iccBased(1);
      expect(gray.getNumberOfComponents(), 1);
      expectRgb(gray.toRgb([0.5]), [0.5, 0.5, 0.5]);

      final rgb = await iccBased(3);
      expect(rgb.getNumberOfComponents(), 3);
      expectRgb(rgb.toRgb([0.1, 0.2, 0.3]), [0.1, 0.2, 0.3]);

      final cmyk = await iccBased(4);
      expect(cmyk.getNumberOfComponents(), 4);
      expectRgb(cmyk.toRgb([0.0, 0.0, 0.0, 0.5]), [0.5, 0.5, 0.5]);
    });

    test('ICCBased without /N is assumed to be RGB', () async {
      final space = await _make(CraftPdfArray.fromList([
        CraftPdfName.iccBased,
        CraftPdfStream.withBytes(Uint8List.fromList([0])),
      ]));
      expect(space.getNumberOfComponents(), 3);
    });

    group('Lab', () {
      Future<CraftPdfColorSpace> labSpace(
          {List<double>? whitePoint, List<double>? range}) async {
        final dict = CraftPdfDictionary();
        if (whitePoint != null) {
          dict.put(_n('WhitePoint'), CraftPdfArray.fromDoubles(whitePoint));
        }
        if (range != null) {
          dict.put(_n('Range'), CraftPdfArray.fromDoubles(range));
        }
        return _make(CraftPdfArray.fromList([CraftPdfName.lab, dict]));
      }

      test('L* = 100 with no chroma is white', () async {
        final lab = await labSpace();
        expectRgb(lab.toRgb([100.0, 0.0, 0.0]), [1.0, 1.0, 1.0],
            tolerance: 1e-4);
      });

      test('L* = 0 is black', () async {
        final lab = await labSpace();
        expectRgb(lab.toRgb([0.0, 0.0, 0.0]), [0.0, 0.0, 0.0], tolerance: 1e-9);
      });

      test('L* = 53.585 with no chroma is mid grey', () async {
        // L* is perceptual, so half the lightness sits at sRGB 0.5, not at
        // L* = 50.
        final lab = await labSpace();
        expectRgb(lab.toRgb([53.5850, 0.0, 0.0]), [0.502, 0.502, 0.502],
            tolerance: 2e-3);
      });

      test('the D50 Lab coordinates of sRGB primaries come back', () async {
        final lab = await labSpace();
        expectRgb(lab.toRgb([54.29, 80.81, 69.89]), [1.0, 0.0, 0.0],
            tolerance: 1e-3);
        expectRgb(lab.toRgb([87.82, -79.29, 80.99]), [0.0, 1.0, 0.0],
            tolerance: 1e-3);
      });

      test('an explicit D65 white point is honoured', () async {
        final lab = await labSpace(whitePoint: PdfCieBasedCsLab.d65WhitePoint);
        expectRgb(lab.toRgb([100.0, 0.0, 0.0]), [1.0, 1.0, 1.0],
            tolerance: 1e-4);
        expectRgb(lab.toRgb([53.24, 80.09, 67.20]), [1.0, 0.0, 0.0],
            tolerance: 1e-3);
      });

      test('components report the Lab ranges and are clamped to them',
          () async {
        final lab = await labSpace(range: [-50.0, 50.0, -60.0, 60.0]);
        expect(lab.getComponentRange(0), [0.0, 100.0]);
        expect(lab.getComponentRange(1), [-50.0, 50.0]);
        expect(lab.getComponentRange(2), [-60.0, 60.0]);
        // a* = 200 is outside /Range and must behave as a* = 50.
        expectRgb(lab.toRgb([54.0, 200.0, 0.0]), lab.toRgb([54.0, 50.0, 0.0]));
      });

      test('defaults to a D50 white point and the full range', () {
        final lab =
            PdfCieBasedCsLab(CraftPdfArray.fromList([CraftPdfName.lab]));
        expect(lab.range, PdfCieBasedCsLab.defaultRange);
        expect(lab.whitePoint[1], 1.0);
      });
    });
  });

  group('Indexed', () {
    /// `[/Indexed /DeviceRGB 2 <palette>]` with red, green and blue entries.
    Future<CraftPdfColorSpace> palette({bool asStream = false}) async {
      final bytes = <int>[255, 0, 0, 0, 255, 0, 0, 0, 255];
      final lookup = asStream
          ? CraftPdfStream.withBytes(Uint8List.fromList(bytes))
          : CraftPdfString.fromBytes(Uint8List.fromList(bytes));
      return _make(CraftPdfArray.fromList([
        CraftPdfName.indexed,
        CraftPdfName.deviceRgb,
        CraftPdfNumber.fromInt(2),
        lookup,
      ]));
    }

    test('looks the index up and delegates to the base space', () async {
      final indexed = await palette();
      expect(indexed, isA<PdfSpecialCsIndexed>());
      expect(indexed.getNumberOfComponents(), 1);
      expectRgb(indexed.toRgb([0.0]), [1.0, 0.0, 0.0]);
      expectRgb(indexed.toRgb([1.0]), [0.0, 1.0, 0.0]);
      expectRgb(indexed.toRgb([2.0]), [0.0, 0.0, 1.0]);
    });

    test('accepts a stream lookup table', () async {
      final indexed = await palette(asStream: true);
      expectRgb(indexed.toRgb([1.0]), [0.0, 1.0, 0.0]);
    });

    test('reports 0..hival as its component range', () async {
      final indexed = await palette();
      expect(indexed.getComponentRange(0), [0.0, 2.0]);
    });

    test('indices are rounded and clamped to 0..hival', () async {
      final indexed = await palette();
      expectRgb(indexed.toRgb([-3.0]), [1.0, 0.0, 0.0]);
      expectRgb(indexed.toRgb([99.0]), [0.0, 0.0, 1.0]);
      expectRgb(indexed.toRgb([1.4]), [0.0, 1.0, 0.0]);
    });

    test('palette bytes are spread over the base component ranges', () async {
      // With a Lab base, byte 255 in the first component means L* = 100 and
      // byte 128 in the others is the middle of /Range, i.e. a* = b* = 0.
      final labDict = CraftPdfDictionary();
      labDict.put(_n('Range'),
          CraftPdfArray.fromDoubles([-128.0, 128.0, -128.0, 128.0]));
      final indexed = await _make(CraftPdfArray.fromList([
        CraftPdfName.indexed,
        CraftPdfArray.fromList([CraftPdfName.lab, labDict]),
        CraftPdfNumber.fromInt(0),
        CraftPdfString.fromBytes(Uint8List.fromList([255, 128, 128])),
      ]));
      expectRgb(indexed.toRgb([0.0]), [1.0, 1.0, 1.0], tolerance: 5e-3);
    });

    test('a palette shorter than hival reads as zero', () async {
      final indexed = await _make(CraftPdfArray.fromList([
        CraftPdfName.indexed,
        CraftPdfName.deviceRgb,
        CraftPdfNumber.fromInt(3),
        CraftPdfString.fromBytes(Uint8List.fromList([255, 255, 255])),
      ]));
      expectRgb(indexed.toRgb([2.0]), [0.0, 0.0, 0.0]);
    });

    test('is rejected when the palette is missing', () async {
      expect(
          await CraftPdfColorSpace.makeColorSpace(CraftPdfArray.fromList([
            CraftPdfName.indexed,
            CraftPdfName.deviceRgb,
            CraftPdfNumber.fromInt(1),
          ])),
          isNull);
    });
  });

  group('Separation', () {
    test('runs the tint transform and delegates to the alternate', () async {
      // White at tint 0, pure red at tint 1.
      final separation = await _make(CraftPdfArray.fromList([
        CraftPdfName.separation,
        _n('PANTONE#20Red'),
        CraftPdfName.deviceRgb,
        _tint([1.0, 1.0, 1.0], [1.0, 0.0, 0.0]),
      ]));
      expect(separation, isA<PdfSpecialCsSeparation>());
      expect(separation.getNumberOfComponents(), 1);
      expectRgb(separation.toRgb([0.0]), [1.0, 1.0, 1.0]);
      expectRgb(separation.toRgb([1.0]), [1.0, 0.0, 0.0]);
      expectRgb(separation.toRgb([0.5]), [1.0, 0.5, 0.5]);
    });

    test('works with a CMYK alternate', () async {
      final separation = await _make(CraftPdfArray.fromList([
        CraftPdfName.separation,
        _n('Black'),
        CraftPdfName.deviceCmyk,
        _tint([0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 1.0]),
      ]));
      expectRgb(separation.toRgb([1.0]), [0.0, 0.0, 0.0]);
      expectRgb(separation.toRgb([0.5]), [0.5, 0.5, 0.5]);
    });

    test('/None paints nothing and reads as white', () async {
      final separation = await _make(CraftPdfArray.fromList([
        CraftPdfName.separation,
        CraftPdfName.none,
        CraftPdfName.deviceRgb,
        _tint([1.0, 1.0, 1.0], [0.0, 0.0, 0.0]),
      ]));
      expectRgb(separation.toRgb([1.0]), [1.0, 1.0, 1.0]);
    });

    test('is rejected without a usable tint transform', () async {
      expect(
          await CraftPdfColorSpace.makeColorSpace(CraftPdfArray.fromList([
            CraftPdfName.separation,
            _n('Spot'),
            CraftPdfName.deviceRgb,
            CraftPdfDictionary(),
          ])),
          isNull);
    });
  });

  group('DeviceN', () {
    test('runs the tint transform over every colourant', () async {
      // { pop dup dup } keeps the first tint and paints it as grey.
      final deviceN = await _make(CraftPdfArray.fromList([
        CraftPdfName.deviceN,
        CraftPdfArray.fromList([_n('Cyan'), _n('Magenta')]),
        CraftPdfName.deviceRgb,
        _postScriptTint('{ pop dup dup }', [0.0, 1.0, 0.0, 1.0],
            [0.0, 1.0, 0.0, 1.0, 0.0, 1.0]),
      ]));
      expect(deviceN, isA<PdfSpecialCsDeviceN>());
      expect(deviceN.getNumberOfComponents(), 2);
      expectRgb(deviceN.toRgb([0.25, 0.9]), [0.25, 0.25, 0.25]);
    });

    test('accepts an array of one in one out tint transforms', () async {
      // Three 1-in-1-out functions stand in for one 1-in-3-out function; with
      // a single colourant this is the shading shorthand applied to DeviceN.
      final deviceN = await _make(CraftPdfArray.fromList([
        CraftPdfName.deviceN,
        CraftPdfArray.fromList([_n('Spot')]),
        CraftPdfName.deviceRgb,
        CraftPdfArray.fromList([
          _tint([1.0], [0.0]),
          _tint([1.0], [0.5]),
          _tint([1.0], [1.0]),
        ]),
      ]));
      expectRgb(deviceN.toRgb([1.0]), [0.0, 0.5, 1.0]);
    });

    test('is rejected without colourant names', () async {
      expect(
          await CraftPdfColorSpace.makeColorSpace(CraftPdfArray.fromList([
            CraftPdfName.deviceN,
            CraftPdfArray(),
            CraftPdfName.deviceRgb,
            _tint([1.0, 1.0, 1.0], [0.0, 0.0, 0.0]),
          ])),
          isNull);
    });
  });

  group('Pattern', () {
    test('has no colour of its own', () {
      final pattern = PdfSpecialCsPattern();
      // -1 is the documented "unknown" answer for the family.
      expect(pattern.getNumberOfComponents(), -1);
      expect(() => pattern.toRgb([0.5]), throwsUnsupportedError);
    });

    test('the array form keeps its underlying space', () async {
      final pattern = await _make(CraftPdfArray.fromList([
        CraftPdfName.pattern,
        CraftPdfName.deviceRgb,
      ]));
      expect(pattern, isA<PdfSpecialCsPattern>());
      expect((pattern as PdfSpecialCsPattern).underlyingColorSpace,
          isA<PdfDeviceCsRgb>());
      expect(() => pattern.toRgb([0.5]), throwsUnsupportedError);
    });
  });

  group('nesting', () {
    test('Indexed over Separation over DeviceCMYK', () async {
      final separation = CraftPdfArray.fromList([
        CraftPdfName.separation,
        _n('Spot'),
        CraftPdfName.deviceCmyk,
        _tint([0.0, 0.0, 0.0, 0.0], [0.0, 0.0, 0.0, 1.0]),
      ]);
      final indexed = await _make(CraftPdfArray.fromList([
        CraftPdfName.indexed,
        separation,
        CraftPdfNumber.fromInt(1),
        // One component per entry: no ink, then full ink.
        CraftPdfString.fromBytes(Uint8List.fromList([0, 255])),
      ]));
      expect(indexed.getNumberOfComponents(), 1);
      expectRgb(indexed.toRgb([0.0]), [1.0, 1.0, 1.0]);
      expectRgb(indexed.toRgb([1.0]), [0.0, 0.0, 0.0]);
    });
  });
}
