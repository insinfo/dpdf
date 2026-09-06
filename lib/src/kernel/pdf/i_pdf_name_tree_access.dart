import 'pdf_object.dart';
import 'pdf_string.dart';

/// Abstract access interface to a PDF name tree.
abstract class IPdfNameTreeAccess {
  /// Retrieve an entry from the name tree.
  Future<PdfObject?> getEntry(PdfString key);

  /// Retrieve an entry from the name tree by String.
  Future<PdfObject?> getEntryAsString(String key);

  /// Retrieve the set of keys in the name tree.
  Future<List<PdfString>> getKeys();
}
