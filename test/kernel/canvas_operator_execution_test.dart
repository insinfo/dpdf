import 'dart:async';
import 'dart:typed_data';

import 'package:pdfcraft/src/kernel/pdf/canvas/parser/content_operator.dart';
import 'package:pdfcraft/src/kernel/pdf/canvas/parser/data/event_data.dart';
import 'package:pdfcraft/src/kernel/pdf/canvas/parser/event_type.dart';
import 'package:pdfcraft/src/kernel/pdf/canvas/parser/listener/event_listener.dart';
import 'package:pdfcraft/src/kernel/pdf/canvas/parser/pdf_canvas_processor.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_literal.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_object.dart';
import 'package:test/test.dart';

class _Listener implements CraftEventListener {
  final events = <CraftEventType>[];

  @override
  void eventOccurred(CraftEventData? data, CraftEventType type) =>
      events.add(type);

  @override
  Set<CraftEventType> getSupportedEvents() => CraftEventType.values.toSet();
}

class _CallbackOperator implements CraftContentOperator {
  final FutureOr<void> Function() callback;
  _CallbackOperator(this.callback);

  @override
  FutureOr<void> invoke(CraftPdfCanvasProcessor processor,
          CraftPdfLiteral operator, List<CraftPdfObject> operands) =>
      callback();
}

Uint8List _content(String text) => Uint8List.fromList(text.codeUnits);

void main() {
  test('built-in operators execute before a queued microtask', () async {
    final listener = _Listener();
    final processor = CraftPdfCanvasProcessor(listener);
    var microtaskRan = false;
    scheduleMicrotask(() => microtaskRan = true);
    final pending =
        processor.processContent(_content('BT (hello) Tj ET'), null);
    expect(microtaskRan, isFalse);
    expect(listener.events, [
      CraftEventType.beginTextBlock,
      CraftEventType.renderText,
      CraftEventType.endTextBlock,
    ]);
    await pending;
  });

  test('external asynchronous operator completes before the next operator',
      () async {
    final processor = CraftPdfCanvasProcessor(_Listener());
    final barrier = Completer<void>();
    final order = <String>[];
    processor.registerContentOperator('custom', _CallbackOperator(() async {
      order.add('start');
      await barrier.future;
      order.add('end');
    }));
    processor.registerContentOperator('next', _CallbackOperator(() {
      order.add('next');
    }));
    final pending = processor.processContent(_content('custom next'), null);
    expect(order, ['start']);
    barrier.complete();
    await pending;
    expect(order, ['start', 'end', 'next']);
  });

  for (final asynchronous in [false, true]) {
    test('propagates operator errors with asynchronous=$asynchronous',
        () async {
      final processor = CraftPdfCanvasProcessor(_Listener());
      final failure = StateError('operator failed');
      var reachedNext = false;
      processor.registerContentOperator(
          'broken',
          _CallbackOperator(
            asynchronous
                ? () async {
                    await Future<void>.value();
                    throw failure;
                  }
                : () => throw failure,
          ));
      processor.registerContentOperator('next', _CallbackOperator(() {
        reachedNext = true;
      }));
      await expectLater(processor.processContent(_content('broken next'), null),
          throwsA(same(failure)));
      expect(reachedNext, isFalse);
    });
  }
}
