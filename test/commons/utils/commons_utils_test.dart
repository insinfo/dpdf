import 'package:test/test.dart';
import 'package:dpdf/src/commons/utils/message_format_util.dart';
import 'package:dpdf/src/commons/utils/date_time_util.dart';
import 'package:dpdf/src/commons/utils/mathematic_util.dart';
import 'package:dpdf/src/commons/utils/string_util.dart';
import 'package:dpdf/src/commons/utils/java_collections_util.dart';

void main() {
  group('MessageFormatUtil', () {
    test('formats simple placeholders', () {
      expect(
        MessageFormatUtil.format('Hello {0}!', ['World']),
        equals('Hello World!'),
      );
    });

    test('formats multiple placeholders', () {
      expect(
        MessageFormatUtil.format('{0} has {1} messages', ['John', 5]),
        equals('John has 5 messages'),
      );
    });

    test('handles null arguments', () {
      expect(
        MessageFormatUtil.format('Value: {0}', [null]),
        equals('Value: null'),
      );
    });

    test('handles repeated placeholders', () {
      expect(
        MessageFormatUtil.format('{0} and {0}', ['test']),
        equals('test and test'),
      );
    });
  });

  group('DateTimeUtil', () {
    test('getUtcMillisFromEpoch returns milliseconds', () {
      final epoch = DateTime.utc(1970, 1, 1, 0, 0, 0);
      expect(DateTimeUtil.getUtcMillisFromEpoch(epoch), equals(0.0));

      final later = DateTime.utc(1970, 1, 1, 0, 0, 1);
      expect(DateTimeUtil.getUtcMillisFromEpoch(later), equals(1000.0));
    });

    test('getRelativeTime returns milliseconds', () {
      final date = DateTime.utc(1970, 1, 1, 0, 1, 0);
      expect(DateTimeUtil.getRelativeTime(date), equals(60000));
    });

    test('createDateTime creates correct date', () {
      final date = DateTimeUtil.createDateTime(2024, 12, 25, 10, 30, 0);
      expect(date.year, equals(2024));
      expect(date.month, equals(12));
      expect(date.day, equals(25));
      expect(date.hour, equals(10));
      expect(date.minute, equals(30));
    });

    test('createUtcDateTime uses 0-indexed months', () {
      // Month 0 = January
      final date = DateTimeUtil.createUtcDateTime(2024, 0, 15, 12, 0, 0);
      expect(date.month, equals(1));
    });

    test('formatWithDefaultPattern formats correctly', () {
      final date = DateTime(2024, 3, 15);
      expect(DateTimeUtil.formatWithDefaultPattern(date), equals('2024-03-15'));
    });

    test('parseWithDefaultPattern parses correctly', () {
      final date = DateTimeUtil.parseWithDefaultPattern('2024-03-15');
      expect(date.year, equals(2024));
      expect(date.month, equals(3));
      expect(date.day, equals(15));
    });

    test('addMillisToDate adds time', () {
      final date = DateTime(2024, 1, 1, 0, 0, 0);
      final result = DateTimeUtil.addMillisToDate(date, 3600000);
      expect(result.hour, equals(1));
    });

    test('isInPast checks correctly', () {
      final past = DateTime(2000, 1, 1);
      final future = DateTime(2100, 1, 1);

      expect(DateTimeUtil.isInPast(past), isTrue);
      expect(DateTimeUtil.isInPast(future), isFalse);
    });

    test('getTimeFromMillis converts from epoch', () {
      final date = DateTimeUtil.getTimeFromMillis(86400000);
      expect(date.day, equals(2));
      expect(date.month, equals(1));
      expect(date.year, equals(1970));
    });
  });

  group('MathematicUtil', () {
    test('round uses away-from-zero rounding', () {
      expect(MathematicUtil.round(2.5), equals(3.0));
      expect(MathematicUtil.round(2.4), equals(2.0));
      expect(MathematicUtil.round(-2.5), equals(-3.0));
      expect(MathematicUtil.round(-2.4), equals(-2.0));
    });

    test('roundToDecimal works correctly', () {
      expect(MathematicUtil.roundToDecimal(3.14159, 2), equals(3.14));
      expect(MathematicUtil.roundToDecimal(3.145, 2), equals(3.15));
    });
  });

  group('StringUtil', () {
    test('replaceAll with regex', () {
      expect(
        StringUtil.replaceAll('hello world', r'\s+', '-'),
        equals('hello-world'),
      );
    });

    test('split with single char', () {
      final result = StringUtil.split('a,b,c', ',');
      expect(result, equals(['a', 'b', 'c']));
    });

    test('split with regex pattern', () {
      final result = StringUtil.split('a  b   c', r'\s+');
      expect(result, equals(['a', 'b', 'c']));
    });

    test('isNullOrEmpty checks correctly', () {
      expect(StringUtil.isNullOrEmpty(null), isTrue);
      expect(StringUtil.isNullOrEmpty(''), isTrue);
      expect(StringUtil.isNullOrEmpty('hello'), isFalse);
    });

    test('isNullOrWhitespace checks correctly', () {
      expect(StringUtil.isNullOrWhitespace(null), isTrue);
      expect(StringUtil.isNullOrWhitespace(''), isTrue);
      expect(StringUtil.isNullOrWhitespace('   '), isTrue);
      expect(StringUtil.isNullOrWhitespace('hello'), isFalse);
    });
  });

  group('JavaCollectionsUtil', () {
    test('emptyList returns empty list', () {
      final list = JavaCollectionsUtil.emptyList<int>();
      expect(list, isEmpty);
    });

    test('singletonList returns single item', () {
      final list = JavaCollectionsUtil.singletonList(42);
      expect(list, equals([42]));
    });

    test('singletonMap returns single entry', () {
      final map = JavaCollectionsUtil.singletonMap('key', 'value');
      expect(map, equals({'key': 'value'}));
    });

    test('reverse reverses list in place', () {
      final list = [1, 2, 3, 4, 5];
      JavaCollectionsUtil.reverse(list);
      expect(list, equals([5, 4, 3, 2, 1]));
    });

    test('sort sorts list in place', () {
      final list = [3, 1, 4, 1, 5, 9];
      JavaCollectionsUtil.sort(list);
      expect(list, equals([1, 1, 3, 4, 5, 9]));
    });

    test('sort with comparator', () {
      final list = [3, 1, 4, 1, 5, 9];
      JavaCollectionsUtil.sort(list, (a, b) => b.compareTo(a));
      expect(list, equals([9, 5, 4, 3, 1, 1]));
    });

    test('frequency counts occurrences', () {
      expect(JavaCollectionsUtil.frequency([1, 2, 1, 3, 1], 1), equals(3));
      expect(JavaCollectionsUtil.frequency([1, 2, 1, 3, 1], 4), equals(0));
    });

    test('binarySearch finds element', () {
      final list = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];
      expect(JavaCollectionsUtil.binarySearch(list, 'c'), equals(2));
      expect(JavaCollectionsUtil.binarySearch(list, 'a'), equals(0));
    });

    test('binarySearch returns negative for missing', () {
      final list = ['a', 'c', 'e', 'g'];
      expect(JavaCollectionsUtil.binarySearch(list, 'b'), lessThan(0));
    });

    test('fill fills list', () {
      final list = [1, 2, 3, 4, 5];
      JavaCollectionsUtil.fill(list, 0);
      expect(list, equals([0, 0, 0, 0, 0]));
    });

    test('replaceAll replaces values', () {
      final list = [1, 2, 1, 3, 1];
      final result = JavaCollectionsUtil.replaceAll(list, 1, 9);
      expect(result, isTrue);
      expect(list, equals([9, 2, 9, 3, 9]));
    });
  });
}
