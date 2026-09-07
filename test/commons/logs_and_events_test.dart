import 'package:test/test.dart';
import 'package:dpdf/src/commons/logs/commons_log_message_constant.dart';
import 'package:dpdf/src/commons/actions/event_manager.dart';
import 'package:dpdf/src/io/logs/io_log_message_constant.dart';
import 'package:dpdf/src/kernel/logs/kernel_log_message_constant.dart';

void main() {
  group('CommonsLogMessageConstant', () {
    test('contains base64 exception message', () {
      expect(CraftCommonsLogMessageConstant.base64Exception, isNotEmpty);
    });

    test('contains placeholder patterns', () {
      expect(CraftCommonsLogMessageConstant.invalidStatisticsName,
          contains('{0}'));
    });
  });

  group('EventManager', () {
    test('singleton instance', () {
      final em1 = CraftEventManager.instance;
      final em2 = CraftEventManager.instance;
      expect(identical(em1, em2), isTrue);
    });

    test('register and dispatch event', () {
      final manager = CraftEventManager.instance;
      manager.clear();

      String? receivedType;
      final handler = _TestEventHandler((event) {
        receivedType = event.eventType;
      });

      manager.register(handler);
      manager.onEvent(_TestEvent('test_type'));

      expect(receivedType, equals('_TestEvent'));

      manager.unregister(handler);
    });

    test('unregister handler', () {
      final manager = CraftEventManager.instance;
      manager.clear();

      int callCount = 0;
      final handler = _TestEventHandler((_) => callCount++);

      manager.register(handler);
      manager.onEvent(_TestEvent('test'));
      expect(callCount, equals(1));

      manager.unregister(handler);
      manager.onEvent(_TestEvent('test'));
      expect(callCount, equals(1)); // Should not increase
    });
  });

  group('ProductNameConstant', () {
    test('contains dpdf Core', () {
      expect(CraftProductNameConstant.Core, equals('dpdf Core'));
    });
  });

  group('IoLogMessageConstant', () {
    test('contains action message', () {
      expect(
          CraftIoLogMessageConstant.actionWasSetToLinkAnnotationWithDestination,
          isNotEmpty);
    });

    test('contains font messages', () {
      expect(CraftIoLogMessageConstant.fontSubsetIssue, contains('subset'));
    });
  });

  group('KernelLogMessageConstant', () {
    test('contains filter decoding messages', () {
      expect(CraftKernelLogMessageConstant.dctdecodeFilterDecoding,
          contains('DCTDecode'));
      expect(CraftKernelLogMessageConstant.jpxdecodeFilterDecoding,
          contains('JPEG2000'));
    });
  });
}

class _TestEvent extends AbstractEvent {
  final String type;
  _TestEvent(this.type);
}

class _TestEventHandler implements CraftEventHandler {
  final void Function(CraftEvent) callback;
  _TestEventHandler(this.callback);

  @override
  void onEvent(CraftEvent event) => callback(event);
}
