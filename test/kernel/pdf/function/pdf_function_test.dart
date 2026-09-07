import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/src/kernel/pdf/function/pdf_function.dart';
import 'package:dpdf/src/kernel/pdf/function/pdf_function_exponential.dart';
import 'package:dpdf/src/kernel/pdf/function/pdf_function_postscript.dart';
import 'package:dpdf/src/kernel/pdf/function/pdf_function_sampled.dart';
import 'package:dpdf/src/kernel/pdf/function/pdf_function_stitching.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:test/test.dart';

CraftPdfName _n(String value) => CraftPdfName.intern(value);

/// Builds a type 2 (exponential) function dictionary.
CraftPdfDictionary _exponential(
    {List<double> domain = const [0.0, 1.0],
    List<double> c0 = const [0.0],
    List<double> c1 = const [1.0],
    double exponent = 1.0,
    List<double>? range}) {
  final dict = CraftPdfDictionary();
  dict.put(_n('FunctionType'), CraftPdfNumber.fromInt(2));
  dict.put(_n('Domain'), CraftPdfArray.fromDoubles(domain));
  dict.put(_n('C0'), CraftPdfArray.fromDoubles(c0));
  dict.put(_n('C1'), CraftPdfArray.fromDoubles(c1));
  dict.put(_n('N'), CraftPdfNumber(exponent));
  if (range != null) {
    dict.put(_n('Range'), CraftPdfArray.fromDoubles(range));
  }
  return dict;
}

/// Builds a type 0 (sampled) function stream over raw sample bytes.
CraftPdfStream _sampled(
    {required List<int> size,
    required int bitsPerSample,
    required List<int> bytes,
    List<double> domain = const [0.0, 1.0],
    List<double> range = const [0.0, 1.0],
    List<double>? encode,
    List<double>? decode,
    int? order}) {
  final stream = CraftPdfStream.withBytes(Uint8List.fromList(bytes));
  stream.put(_n('FunctionType'), CraftPdfNumber.fromInt(0));
  stream.put(_n('Domain'), CraftPdfArray.fromDoubles(domain));
  stream.put(_n('Range'), CraftPdfArray.fromDoubles(range));
  stream.put(_n('Size'), CraftPdfArray.fromInts(size));
  stream.put(_n('BitsPerSample'), CraftPdfNumber.fromInt(bitsPerSample));
  if (encode != null) {
    stream.put(_n('Encode'), CraftPdfArray.fromDoubles(encode));
  }
  if (decode != null) {
    stream.put(_n('Decode'), CraftPdfArray.fromDoubles(decode));
  }
  if (order != null) {
    stream.put(_n('Order'), CraftPdfNumber.fromInt(order));
  }
  return stream;
}

/// Builds a type 4 (PostScript calculator) function stream.
CraftPdfStream _postScript(String program,
    {List<double> domain = const [0.0, 1.0],
    List<double> range = const [0.0, 1.0]}) {
  final stream =
      CraftPdfStream.withBytes(Uint8List.fromList(latin1.encode(program)));
  stream.put(_n('FunctionType'), CraftPdfNumber.fromInt(4));
  stream.put(_n('Domain'), CraftPdfArray.fromDoubles(domain));
  stream.put(_n('Range'), CraftPdfArray.fromDoubles(range));
  return stream;
}

Future<CraftPdfFunction> _parse(CraftPdfObject object) async {
  final function = await CraftPdfFunction.parse(object);
  expect(function, isNotNull, reason: 'the function should have parsed');
  return function!;
}

/// Evaluates a type 4 program on a single input and returns a single output.
Future<double> _runProgram(String program, double input,
    {List<double> range = const [-1000.0, 1000.0]}) async {
  final function = await _parse(
      _postScript(program, domain: [-1000.0, 1000.0], range: range));
  return function.evaluate([input])[0];
}

