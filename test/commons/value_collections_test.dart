import 'package:dpdf/src/commons/utils/value_collections.dart';
import 'package:dpdf/src/kernel/numbering/alphabet_numbering.dart';
import 'package:test/test.dart';

void main() {
  test('list equality handles null and order', () {
    expect(ValueCollections.listsEqual(null, null), isTrue);
    expect(ValueCollections.listsEqual(null, []), isFalse);
    expect(ValueCollections.listsEqual([1, null], [1, null]), isTrue);
    expect(ValueCollections.listsEqual([1, 2], [2, 1]), isFalse);
  });
  test('unordered comparisons have order-independent hashes', () {
    final a = <Object?, Object?>{'a': null, 'b': 2};
    final b = <Object?, Object?>{'b': 2, 'a': null};
    expect(ValueCollections.mapsEqual(a, b), isTrue);
    expect(ValueCollections.mapHash(a), ValueCollections.mapHash(b));
    expect(ValueCollections.mapsEqual({'a': null}, {'b': null}), isFalse);
    expect(ValueCollections.setsEqual({1, 2, 3}, {3, 1, 2}), isTrue);
    expect(ValueCollections.setHash({1, 2, 3}),
        ValueCollections.setHash({3, 1, 2}));
  });
  test(
      'bijective numbering crosses digit boundaries and validates its alphabet',
      () {
    final alphabet = List.generate(26, (i) => String.fromCharCode(65 + i));
    for (final item in {
      1: 'A',
      26: 'Z',
      27: 'AA',
      52: 'AZ',
      702: 'ZZ',
      703: 'AAA'
    }.entries) {
      expect(CraftAlphabetNumbering.toAlphabetNumber(item.key, alphabet),
          item.value);
    }
    expect(CraftAlphabetNumbering.toAlphabetNumber(3, ['x']), 'xxx');
    expect(() => CraftAlphabetNumbering.toAlphabetNumber(1, []),
        throwsArgumentError);
    expect(() => CraftAlphabetNumbering.toAlphabetNumber(0, alphabet),
        throwsArgumentError);
  });
}
