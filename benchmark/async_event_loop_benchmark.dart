import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:dpdf/dpdf.dart';

Future<Uint8List> fixture(int pages) async {
  final out = BytesBuilder();
  final doc = CraftPdfDocument.create(CraftPdfWriter.fromBytesBuilder(out));
  final font = CraftPdfFontFactory.createFont('Helvetica');
  for (var number = 0; number < pages; number++) {
    final canvas = await CraftPdfCanvas.fromPage(await doc.appendBlankPage());
    canvas.beginText();
    await canvas.setFontAndSize(font, 12);
    canvas.moveText(20, 700).showText('Synthetic page ${number + 1}').endText();
  }
  await doc.close();
  return out.takeBytes();
}

Future<int> operation(Uint8List source, int pages, String task) async {
  final bytes = task == 'merge'
      ? await PdfPageAssembly.merge(
          [PdfPageSelection(source), PdfPageSelection(source)])
      : source;
  final expected = task == 'merge' ? pages * 2 : pages;
  final doc = await CraftPdfDocument.open(CraftPdfReader.fromBytes(bytes));
  try {
    if (doc.pageTotal() != expected) throw StateError('Unexpected page count');
    if (task == 'extract') {
      for (var page = 1; page <= pages; page++) {
        final text =
            await PdfTextExtraction.fromPage((await doc.pageAt(page))!);
        if (!text.contains('Synthetic page $page')) {
          throw StateError('Incorrect extraction');
        }
      }
    }
    return expected;
  } finally {
    await doc.close();
  }
}

Future<Map<String, Object>> sample(
    Uint8List bytes, int pages, String task, bool worker) async {
  final watch = Stopwatch()..start();
  var previous = 0, maxGap = 0, ticks = 0;
  int? zeroLatency;
  final zero = Timer(Duration.zero, () {
    zeroLatency = watch.elapsedMicroseconds;
  });
  final timer = Timer.periodic(const Duration(milliseconds: 1), (_) {
    final now = watch.elapsedMicroseconds;
    final gap = now - previous;
    if (gap > maxGap) maxGap = gap;
    previous = now;
    ticks++;
  });
  late int count;
  try {
    count = worker
        ? await Isolate.run(() => operation(bytes, pages, task))
        : await operation(bytes, pages, task);
    final elapsed = watch.elapsedMicroseconds;
    final firedBeforeCompletion = zeroLatency != null;
    final ticksDuringOperation = ticks;
    final lastOperationTick = previous;
    final operationMaxGap = maxGap;
    // Drain one event turn after completion to measure starvation of Timer.zero.
    await Future<void>.delayed(Duration.zero);
    final finalGap = elapsed - lastOperationTick;
    final operationGap =
        finalGap > operationMaxGap ? finalGap : operationMaxGap;
    return {
      'operation': task,
      'execution': worker ? 'Isolate.run' : 'same_isolate_async',
      'elapsed_us': elapsed,
      'timer_zero_us': zeroLatency ?? watch.elapsedMicroseconds,
      'timer_zero_before_completion': firedBeforeCompletion,
      'heartbeat_ticks': ticksDuringOperation,
      'max_heartbeat_gap_us': operationGap,
      'verified_pages': count,
    };
  } finally {
    timer.cancel();
    zero.cancel();
    watch.stop();
  }
}

Future<void> main(List<String> args) async {
  final pages = args.isEmpty ? 100 : int.parse(args[0]);
  if (pages < 1) throw ArgumentError('Page count must be positive');
  final bytes = await fixture(pages);
  final samples = <Map<String, Object>>[];
  for (final task in ['merge', 'extract']) {
    // Warm both execution paths; each Isolate.run necessarily starts a fresh VM isolate.
    await sample(bytes, pages, task, false);
    await sample(bytes, pages, task, true);
    for (var iteration = 0; iteration < 3; iteration++) {
      for (final worker in iteration.isEven ? [false, true] : [true, false]) {
        samples.add(await sample(bytes, pages, task, worker));
      }
    }
  }
  print(jsonEncode({
    'runtime': Platform.version,
    'os': Platform.operatingSystem,
    'pages': pages,
    'input_bytes': bytes.length,
    'samples_per_case': 3,
    'warmups_per_case': 1,
    'scope':
        'VM JIT. Fixture construction excluded. Operation includes opening/closing and page-count validation; extraction additionally verifies every page text. Isolate.run includes startup and message transfer. Timer resolution and scheduling are OS dependent.',
    'samples': samples,
  }));
}
