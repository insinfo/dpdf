import 'pdf_dictionary.dart';
import 'pdf_object_wrapper.dart';
import 'pdf_name.dart';
import 'pdf_document.dart';
import 'pdf_string.dart';
import 'pdf_array.dart';
import 'pdf_number.dart';
import '../colors/color.dart';
import 'action/pdf_action.dart';
import 'navigation/pdf_destination.dart';
import 'colorspace/pdf_color_space.dart';
import 'pdf_object.dart';

/// Document outline object.
/// See ISO-320001, 12.3.3 Document Outline.
class PdfOutline extends PdfObjectWrapper<PdfDictionary> {
  /// A flag for displaying the outline item’s text with italic font.
  static const int flagItalic = 1;

  /// A flag for displaying the outline item’s text with bold font.
  static const int flagBold = 2;

  final List<PdfOutline> _children = [];
  String? _title;
  PdfDestination? _destination;
  PdfOutline? _parent;
  final PdfDocument? _pdfDoc;

  // Internal constructors

  PdfOutline._child(String title, PdfDictionary content, PdfOutline parent, {bool makeIndirect = true})
      : _title = title,
        _parent = parent,
        _pdfDoc = parent._pdfDoc,
        super(content) {
    if (makeIndirect && parent._pdfDoc != null) {
      content.makeIndirect(parent._pdfDoc);
    }
  }

  /// This constructor creates root outline in the document.
  PdfOutline.createRoot(PdfDocument doc)
      : _pdfDoc = doc,
        super(PdfDictionary()) {
    getPdfObject().put(PdfName.type, PdfName.outlines);
    getPdfObject().makeIndirect(doc);
    doc.getCatalog().put(PdfName.outlines, getPdfObject());
  }

  /// Wrap existing dictionary
  PdfOutline.wrap(PdfDictionary content, PdfDocument? pdfDocument)
      : _pdfDoc = pdfDocument,
        super(content) {
    final titleObj = content.getMap()?[PdfName.title];
    if (titleObj is PdfString) {
      _title = titleObj.toUnicodeString();
    } else if (titleObj is PdfIndirectReference) {
      final resolved = titleObj.getRefersToSync();
      if (resolved is PdfString) {
        _title = resolved.toUnicodeString();
      }
    }
  }

  @override
  bool isWrappedObjectMustBeIndirect() => true;

  /// Gets title of the outline.
  String? getTitle() {
    return _title;
  }

  /// Sets title of the outline with [PdfEncodings.unicodeBig] encoding.
  void setTitle(String title) {
    _title = title;
    getPdfObject().put(PdfName.title, PdfString(title));
  }

  /// Sets color for the outline entry’s text.
  void setColor(Color color) {
    getPdfObject().put(PdfName.c, PdfArray.fromDoubles(color.getColorValue()));
  }

  /// Gets color for the outline entry's text.
  Future<Color?> getColor() async {
    final colorArray = await getPdfObject().getAsArray(PdfName.c);
    if (colorArray == null) {
      return null;
    }
    final floats = <double>[];
    for (int i = 0; i < colorArray.size(); i++) {
      final n = await colorArray.getAsNumber(i);
      if (n != null) floats.add(n.getValue());
    }
    final cs = await PdfColorSpace.makeColorSpace(PdfName.deviceRgb);
    if (cs != null) {
      return Color.makeColor(cs, floats);
    }
    return null;
  }

  /// Sets text style for the outline entry’s text.
  void setStyle(int style) {
    if (style == flagBold || style == flagItalic) {
      getPdfObject().put(PdfName.f, PdfNumber.fromInt(style));
    }
  }

  /// Gets text style for the outline entry's text.
  Future<int?> getStyle() async {
    return await getPdfObject().getAsInt(PdfName.f);
  }

  /// Gets content dictionary.
  PdfDictionary getContent() {
    return getPdfObject();
  }

  /// Gets list of children outlines.
  List<PdfOutline> getAllChildren() {
    return _children;
  }

  /// Gets parent outline.
  PdfOutline? getParent() {
    return _parent;
  }

  /// Gets [PdfDestination].
  PdfDestination? getDestination() {
    return _destination;
  }

  /// Adds [PdfDestination] for the outline.
  void addDestination(PdfDestination destination) {
    setDestination(destination);
    getPdfObject().put(PdfName.dest, destination.getPdfObject());
    
    // Register this outline with the catalog for page removal tracking
    if (_pdfDoc != null && destination is PdfExplicitDestination) {
      final destArray = destination.getPdfObject() as PdfArray;
      if (!destArray.isEmpty()) {
        final pageRef = destArray.toList()[0];
        if (pageRef is PdfIndirectReference) {
          final pageObj = pageRef.getRefersToSync();
          if (pageObj != null) {
            _pdfDoc.getCatalog().registerOutlineWithPage(this, pageObj);
          }
        }
      }
    }
  }