void main() {
  group('type 2 exponential', () {
    test('linear ramp reads its own domain position', () async {
      final function = await _parse(_exponential());
      expect(function.inputCount, 1);
      expect(function.outputCount, 1);
      expect(function.evaluate([0.0])[0], closeTo(0.0, 1e-12));
      expect(function.evaluate([0.25])[0], closeTo(0.25, 1e-12));
      expect(function.evaluate([1.0])[0], closeTo(1.0, 1e-12));
    });

    test('exponent and multiple outputs', () async {
      final function = await _parse(_exponential(
          c0: [0.0, 1.0, 0.5], c1: [1.0, 0.0, 0.5], exponent: 2.0));
      expect(function.outputCount, 3);
      // x^2 at 0.5 is 0.25, so each output is a quarter of the way from C0
      // towards C1.
      final result = function.evaluate([0.5]);
      expect(result[0], closeTo(0.25, 1e-12));
      expect(result[1], closeTo(0.75, 1e-12));
      expect(result[2], closeTo(0.5, 1e-12));
    });

    test('defaults to the 0..1 ramp when C0 and C1 are absent', () async {
      final dict = CraftPdfDictionary();
      dict.put(_n('FunctionType'), CraftPdfNumber.fromInt(2));
      dict.put(_n('Domain'), CraftPdfArray.fromDoubles([0.0, 1.0]));
      dict.put(_n('N'), CraftPdfNumber(1.0));
      final function = await _parse(dict);
      expect(function.evaluate([0.75])[0], closeTo(0.75, 1e-12));
    });

    test('clips the input to the domain', () async {
      final function = await _parse(_exponential(domain: [0.2, 0.8]));
      // Below the domain the function must behave as if x were 0.2.
      expect(function.evaluate([-5.0])[0], closeTo(0.2, 1e-12));
      expect(function.evaluate([5.0])[0], closeTo(0.8, 1e-12));
    });

    test('clips the output to the range', () async {
      final function =
          await _parse(_exponential(c1: [10.0], range: [0.0, 1.0]));
      expect(function.evaluate([1.0])[0], closeTo(1.0, 1e-12));
      expect(function.evaluate([0.05])[0], closeTo(0.5, 1e-12));
    });

    test('is rejected without /N', () async {
      final dict = CraftPdfDictionary();
      dict.put(_n('FunctionType'), CraftPdfNumber.fromInt(2));
      dict.put(_n('Domain'), CraftPdfArray.fromDoubles([0.0, 1.0]));
      expect(await CraftPdfFunction.parse(dict), isNull);
    });
  });

  group('type 0 sampled', () {
    test('interpolates a two sample ramp', () async {
      final function = await _parse(
          _sampled(size: [2], bitsPerSample: 8, bytes: [0x00, 0xFF]));
      expect(function, isA<CraftPdfFunctionSampled>());
      expect(function.evaluate([0.0])[0], closeTo(0.0, 1e-12));
      expect(function.evaluate([0.5])[0], closeTo(0.5, 1e-12));
      expect(function.evaluate([1.0])[0], closeTo(1.0, 1e-12));
      expect(function.evaluate([0.25])[0], closeTo(0.25, 1e-12));
    });

    test('interpolates between three samples', () async {
      // 0, 128, 255 over 0..1: the midpoint of the first cell is 64/255.
      final function = await _parse(
          _sampled(size: [3], bitsPerSample: 8, bytes: [0x00, 0x80, 0xFF]));
      expect(function.evaluate([0.5])[0], closeTo(128.0 / 255.0, 1e-12));
      expect(function.evaluate([0.25])[0], closeTo(64.0 / 255.0, 1e-12));
    });

    test('handles 1, 4, 12 and 16 bits per sample', () async {
      final oneBit =
          await _parse(_sampled(size: [2], bitsPerSample: 1, bytes: [0x40]));
      // Bits are packed from the most significant end: 0 then 1.
      expect(oneBit.evaluate([0.0])[0], closeTo(0.0, 1e-12));
      expect(oneBit.evaluate([1.0])[0], closeTo(1.0, 1e-12));

      final fourBit =
          await _parse(_sampled(size: [2], bitsPerSample: 4, bytes: [0x0F]));
      expect(fourBit.evaluate([0.0])[0], closeTo(0.0, 1e-12));
      expect(fourBit.evaluate([1.0])[0], closeTo(1.0, 1e-12));

      final twelveBit = await _parse(
          _sampled(size: [2], bitsPerSample: 12, bytes: [0x00, 0x0F, 0xFF]));
      expect(twelveBit.evaluate([0.0])[0], closeTo(0.0, 1e-12));
      expect(twelveBit.evaluate([1.0])[0], closeTo(1.0, 1e-12));

      final sixteenBit = await _parse(_sampled(
          size: [2], bitsPerSample: 16, bytes: [0x00, 0x00, 0xFF, 0xFF]));
      expect(sixteenBit.evaluate([0.0])[0], closeTo(0.0, 1e-12));
      expect(sixteenBit.evaluate([1.0])[0], closeTo(1.0, 1e-12));
      expect(sixteenBit.evaluate([0.5])[0], closeTo(0.5, 1e-12));
    });

    test('multiple outputs are interleaved per sample', () async {
      final function = await _parse(_sampled(
          size: [2],
          bitsPerSample: 8,
          range: [0.0, 1.0, 0.0, 1.0],
          bytes: [0x00, 0xFF, 0xFF, 0x00]));
      expect(function.outputCount, 2);
      final low = function.evaluate([0.0]);
      expect(low[0], closeTo(0.0, 1e-12));
      expect(low[1], closeTo(1.0, 1e-12));
      final high = function.evaluate([1.0]);
      expect(high[0], closeTo(1.0, 1e-12));
      expect(high[1], closeTo(0.0, 1e-12));
    });

    test('the first input dimension varies fastest', () async {
      // Table for Size [2, 2]: (0,0)=0 (1,0)=255 (0,1)=255 (1,1)=0.
      final function = await _parse(_sampled(
          size: [2, 2],
          bitsPerSample: 8,
          domain: [0.0, 1.0, 0.0, 1.0],
          bytes: [0x00, 0xFF, 0xFF, 0x00]));
      expect(function.inputCount, 2);
      expect(function.evaluate([0.0, 0.0])[0], closeTo(0.0, 1e-12));
      expect(function.evaluate([1.0, 0.0])[0], closeTo(1.0, 1e-12));
      expect(function.evaluate([0.0, 1.0])[0], closeTo(1.0, 1e-12));
      expect(function.evaluate([1.0, 1.0])[0], closeTo(0.0, 1e-12));
      // The centre of the bilinear saddle is the mean of the four corners.
      expect(function.evaluate([0.5, 0.5])[0], closeTo(0.5, 1e-12));
    });

    test('honours /Encode and /Decode', () async {
      // Encode reverses the table, so the ramp runs downwards.
      final reversed = await _parse(_sampled(
          size: [2],
          bitsPerSample: 8,
          bytes: [0x00, 0xFF],
          encode: [1.0, 0.0]));
      expect(reversed.evaluate([0.0])[0], closeTo(1.0, 1e-12));
      expect(reversed.evaluate([1.0])[0], closeTo(0.0, 1e-12));

      // Decode maps the raw samples onto -1..1 instead of the range.
      final decoded = await _parse(_sampled(
          size: [2],
          bitsPerSample: 8,
          bytes: [0x00, 0xFF],
          range: [-1.0, 1.0],
          decode: [-1.0, 1.0]));
      expect(decoded.evaluate([0.0])[0], closeTo(-1.0, 1e-12));
      expect(decoded.evaluate([0.5])[0], closeTo(0.0, 1e-12));
    });

    test('order 3 falls back to linear interpolation', () async {
      final function = await _parse(
          _sampled(size: [2], bitsPerSample: 8, bytes: [0x00, 0xFF], order: 3));
      expect((function as CraftPdfFunctionSampled).order, 3);
      expect(function.evaluate([0.5])[0], closeTo(0.5, 1e-12));
    });

    test('rejects an unsupported bits per sample', () async {
      expect(
          await CraftPdfFunction.parse(
              _sampled(size: [2], bitsPerSample: 5, bytes: [0x00, 0xFF])),
          isNull);
    });

    test('a truncated sample table reads as zero instead of throwing',
        () async {
      final function =
          await _parse(_sampled(size: [4], bitsPerSample: 8, bytes: [0xFF]));
      expect(function.evaluate([0.0])[0], closeTo(1.0, 1e-12));
      expect(function.evaluate([1.0])[0], closeTo(0.0, 1e-12));
    });
  });

  group('type 3 stitching', () {
    /// Two half ramps stitched at 0.5 reproduce a single 0..1 ramp.
    Future<CraftPdfFunction> twoRamps() async {
      final dict = CraftPdfDictionary();
      dict.put(_n('FunctionType'), CraftPdfNumber.fromInt(3));
      dict.put(_n('Domain'), CraftPdfArray.fromDoubles([0.0, 1.0]));
      dict.put(
          _n('Functions'),
          CraftPdfArray.fromList([
            _exponential(c0: [0.0], c1: [0.5]),
            _exponential(c0: [0.5], c1: [1.0]),
          ]));
      dict.put(_n('Bounds'), CraftPdfArray.fromDoubles([0.5]));
      dict.put(_n('Encode'), CraftPdfArray.fromDoubles([0.0, 1.0, 0.0, 1.0]));
      return _parse(dict);
    }

    test('selects the subfunction and re-encodes the input', () async {
      final function = await twoRamps();
      expect(function, isA<CraftPdfFunctionStitching>());
      expect(function.inputCount, 1);
      expect(function.outputCount, 1);
      expect(function.evaluate([0.0])[0], closeTo(0.0, 1e-12));
      expect(function.evaluate([0.25])[0], closeTo(0.25, 1e-12));
      expect(function.evaluate([0.5])[0], closeTo(0.5, 1e-12));
      expect(function.evaluate([0.75])[0], closeTo(0.75, 1e-12));
      expect(function.evaluate([1.0])[0], closeTo(1.0, 1e-12));
    });

    test('a single subfunction needs no bounds', () async {
      final dict = CraftPdfDictionary();
      dict.put(_n('FunctionType'), CraftPdfNumber.fromInt(3));
      dict.put(_n('Domain'), CraftPdfArray.fromDoubles([0.0, 1.0]));
      dict.put(
          _n('Functions'),
          CraftPdfArray.fromList([
            _exponential(c0: [0.0], c1: [1.0])
          ]));
      dict.put(_n('Bounds'), CraftPdfArray());
      // The subdomain 0..1 is mapped onto the subfunction's 1..0, reversing it.
      dict.put(_n('Encode'), CraftPdfArray.fromDoubles([1.0, 0.0]));
      final function = await _parse(dict);
      expect(function.evaluate([0.25])[0], closeTo(0.75, 1e-12));
    });

    test('is rejected when /Bounds has the wrong length', () async {
      final dict = CraftPdfDictionary();
      dict.put(_n('FunctionType'), CraftPdfNumber.fromInt(3));
      dict.put(_n('Domain'), CraftPdfArray.fromDoubles([0.0, 1.0]));
      dict.put(_n('Functions'),
          CraftPdfArray.fromList([_exponential(), _exponential()]));
      dict.put(_n('Bounds'), CraftPdfArray.fromDoubles([0.3, 0.6]));
      dict.put(_n('Encode'), CraftPdfArray.fromDoubles([0.0, 1.0, 0.0, 1.0]));
      expect(await CraftPdfFunction.parse(dict), isNull);
    });
  });

  group('type 4 PostScript calculator', () {
    test('{ 2 mul } doubles its input', () async {
      final function =
          await _parse(_postScript('{ 2 mul }', range: [0.0, 2.0]));
      expect(function, isA<CraftPdfFunctionPostScript>());
      expect(function.evaluate([0.3])[0], closeTo(0.6, 1e-12));
      expect(function.evaluate([1.0])[0], closeTo(2.0, 1e-12));
    });

    test('clips the result to the range', () async {
      final function =
          await _parse(_postScript('{ 2 mul }', range: [0.0, 1.0]));
      expect(function.evaluate([0.8])[0], closeTo(1.0, 1e-12));
    });

    test('produces several outputs bottom to top', () async {
      final function = await _parse(_postScript('{ dup dup 1 exch sub }',
          range: [0.0, 1.0, 0.0, 1.0, 0.0, 1.0]));
      expect(function.outputCount, 3);
      final result = function.evaluate([0.25]);
      expect(result[0], closeTo(0.25, 1e-12));
      expect(result[1], closeTo(0.25, 1e-12));
      expect(result[2], closeTo(0.75, 1e-12));
    });

    test('arithmetic operators', () async {
      expect(await _runProgram('{ 3 add }', 4.0), closeTo(7.0, 1e-12));
      expect(await _runProgram('{ 3 sub }', 4.0), closeTo(1.0, 1e-12));
      expect(await _runProgram('{ 4 div }', 3.0), closeTo(0.75, 1e-12));
      // Division by zero must not produce infinity.
      expect(await _runProgram('{ 0 div }', 3.0), closeTo(0.0, 1e-12));
      expect(await _runProgram('{ 4 idiv }', 7.0), closeTo(1.0, 1e-12));
      expect(await _runProgram('{ 4 mod }', 7.0), closeTo(3.0, 1e-12));
      expect(await _runProgram('{ neg }', 7.0), closeTo(-7.0, 1e-12));
      expect(await _runProgram('{ abs }', -7.0), closeTo(7.0, 1e-12));
      expect(await _runProgram('{ ceiling }', 1.2), closeTo(2.0, 1e-12));
      expect(await _runProgram('{ floor }', 1.8), closeTo(1.0, 1e-12));
      expect(await _runProgram('{ round }', 1.5), closeTo(2.0, 1e-12));
      expect(await _runProgram('{ truncate }', -1.8), closeTo(-1.0, 1e-12));
      expect(await _runProgram('{ sqrt }', 9.0), closeTo(3.0, 1e-12));
      expect(await _runProgram('{ cvi }', 1.9), closeTo(1.0, 1e-12));
      expect(await _runProgram('{ cvr }', 1.9), closeTo(1.9, 1e-12));
    });

    test('transcendental operators use degrees and the documented bases',
        () async {
      expect(await _runProgram('{ sin }', 90.0), closeTo(1.0, 1e-12));
      expect(await _runProgram('{ cos }', 180.0), closeTo(-1.0, 1e-12));
      // atan takes num den and answers in degrees within 0..360.
      expect(await _runProgram('{ 0 atan }', 1.0), closeTo(90.0, 1e-9));
      expect(await _runProgram('{ 1 atan }', -1.0), closeTo(315.0, 1e-9));
      expect(await _runProgram('{ 3 exp }', 2.0), closeTo(8.0, 1e-12));
      expect(await _runProgram('{ ln }', 1.0), closeTo(0.0, 1e-12));
      expect(await _runProgram('{ log }', 100.0), closeTo(2.0, 1e-12));
    });

    test('relational, boolean and bitwise operators', () async {
      expect(await _runProgram('{ 1 eq { 10 } { 20 } ifelse }', 1.0),
          closeTo(10.0, 1e-12));
      expect(await _runProgram('{ 1 ne { 10 } { 20 } ifelse }', 1.0),
          closeTo(20.0, 1e-12));
      expect(await _runProgram('{ 0.5 gt { 1 } { 0 } ifelse }', 0.6),
          closeTo(1.0, 1e-12));
      expect(await _runProgram('{ 0.5 ge { 1 } { 0 } ifelse }', 0.5),
          closeTo(1.0, 1e-12));
      expect(await _runProgram('{ 0.5 lt { 1 } { 0 } ifelse }', 0.6),
          closeTo(0.0, 1e-12));
      expect(await _runProgram('{ 0.5 le { 1 } { 0 } ifelse }', 0.5),
          closeTo(1.0, 1e-12));
      expect(
          await _runProgram('{ pop true false and { 1 } { 0 } ifelse }', 0.0),
          closeTo(0.0, 1e-12));
      expect(await _runProgram('{ pop true false or { 1 } { 0 } ifelse }', 0.0),
          closeTo(1.0, 1e-12));
      expect(await _runProgram('{ pop true true xor { 1 } { 0 } ifelse }', 0.0),
          closeTo(0.0, 1e-12));
      expect(await _runProgram('{ pop false not { 1 } { 0 } ifelse }', 0.0),
          closeTo(1.0, 1e-12));
      // On integers the same operators are bitwise.
      expect(await _runProgram('{ 3 and }', 6.0), closeTo(2.0, 1e-12));
      expect(await _runProgram('{ 3 or }', 4.0), closeTo(7.0, 1e-12));
      expect(await _runProgram('{ 3 xor }', 6.0), closeTo(5.0, 1e-12));
      expect(await _runProgram('{ 2 bitshift }', 1.0), closeTo(4.0, 1e-12));
      expect(await _runProgram('{ -2 bitshift }', 8.0), closeTo(2.0, 1e-12));
    });

    test('if executes only when the condition holds', () async {
      expect(await _runProgram('{ dup 0.5 gt { 100 mul } if }', 0.6),
          closeTo(60.0, 1e-9));
      expect(await _runProgram('{ dup 0.5 gt { 100 mul } if }', 0.4),
          closeTo(0.4, 1e-12));
    });

    test('stack operators', () async {
      expect(await _runProgram('{ 5 exch pop }', 2.0), closeTo(5.0, 1e-12));
      expect(await _runProgram('{ dup add }', 3.0), closeTo(6.0, 1e-12));
      // 3 1 2 -> copy 2 -> 3 1 2 1 2 -> the top is 2, sum of the two adds is 3.
      expect(await _runProgram('{ pop 3 1 2 2 copy add add add add }', 0.0),
          closeTo(9.0, 1e-12));
      // index 2 reaches past the top two entries to the 7.
      expect(
          await _runProgram('{ pop 7 8 9 2 index }', 0.0), closeTo(7.0, 1e-12));
      // roll by 1 lifts the bottom of the window to the top: 1 2 3 -> 3 1 2.
      expect(await _runProgram('{ pop 1 2 3 3 1 roll pop pop }', 0.0),
          closeTo(3.0, 1e-12));
      expect(await _runProgram('{ pop 1 2 3 3 -1 roll pop pop }', 0.0),
          closeTo(2.0, 1e-12));
    });

    test('comments and irregular white space are ignored', () async {
      final function = await _parse(
          _postScript('%!PS\n{\n\t2 mul % double it\n}\n', range: [0.0, 2.0]));
      expect(function.evaluate([0.5])[0], closeTo(1.0, 1e-12));
    });

    test('an unbalanced program does not parse', () async {
      expect(await CraftPdfFunction.parse(_postScript('{ 2 mul')), isNull);
      expect(await CraftPdfFunction.parse(_postScript('2 mul')), isNull);
    });

    test('an overflowing program is contained and yields zeros', () async {
      final pushes = List<String>.filled(200, '1').join(' ');
      final function = await _parse(_postScript('{ $pushes }'));
      expect(function.evaluate([0.5])[0], 0.0);
    });

    test('an unknown operator is contained and yields zeros', () async {
      final function = await _parse(_postScript('{ 2 frobnicate }'));
      expect(function.evaluate([0.5])[0], 0.0);
    });
  });

  group('function arrays', () {
    test('n one in one out functions stand in for one n output function',
        () async {
      final array = CraftPdfArray.fromList([
        _exponential(c0: [0.0], c1: [1.0]),
        _exponential(c0: [1.0], c1: [0.0]),
        _exponential(c0: [0.5], c1: [0.5]),
      ]);
      final function = await _parse(array);
      expect(function, isA<CraftPdfFunctionArray>());
      expect(function.inputCount, 1);
      expect(function.outputCount, 3);
      final result = function.evaluate([0.25]);
      expect(result[0], closeTo(0.25, 1e-12));
      expect(result[1], closeTo(0.75, 1e-12));
      expect(result[2], closeTo(0.5, 1e-12));
    });

    test('an array holding a multi output function is rejected', () async {
      final array = CraftPdfArray.fromList([
        _exponential(c0: [0.0, 0.0], c1: [1.0, 1.0]),
      ]);
      expect(await CraftPdfFunction.parse(array), isNull);
    });
  });

  group('parse', () {
    test('resolves an indirect reference', () async {
      final reference = CraftPdfIndirectReference(1, 0, _exponential());
      final function = await _parse(reference);
      expect(function, isA<CraftPdfFunctionExponential>());
    });

    test('returns null for objects that are not functions', () async {
      expect(await CraftPdfFunction.parse(null), isNull);
      expect(await CraftPdfFunction.parse(CraftPdfName.deviceRgb), isNull);
      expect(await CraftPdfFunction.parse(CraftPdfDictionary()), isNull);
      final unknownType = CraftPdfDictionary();
      unknownType.put(_n('FunctionType'), CraftPdfNumber.fromInt(9));
      unknownType.put(_n('Domain'), CraftPdfArray.fromDoubles([0.0, 1.0]));
      expect(await CraftPdfFunction.parse(unknownType), isNull);
    });
  });

  group('helpers', () {
    test('interpolate maps between intervals', () {
      expect(CraftPdfFunction.interpolate(0.5, 0.0, 1.0, 10.0, 20.0),
          closeTo(15.0, 1e-12));
      // A degenerate source interval collapses onto the low end.
      expect(CraftPdfFunction.interpolate(0.5, 1.0, 1.0, 10.0, 20.0),
          closeTo(10.0, 1e-12));
    });

    test('clip tolerates reversed bounds', () {
      expect(CraftPdfFunction.clip(5.0, 10.0, 0.0), closeTo(5.0, 1e-12));
      expect(CraftPdfFunction.clip(-5.0, 10.0, 0.0), closeTo(0.0, 1e-12));
    });
  });
}
