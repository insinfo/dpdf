import 'package:test/test.dart';
import 'package:dpdf/src/commons/actions/event_manager.dart';
import 'package:dpdf/src/commons/exceptions/dpdf_exception.dart';
import 'package:dpdf/src/commons/logger.dart';
import 'package:dpdf/src/commons/dpdf_log_manager.dart';

class _Notification extends AbstractEvent {}

class _Handler implements CraftEventHandler {
  final void Function(CraftEvent) callback;
  _Handler(this.callback);
  @override
  void onEvent(CraftEvent event) => callback(event);
}

void main() {
  final manager = CraftEventManager.instance;
  setUp(manager.clear);
  tearDown(() {
    manager.clear();
    LogManager.resetLoggerFactory();
  });

  test('dispatch snapshots recipients when callbacks register and remove', () {
    final calls = <String>[];
    final late = _Handler((_) => calls.add('late'));
    final second = _Handler((_) => calls.add('second'));
    final first = _Handler((_) {
      calls.add('first');
      manager.unregister(second);
      manager.register(late);
    });
    manager.register(first);
    manager.register(second);
    manager.onEvent(_Notification());
    expect(calls, ['first', 'second']);
    calls.clear();
    manager.onEvent(_Notification());
    expect(calls, ['first', 'late']);
  });

  test('clear during delivery affects the next event only', () {
    final calls = <int>[];
    manager.register(_Handler((_) {
      calls.add(1);
      manager.clear();
    }));
    manager.register(_Handler((_) => calls.add(2)));
    manager.onEvent(_Notification());
    manager.onEvent(_Notification());
    expect(calls, [1, 2]);
  });

  test('duplicate registration delivers once and re-registration moves to end',
      () {
    final calls = <int>[];
    final first = _Handler((_) => calls.add(1));
    final second = _Handler((_) => calls.add(2));
    manager.register(first);
    manager.register(first);
    manager.register(second);
    manager.onEvent(_Notification());
    expect(calls, [1, 2]);
    calls.clear();
    manager.unregister(first);
    manager.register(first);
    manager.onEvent(_Notification());
    expect(calls, [2, 1]);
  });

  test('nested dispatch uses current registrations', () {
    final calls = <String>[];
    var nested = false;
    final late = _Handler((_) => calls.add('late'));
    manager.register(_Handler((event) {
      calls.add(nested ? 'nested' : 'outer');
      if (!nested) {
        nested = true;
        manager.register(late);
        manager.onEvent(event);
      }
    }));
    manager.onEvent(_Notification());
    expect(calls, ['outer', 'nested', 'late']);
  });

  test('handler errors propagate without replacing the original failure', () {
    final error = StateError('listener failure');
    var laterCalled = false;
    manager.register(_Handler((_) => throw error));
    manager.register(_Handler((_) => laterCalled = true));
    expect(() => manager.onEvent(_Notification()), throwsA(same(error)));
    expect(laterCalled, isFalse);
  });

  test('logger resolver receives exact names on every lookup and resets', () {
    final names = <String>[];
    LogManager.setLoggerFactory((name) {
      names.add(name);
      return ConsoleLogger(name);
    });
    final first = LogManager.getLoggerByName('custom');
    final second = LogManager.getLoggerByName('custom');
    LogManager.getLogger(_Notification);
    expect(names, ['custom', 'custom', '_Notification']);
    expect(identical(first, second), isFalse);
    LogManager.resetLoggerFactory();
    expect(LogManager.getLoggerByName('restored'), isA<ConsoleLogger>());
    expect(names.length, 3);
  });

  test('base and aggregate diagnostics retain original causes', () {
    final cause = StateError('disk full');
    final error = DpdfException('write failed', cause);
    expect(error.getCause(), same(cause));
    expect(error.getMessage(), 'write failed');
    expect(error.toString(), contains('disk full'));
    final aggregate =
        CraftAggregatedException('multiple failures', [error], cause);
    expect(aggregate.toString(), contains('[0] Exception: write failed'));
    expect(aggregate.toString(), contains('Caused by: Bad state: disk full'));
    expect(DpdfException.withDefaultMessage().getMessage(), isNotEmpty);
  });
}
