import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dpdf/src/editing/pdf_page_assembly.dart';
import 'package:dpdf/src/editing/pdf_text_extraction.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';

Future<int> inspect(Uint8List bytes, int pages) async {
  final doc = await CraftPdfDocument.open(CraftPdfReader.fromBytes(bytes));
  try {
    if (doc.pageTotal() != pages) throw StateError('Unexpected page count');
    var characters = 0;
    for (var page = 1; page <= pages; page++) {
      final text = await PdfTextExtraction.fromPage((await doc.pageAt(page))!);
      if (!text.contains('Contract page ${(page - 1) % 3 + 1}')) {
        throw StateError('Unexpected page text');
      }
      characters += text.length;
    }
    return characters;
  } finally {
    await doc.close();
  }
}

Future<void> main(List<String> args) async {
  final source = await File(args.isEmpty
          ? 'test/compatibility/assets/generated_three_pages.pdf'
          : args[0])
      .readAsBytes();
  const warmup = 5, samples = 15;
  final load = <int>[], merge = <int>[];
  var outputBytes = 0, characters = 0;
  final total = Stopwatch()..start();
  for (var iteration = -warmup; iteration < samples; iteration++) {
    final watch = Stopwatch()..start();
    characters = await inspect(source, 3);
    final loadTime = watch.elapsedMicroseconds;
    watch.reset();
    final output = await PdfPageAssembly.merge(
        List.generate(3, (_) => PdfPageSelection(source)));
    final mergeTime = watch.elapsedMicroseconds;
    await inspect(output, 9);
    outputBytes = output.length;
    if (iteration >= 0) {
      load.add(loadTime);
      merge.add(mergeTime);
    }
  }
  total.stop();
  Map<String, Object> stats(List<int> values) {
    final sorted = [...values]..sort();
    return {
      'samples_us': values,
      'median_us': sorted[sorted.length ~/ 2],
      'total_us': values.reduce((a, b) => a + b)
    };
  }

  print(jsonEncode({
    'engine': 'dpdf',
    'runtime': Platform.version,
    'os': Platform.operatingSystem,
    'warmup': warmup,
    'samples': samples,
    'input_bytes': source.length,
    'output_bytes': outputBytes,
    'input_pages': 3,
    'output_pages': 9,
    'extracted_characters': characters,
    'load_extract': stats(load),
    'merge': stats(merge),
    'wall_total_us': total.elapsedMicroseconds,
    'timing_scope':
        'VM JIT; bytes read before timing; load includes extraction and checks; merge excludes output verification; wall includes warmup and verification'
  }));
}
