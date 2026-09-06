import 'pdf_dictionary.dart';
import 'pdf_array.dart';
import 'pdf_name.dart';
import 'pdf_number.dart';
import 'pdf_object_wrapper.dart';

/// Represents a node in the pages tree.
/// Follows the same logic as  C# PdfPages.
class PdfPages extends PdfObjectWrapper<PdfDictionary> {
  int _from;
  late PdfNumber _count;
  PdfArray? _kids;
  final PdfPages? _parent;

  PdfPages(this._from, {PdfPages? parent, PdfDictionary? pdfObject})
      : _parent = parent,
        super(pdfObject ?? PdfDictionary()) {
    setForbidRelease();
  }

  /// Initializes the pages node, loading count and kids from the dictionary.
  Future<void> init() async {
    final pdfObject = getPdfObject();

    // Check if this is an existing Pages dictionary by looking for /Count key
    // Don't use isEmpty() as it may return true for loaded dictionaries
    if (pdfObject.containsKey(PdfName.count) ||
        pdfObject.containsKey(PdfName.kids)) {
      // Load from existing dictionary
      _count = await pdfObject.getAsNumber(PdfName.count) ?? PdfNumber(0.0);
      _kids = await pdfObject.getAsArray(PdfName.kids);
    } else {
      // New empty pages node
      _count = PdfNumber(0.0);
      _kids = PdfArray();
      pdfObject.put(PdfName.type, PdfName.pages);
      pdfObject.put(PdfName.kids, _kids!);
      pdfObject.put(PdfName.count, _count);
      if (_parent != null) {
        // Use indirect reference for parent
        final parentRef = _parent.getPdfObject().getIndirectReference();
        if (parentRef != null) {
          pdfObject.put(PdfName.parent, parentRef);
        } else {
          pdfObject.put(PdfName.parent, _parent.getPdfObject());
        }
      }
    }
  }

  @override
  bool isWrappedObjectMustBeIndirect() => true;

  int getFrom() => _from;

  int getCount() => _count.intValue();

  void correctFrom(int correction) {
    _from += correction;
  }

  PdfArray? getKids() => _kids;

  PdfPages? getParent() => _parent;

  void addPage(PdfDictionary page) {
    _kids ??= PdfArray();
    _kids!.add(page);
    incrementCount();
    // Use indirect reference for parent to avoid writing inline dictionary
    final parentRef = getPdfObject().getIndirectReference();
    if (parentRef != null) {
      page.put(PdfName.parent, parentRef);
    } else {
      page.put(PdfName.parent, getPdfObject());
    }
    page.setModified();
  }

  /// Inserts a page at the specified position within this Pages node.
  ///
  /// [index] - The 0-based index within this node's kids where to insert.
  /// [page] - The page dictionary to insert.
  void addPageAt(int index, PdfDictionary page) {
    _kids ??= PdfArray();
    _kids!.insert(index, page);
    incrementCount();
    // Use indirect reference for parent to avoid writing inline dictionary
    final parentRef = getPdfObject().getIndirectReference();
    if (parentRef != null) {
      page.put(PdfName.parent, parentRef);
    } else {
      page.put(PdfName.parent, getPdfObject());
    }
    page.setModified();
  }

  void incrementCount() {
    _count.setValue(_count.doubleValue() + 1);
    setModified();
    _parent?.incrementCount();
  }

  void decrementCount() {
    _count.setValue(_count.doubleValue() - 1);
    setModified();
    _parent?.decrementCount();
  }

  int compareTo(int index) {
    if (index < _from) return 1;
    if (index >= _from + getCount()) return -1;
    return 0;
  }

  bool removePage(int pageNum) {
    if (pageNum < _from || pageNum >= _from + getCount()) {
      return false;
    }
    decrementCount();
    _kids?.removeAt(pageNum - _from);
    return true;
  }

  void addPages(PdfPages other) {
    _kids ??= PdfArray();
    _kids!.add(other.getPdfObject());
    _count.setValue(_count.doubleValue() + other.getCount().toDouble());
    // Use indirect reference for parent
    final parentRef = getPdfObject().getIndirectReference();
    if (parentRef != null) {
      other.getPdfObject().put(PdfName.parent, parentRef);
    } else {
      other.getPdfObject().put(PdfName.parent, getPdfObject());
    }
    other.setModified();
    setModified();
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
