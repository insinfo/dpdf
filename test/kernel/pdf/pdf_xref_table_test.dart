import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_xref_table.dart';
import 'package:test/test.dart';

void main() {
  test('clearAllReferences deixa somente a entrada obrigatória zero', () {
    final table = CraftPdfXrefTable()
      ..add(CraftPdfIndirectReference(1, 0))
      ..add(CraftPdfIndirectReference(4, 0));

    table.clearAllReferences();

    expect(table.size(), 1);
    expect(table.get(0), isNotNull);
    expect(table.get(1), isNull);
    expect(table.get(4), isNull);
  });

  test('clear conserva entradas livres acessíveis e ajusta seu limite', () {
    final table = CraftPdfXrefTable()
      ..add(CraftPdfIndirectReference(1, 0))
      ..add(CraftPdfIndirectReference(4, 0));
    table.freeReference(table.get(4)!);

    table.clear();

    expect(table.size(), 5);
    expect(table.get(1), isNull);
    expect(table.get(4)?.isFree(), isTrue);
  });
}