  /// Adds [PdfAction] for the outline.
  Future<void> addAction(PdfAction action) async {
    final actionType = await action.getPdfObject().getAsName(PdfName.s);
    if (PdfName.goTo == actionType) {
      final d = await action.getPdfObject().get(PdfName.d); // Destination
      if (d != null) {
        final dest = await PdfDestination.makeDestination(d);
        if (dest != null) setDestination(dest);
      }
    }
    getPdfObject().put(PdfName.a, action.getPdfObject());
  }

  void setOpen(bool open) {
    if (!open) {
      getPdfObject().put(PdfName.count, PdfNumber.fromInt(-1));
    } else {
      if (_children.isNotEmpty) {
        getPdfObject().put(PdfName.count, PdfNumber.fromInt(_children.length));
      } else {
        getPdfObject().remove(PdfName.count);
      }
    }
  }

  Future<bool> isOpen() async {
    final count = await getPdfObject().getAsInt(PdfName.count);
    return count == null || count >= 0;
  }

  /// Adds a new [PdfOutline] as a child.
  Future<PdfOutline> addOutline(String title, {int position = -1}) async {
    if (position == -1) {
      position = _children.length;
    }
    final dictionary = PdfDictionary();
    final outline = PdfOutline._child(title, dictionary, this);

    dictionary.put(PdfName.title, PdfString(title));
    dictionary.put(PdfName.parent, getPdfObject());

    if (_children.isNotEmpty) {
      if (position != 0) {
        final prevContent = _children[position - 1].getContent();
        dictionary.put(PdfName.prev, prevContent);
        prevContent.put(PdfName.next, dictionary);
      }
      if (position != _children.length) {
        final nextContent = _children[position].getContent();
        dictionary.put(PdfName.next, nextContent);
        nextContent.put(PdfName.prev, dictionary);
      }
    }

    if (position == 0) {
      getPdfObject().put(PdfName.first, dictionary);
    }
    if (position == _children.length) {
      getPdfObject().put(PdfName.last, dictionary);
    }

    final count = await getPdfObject().getAsNumber(PdfName.count);
    if (count == null || count.getValue() != -1) {
      getPdfObject()
          .put(PdfName.count, PdfNumber.fromInt(_children.length + 1));
    }

    _children.insert(position, outline);
    return outline;
  }

  void setDestination(PdfDestination destination) {
    _destination = destination;
  }

  /// Removes this outline from the hierarchy and marks it as free.
  void removeOutline() {
    final parent = _parent;
    if (parent != null) {
      final index = parent._children.indexOf(this);
      if (index == -1) return;

      parent._children.removeAt(index);
      final parentContent = parent.getContent();

      if (parent._children.isEmpty) {
        parentContent.remove(PdfName.first);
        parentContent.remove(PdfName.last);
        parentContent.remove(PdfName.count);
      } else {
        final first = parentContent.getMap()?[PdfName.first];
        if (first == getPdfObject()) {
          parentContent.put(PdfName.first, parent._children[0].getContent());
        }
        final last = parentContent.getMap()?[PdfName.last];
        if (last == getPdfObject()) {
          parentContent.put(
              PdfName.last, parent._children[parent._children.length - 1].getContent());
        }
        final count = parentContent.getMap()?[PdfName.count];
        if (count is PdfNumber && count.intValue() > 0) {
          parentContent.put(PdfName.count, PdfNumber.fromInt(parent._children.length));
        }

        if (index > 0) {
          // Link previous child to the next child
          final prevChild = parent._children[index - 1];
          if (index < parent._children.length) {
            prevChild.getContent().put(PdfName.next, parent._children[index].getContent());
          } else {
            prevChild.getContent().remove(PdfName.next);
          }
        }

        if (index < parent._children.length) {
          // Link next child to the previous child
          final nextChild = parent._children[index];
          if (index > 0) {
            nextChild.getContent().put(PdfName.prev, parent._children[index - 1].getContent());
          } else {
            nextChild.getContent().remove(PdfName.prev);
          }
        }
      }

      final ref = getPdfObject().getIndirectReference();
      if (ref != null) {
        ref.setState(PdfObject.free);
      }
    }
  }

  /// Clears children.
  void clear() {
    _children.clear();
  }
}
