import 'package:test/test.dart';
import 'package:dpdf/src/io/util/int_hashtable.dart';

void main() {
  group('IntHashtable', () {
    test('put and get values', () {
      final ht = IntHashtable();
      ht.put(1, 100);
      ht.put(2, 200);
      ht.put(3, 300);

      expect(ht.get(1), equals(100));
      expect(ht.get(2), equals(200));
      expect(ht.get(3), equals(300));
    });

    test('returns 0 for non-existent keys', () {
      final ht = IntHashtable();
      expect(ht.get(999), equals(0));
    });

    test('size increases with puts', () {
      final ht = IntHashtable();
      expect(ht.size(), equals(0));
      ht.put(1, 100);
      expect(ht.size(), equals(1));
      ht.put(2, 200);
      expect(ht.size(), equals(2));
    });

    test('isEmpty returns correct value', () {
      final ht = IntHashtable();
      expect(ht.isEmpty(), isTrue);
      ht.put(1, 100);
      expect(ht.isEmpty(), isFalse);
    });

    test('containsKey works', () {
      final ht = IntHashtable();
      ht.put(42, 100);
      expect(ht.containsKey(42), isTrue);
      expect(ht.containsKey(43), isFalse);
    });

    test('containsValue works', () {
      final ht = IntHashtable();
      ht.put(1, 100);
      expect(ht.containsValue(100), isTrue);
      expect(ht.containsValue(200), isFalse);
    });

    test('remove works', () {
      final ht = IntHashtable();
      ht.put(1, 100);
      expect(ht.remove(1), equals(100));
      expect(ht.containsKey(1), isFalse);
      expect(ht.size(), equals(0));
    });

    test('clear removes all entries', () {
      final ht = IntHashtable();
      ht.put(1, 100);
      ht.put(2, 200);
      ht.clear();
      expect(ht.size(), equals(0));
      expect(ht.isEmpty(), isTrue);
    });

    test('getKeys returns all keys', () {
      final ht = IntHashtable();
      ht.put(3, 300);
      ht.put(1, 100);
      ht.put(2, 200);
      final keys = ht.getKeys();
      expect(keys.length, equals(3));
      expect(keys.contains(1), isTrue);
      expect(keys.contains(2), isTrue);
      expect(keys.contains(3), isTrue);
    });

    test('toOrderedKeys returns sorted keys', () {
      final ht = IntHashtable();
      ht.put(3, 300);
      ht.put(1, 100);
      ht.put(2, 200);
      final keys = ht.toOrderedKeys();
      expect(keys, equals([1, 2, 3]));
    });

    test('clone creates independent copy', () {
      final ht = IntHashtable();
      ht.put(1, 100);
      final clone = ht.clone();
      clone.put(2, 200);
      expect(ht.size(), equals(1));
      expect(clone.size(), equals(2));
    });

    test('operator [] works', () {
      final ht = IntHashtable();
      ht[1] = 100;
      expect(ht[1], equals(100));
    });

    test('handles many entries with rehash', () {
      final ht = IntHashtable.withInitialCapacity(10);
      for (int i = 0; i < 100; i++) {
        ht.put(i, i * 10);
      }
      expect(ht.size(), equals(100));
      for (int i = 0; i < 100; i++) {
        expect(ht.get(i), equals(i * 10));
      }
    });
  });
}
