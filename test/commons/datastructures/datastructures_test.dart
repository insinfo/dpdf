import 'package:test/test.dart';
import 'package:dpdf/src/commons/datastructures/bi_map.dart';
import 'package:dpdf/src/commons/datastructures/null_unlimited_list.dart';
import 'package:dpdf/src/commons/datastructures/simple_array_list.dart';
import 'package:dpdf/src/commons/datastructures/tuple.dart';

void main() {
  group('BiMap', () {
    test('put and getByKey', () {
      final biMap = BiMap<String, int>();
      biMap.put('one', 1);
      biMap.put('two', 2);

      expect(biMap.getByKey('one'), equals(1));
      expect(biMap.getByKey('two'), equals(2));
      expect(biMap.getByKey('three'), isNull);
    });

    test('getByValue', () {
      final biMap = BiMap<String, int>();
      biMap.put('one', 1);
      biMap.put('two', 2);

      expect(biMap.getByValue(1), equals('one'));
      expect(biMap.getByValue(2), equals('two'));
      expect(biMap.getByValue(3), isNull);
    });

    test('removeByKey', () {
      final biMap = BiMap<String, int>();
      biMap.put('one', 1);
      biMap.removeByKey('one');

      expect(biMap.getByKey('one'), isNull);
      expect(biMap.getByValue(1), isNull);
    });

    test('removeByValue', () {
      final biMap = BiMap<String, int>();
      biMap.put('one', 1);
      biMap.removeByValue(1);

      expect(biMap.getByKey('one'), isNull);
      expect(biMap.getByValue(1), isNull);
    });

    test('size and isEmpty', () {
      final biMap = BiMap<String, int>();
      expect(biMap.isEmpty(), isTrue);
      expect(biMap.size(), equals(0));

      biMap.put('one', 1);
      expect(biMap.isEmpty(), isFalse);
      expect(biMap.size(), equals(1));
    });

    test('containsKey and containsValue', () {
      final biMap = BiMap<String, int>();
      biMap.put('one', 1);

      expect(biMap.containsKey('one'), isTrue);
      expect(biMap.containsKey('two'), isFalse);
      expect(biMap.containsValue(1), isTrue);
      expect(biMap.containsValue(2), isFalse);
    });

    test('overwrite existing key', () {
      final biMap = BiMap<String, int>();
      biMap.put('one', 1);
      biMap.put('one', 999);

      expect(biMap.getByKey('one'), equals(999));
      expect(biMap.getByValue(999), equals('one'));
      expect(biMap.getByValue(1), isNull);
    });

    test('overwrite existing value', () {
      final biMap = BiMap<String, int>();
      biMap.put('one', 1);
      biMap.put('new_one', 1);

      expect(biMap.getByValue(1), equals('new_one'));
      expect(biMap.getByKey('new_one'), equals(1));
      expect(biMap.getByKey('one'), isNull);
    });
  });

  group('NullUnlimitedList', () {
    test('add and get', () {
      final list = NullUnlimitedList<String>();
      list.add('a');
      list.add('b');

      expect(list.get(0), equals('a'));
      expect(list.get(1), equals('b'));
      expect(list.size(), equals(2));
    });

    test('handles null values without memory allocation', () {
      final list = NullUnlimitedList<String?>();
      list.add('a');
      list.add(null);
      list.add('b');

      expect(list.get(0), equals('a'));
      expect(list.get(1), isNull);
      expect(list.get(2), equals('b'));
      expect(list.size(), equals(3));
    });

    test('indexOf finds elements', () {
      final list = NullUnlimitedList<String>();
      list.add('a');
      list.add('b');

      expect(list.indexOf('a'), equals(0));
      expect(list.indexOf('b'), equals(1));
      expect(list.indexOf('c'), equals(-1));
    });

    test('set replaces elements', () {
      final list = NullUnlimitedList<String>();
      list.add('a');
      list.add('b');
      list.set(1, 'c');

      expect(list.get(1), equals('c'));
    });

    test('isEmpty returns correct value', () {
      final list = NullUnlimitedList<String>();
      expect(list.isEmpty(), isTrue);

      list.add('a');
      expect(list.isEmpty(), isFalse);
    });
  });

  group('SimpleArrayList', () {
    test('add and get', () {
      final list = SimpleArrayList<int>();
      list.add(1);
      list.add(2);
      list.add(3);

      expect(list.get(0), equals(1));
      expect(list.get(1), equals(2));
      expect(list.get(2), equals(3));
    });

    test('addAt inserts at index', () {
      final list = SimpleArrayList<int>();
      list.add(1);
      list.add(3);
      list.addAt(1, 2);

      expect(list.get(0), equals(1));
      expect(list.get(1), equals(2));
      expect(list.get(2), equals(3));
    });

    test('set replaces element', () {
      final list = SimpleArrayList<int>();
      list.add(1);
      list.add(2);

      final old = list.set(1, 99);
      expect(old, equals(2));
      expect(list.get(1), equals(99));
    });

    test('removeAt removes element', () {
      final list = SimpleArrayList<int>();
      list.add(1);
      list.add(2);
      list.add(3);
      list.removeAt(1);

      expect(list.size(), equals(2));
      expect(list.get(0), equals(1));
      expect(list.get(1), equals(3));
    });

    test('indexOf finds element', () {
      final list = SimpleArrayList<int>();
      list.add(10);
      list.add(20);
      list.add(30);

      expect(list.indexOf(20), equals(1));
      expect(list.indexOf(99), equals(-1));
    });
  });

  group('Tuple2', () {
    test('stores elements', () {
      final tuple = Tuple2('hello', 42);

      expect(tuple.first, equals('hello'));
      expect(tuple.second, equals(42));
      expect(tuple.getFirst(), equals('hello'));
      expect(tuple.getSecond(), equals(42));
    });

    test('equality', () {
      final t1 = Tuple2('a', 1);
      final t2 = Tuple2('a', 1);
      final t3 = Tuple2('a', 2);

      expect(t1, equals(t2));
      expect(t1, isNot(equals(t3)));
    });

    test('hashCode is consistent', () {
      final t1 = Tuple2('a', 1);
      final t2 = Tuple2('a', 1);

      expect(t1.hashCode, equals(t2.hashCode));
    });

    test('toString', () {
      final tuple = Tuple2('a', 1);
      expect(tuple.toString(), contains('first'));
      expect(tuple.toString(), contains('second'));
    });
  });

  group('Tuple3', () {
    test('stores elements', () {
      final tuple = Tuple3('a', 1, true);

      expect(tuple.first, equals('a'));
      expect(tuple.second, equals(1));
      expect(tuple.third, equals(true));
    });

    test('equality', () {
      final t1 = Tuple3('a', 1, true);
      final t2 = Tuple3('a', 1, true);
      final t3 = Tuple3('a', 1, false);

      expect(t1, equals(t2));
      expect(t1, isNot(equals(t3)));
    });
  });
}
