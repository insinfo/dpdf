import 'dart:io';
import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';

/// Simple benchmark for FilterHandlers
///
/// Run with: dart run benchmark/filter_benchmark.dart
void main() {
  print('='.padRight(60, '='));
  print('FilterHandlers Benchmark');
  print('='.padRight(60, '='));
  print('');

  // Prepare test data of various sizes
  final sizes = [1024, 10 * 1024, 100 * 1024, 500 * 1024];
  final iterations = 100;

  for (final size in sizes) {
    print('Data size: ${(size / 1024).toStringAsFixed(0)} KB');
    print('-'.padRight(40, '-'));

    // Generate random-ish data (using pattern to be compressible)
    final data = _generateTestData(size);

    // Prepare compressed data for FlateDecode
    final compressed = zlib.encode(data);

    // Prepare ASCIIHex encoded data
    final hexEncoded = _asciiHexEncode(data);

    // Prepare RunLength encoded data
    final rlEncoded = _runLengthEncode(data);

    // Benchmark FlateDecode
    _benchmark('FlateDecode', iterations, () {
      final dict = PdfDictionary();
      dict.put(PdfName.filter, PdfName.flateDecodeFilter);
      FilterHandlers.decodeBytes(Uint8List.fromList(compressed), dict);
    });

    // Benchmark ASCIIHexDecode
    _benchmark('ASCIIHexDecode', iterations, () {
      final dict = PdfDictionary();
      dict.put(PdfName.filter, PdfName.asciiHexDecodeFilter);
      FilterHandlers.decodeBytes(hexEncoded, dict);
    });

    // Benchmark RunLengthDecode
    _benchmark('RunLengthDecode', iterations, () {
      final dict = PdfDictionary();
      dict.put(PdfName.filter, PdfName.runLengthDecodeFilter);
      FilterHandlers.decodeBytes(rlEncoded, dict);
    });

    print('');
  }

  print('='.padRight(60, '='));
  print('Benchmark complete');
  print('='.padRight(60, '='));
}

/// Generates test data with repeating patterns (compressible)
Uint8List _generateTestData(int size) {
  final data = Uint8List(size);
  for (var i = 0; i < size; i++) {
    // Mix of patterns to make it somewhat compressible
    data[i] = (i % 256 + (i ~/ 256) % 17) & 0xFF;
  }
  return data;
}

/// Simple ASCII hex encoding
Uint8List _asciiHexEncode(Uint8List data) {
  const hexChars = '0123456789ABCDEF';
  final result = Uint8List(data.length * 2 + 1); // +1 for EOD marker

  for (var i = 0; i < data.length; i++) {
    final b = data[i];
    result[i * 2] = hexChars.codeUnitAt((b >> 4) & 0x0F);
    result[i * 2 + 1] = hexChars.codeUnitAt(b & 0x0F);
  }
  result[data.length * 2] = 0x3E; // '>'

  return result;
}

/// Simple run-length encoding
Uint8List _runLengthEncode(Uint8List data) {
  if (data.isEmpty) return Uint8List.fromList([128]); // EOD only

  final result = <int>[];
  var i = 0;

  while (i < data.length) {
    // Check for run of same bytes
    var runLength = 1;
    while (i + runLength < data.length &&
        runLength < 128 &&
        data[i + runLength] == data[i]) {
      runLength++;
    }

    if (runLength > 2) {
      // Encode as run
      result.add(257 - runLength);
      result.add(data[i]);
      i += runLength;
    } else {
      // Encode as literal
      var literalStart = i;
      var literalLength = 0;

      while (i < data.length && literalLength < 128) {
        // Check if next bytes form a run
        var nextRunLength = 1;
        while (i + nextRunLength < data.length &&
            nextRunLength < 3 &&
            data[i + nextRunLength] == data[i]) {
          nextRunLength++;
        }

        if (nextRunLength >= 3 && literalLength > 0) {
          break; // End literal, start run next
        }

        literalLength++;
        i++;
      }

      result.add(literalLength - 1);
      for (var j = literalStart; j < literalStart + literalLength; j++) {
        result.add(data[j]);
      }
    }
  }

  result.add(128); // EOD
  return Uint8List.fromList(result);
}

/// Runs a benchmark
void _benchmark(String name, int iterations, void Function() fn) {
  // Warm up
  for (var i = 0; i < 5; i++) {
    fn();
  }

  // Measure
  final sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    fn();
  }
  sw.stop();

  final avgUs = sw.elapsedMicroseconds / iterations;
  final throughput = iterations * 1000000 / sw.elapsedMicroseconds;

  print(
      '  $name: ${avgUs.toStringAsFixed(1)} µs/op (${throughput.toStringAsFixed(1)} ops/s)');
}
