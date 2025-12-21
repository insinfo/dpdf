import 'pdf_dictionary.dart';
import 'pdf_array.dart';
import 'pdf_name.dart';
import 'pdf_number.dart';
import 'pdf_object_wrapper.dart';

/// Represents a node in the pages tree.
class PdfPages extends PdfObjectWrapper<PdfDictionary> {
  int _from;
  late PdfNumber _count;
  late PdfArray _kids;
  final PdfPages? _parent;

  PdfPages(this._from, {PdfPages? parent, PdfDictionary? pdfObject})
      : _parent = parent,
        super(pdfObject ?? PdfDictionary()) {
    setForbidRelease();
  }

  /// Initializes the pages node, loading count and kids from the dictionary.
  Future<void> init() async {
    final pdfObject = getPdfObject();
    if (pdfObject.isEmpty()) {
      _count = PdfNumber(0.0);
      _kids = PdfArray();
      pdfObject.put(PdfName.type, PdfName.pages);
      pdfObject.put(PdfName.kids, _kids);
      pdfObject.put(PdfName.count, _count);
      if (_parent != null) {
        pdfObject.put(PdfName.parent, _parent.getPdfObject());
      }
    } else {
      _count = await pdfObject.getAsNumber(PdfName.count) ?? PdfNumber(0.0);
      _kids = await pdfObject.getAsArray(PdfName.kids) ?? PdfArray();
      pdfObject.put(PdfName.type, PdfName.pages);
    }
  }

  @override
  bool isWrappedObjectMustBeIndirect() => true;

  int getFrom() => _from;
  int getCount() => _count.intValue();

  void correctFrom(int correction) {
    _from += correction;
  }

  PdfArray getKids() => _kids;
  PdfPages? getParent() => _parent;

  void addPage(PdfDictionary page) {
    _kids.add(page);
    incrementCount();
    page.put(PdfName.parent, getPdfObject());
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
    _kids.removeAt(pageNum - _from);
    return true;
  }

  void addPages(PdfPages other) {
    _kids.add(other.getPdfObject());
    _count.setValue(_count.doubleValue() + other.getCount().toDouble());
    other.getPdfObject().put(PdfName.parent, getPdfObject());
    other.setModified();
    setModified();
  }
}
