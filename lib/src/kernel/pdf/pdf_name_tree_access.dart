import 'pdf_object.dart';
import 'pdf_string.dart';

/// Abstract access interface to a PDF name tree.
abstract class CraftPdfNameTreeAccess {
  /// Retrieve an entry from the name tree.
  Future<CraftPdfObject?> getEntry(CraftPdfString key);

  /// Retrieve an entry from the name tree by String.
  Future<CraftPdfObject?> getEntryAsString(String key);

  /// Retrieve the set of keys in the name tree.
  Future<List<CraftPdfString>> getKeys();
}
