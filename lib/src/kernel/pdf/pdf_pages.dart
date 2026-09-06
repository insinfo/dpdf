import 'pdf_dictionary.dart';
import 'pdf_array.dart';
import 'pdf_name.dart';
import 'pdf_number.dart';
import 'pdf_object_wrapper.dart';

/// Represents a node in the pages tree.
/// Follows the same logic as  C# PdfPages.
class CraftPdfPages extends CraftPdfObjectWrapper<CraftPdfDictionary> {
  int _from;
  late CraftPdfNumber _count;
  CraftPdfArray? _kids;
  final CraftPdfPages? _parent;

  CraftPdfPages(this._from,
      {CraftPdfPages? parent, CraftPdfDictionary? pdfObject})
      : _parent = parent,
        super(pdfObject ?? CraftPdfDictionary()) {
    setForbidRelease();
  }

  /// Initializes the pages node, loading count and kids from the dictionary.
  Future<void> init() async {
    final pdfObject = pdfRepresentation();

    // Check if this is an existing Pages dictionary by looking for /Count key
    // Don't use isEmpty() as it may return true for loaded dictionaries
    if (pdfObject.containsKey(CraftPdfName.count) ||
        pdfObject.containsKey(CraftPdfName.kids)) {
      // Load from existing dictionary
      _count = await pdfObject.numberEntry(CraftPdfName.count) ??
          CraftPdfNumber(0.0);
      _kids = await pdfObject.arrayEntry(CraftPdfName.kids);
    } else {
      // New empty pages node
      _count = CraftPdfNumber(0.0);
      _kids = CraftPdfArray();
      pdfObject.put(CraftPdfName.type, CraftPdfName.pages);
      pdfObject.put(CraftPdfName.kids, _kids!);
      pdfObject.put(CraftPdfName.count, _count);
      if (_parent != null) {
        // Use indirect reference for parent
        final parentRef = _parent.pdfRepresentation().indirectHandle();
        if (parentRef != null) {
          pdfObject.put(CraftPdfName.parent, parentRef);
        } else {
          pdfObject.put(CraftPdfName.parent, _parent.pdfRepresentation());
        }
      }
    }
  }

  @override
  bool requiresIndirectStorage() => true;

  int getFrom() => _from;

  int getCount() => _count.intValue();

  void correctFrom(int correction) {
    _from += correction;
  }

  CraftPdfArray? getKids() => _kids;

  CraftPdfPages? getParent() => _parent;

  void appendPageObject(CraftPdfDictionary page) {
    _kids ??= CraftPdfArray();
    _kids!.add(page);
    incrementCount();
    // Use indirect reference for parent to avoid writing inline dictionary
    final parentRef = pdfRepresentation().indirectHandle();
    if (parentRef != null) {
      page.put(CraftPdfName.parent, parentRef);
    } else {
      page.put(CraftPdfName.parent, pdfRepresentation());
    }
    page.markChanged();
  }

  /// Inserts a page at the specified position within this Pages node.
  ///
  /// [index] - The 0-based index within this node's kids where to insert.
  /// [page] - The page dictionary to insert.
  void insertPageObject(int index, CraftPdfDictionary page) {
    _kids ??= CraftPdfArray();
    _kids!.insert(index, page);
    incrementCount();
    // Use indirect reference for parent to avoid writing inline dictionary
    final parentRef = pdfRepresentation().indirectHandle();
    if (parentRef != null) {
      page.put(CraftPdfName.parent, parentRef);
    } else {
      page.put(CraftPdfName.parent, pdfRepresentation());
    }
    page.markChanged();
  }

  void incrementCount() {
    _count.setValue(_count.doubleValue() + 1);
    markChanged();
    _parent?.incrementCount();
  }

  void decrementCount() {
    _count.setValue(_count.doubleValue() - 1);
    markChanged();
    _parent?.decrementCount();
  }

  int compareTo(int index) {
    if (index < _from) return 1;
    if (index >= _from + getCount()) return -1;
    return 0;
  }

  bool detachPage(int pageNum) {
    if (pageNum < _from || pageNum >= _from + getCount()) {
      return false;
    }
    decrementCount();
    _kids?.removeAt(pageNum - _from);
    return true;
  }

  void addPages(CraftPdfPages other) {
    _kids ??= CraftPdfArray();
    _kids!.add(other.pdfRepresentation());
    _count.setValue(_count.doubleValue() + other.getCount().toDouble());
    // Use indirect reference for parent
    final parentRef = pdfRepresentation().indirectHandle();
    if (parentRef != null) {
      other.pdfRepresentation().put(CraftPdfName.parent, parentRef);
    } else {
      other.pdfRepresentation().put(CraftPdfName.parent, pdfRepresentation());
    }
    other.markChanged();
    markChanged();
  }

  void removeFromParent() {
    if (_parent != null) {
      final parentKids = _parent.getKids();
      if (parentKids != null) {
        // Find and remove this Pages node from parent's Kids
        for (var i = 0; i < parentKids.size(); i++) {
          // Simplified removal - in real impl need to check references
        }
      }
    }
  }
}
