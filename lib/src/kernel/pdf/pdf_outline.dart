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
class CraftPdfOutline extends CraftPdfObjectWrapper<CraftPdfDictionary> {
  /// Displays the outline label in italics.
  static const int flagItalic = 1;

  /// Displays the outline label in bold.
  static const int flagBold = 2;

  final List<CraftPdfOutline> _children = [];
  String? _title;
  CraftPdfDestination? _destination;
  CraftPdfOutline? _parent;
  final CraftPdfDocument? _pdfDoc;

  // Internal constructors

  CraftPdfOutline._child(
      String title, CraftPdfDictionary content, CraftPdfOutline parent,
      {bool attachToDocument = true})
      : _title = title,
        _parent = parent,
        _pdfDoc = parent._pdfDoc,
        super(content) {
    if (attachToDocument && parent._pdfDoc != null) {
      content.attachToDocument(parent._pdfDoc);
    }
  }

  /// This constructor creates root outline in the document.
  CraftPdfOutline.createRoot(CraftPdfDocument doc)
      : _pdfDoc = doc,
        super(CraftPdfDictionary()) {
    pdfRepresentation().put(CraftPdfName.type, CraftPdfName.outlines);
    pdfRepresentation().attachToDocument(doc);
    doc.rootCatalog().put(CraftPdfName.outlines, pdfRepresentation());
  }

  /// Wrap existing dictionary
  CraftPdfOutline.wrap(
      CraftPdfDictionary content, CraftPdfDocument? pdfDocument)
      : _pdfDoc = pdfDocument,
        super(content) {
    final titleObj = content.getMap()?[CraftPdfName.title];
    if (titleObj is CraftPdfString) {
      _title = titleObj.decodeMappingText();
    } else if (titleObj is CraftPdfIndirectReference) {
      final resolved = titleObj.targetObjectSync();
      if (resolved is CraftPdfString) {
        _title = resolved.decodeMappingText();
      }
    }
  }

  @override
  bool requiresIndirectStorage() => true;

  /// Gets title of the outline.
  String? getTitle() {
    return _title;
  }

  /// Sets title of the outline with [PdfEncodings.unicodeBig] encoding.
  void setTitle(String title) {
    _title = title;
    pdfRepresentation().put(CraftPdfName.title, CraftPdfString(title));
  }

  /// Sets color for the outline entry’s text.
  void setColor(CraftColor color) {
    pdfRepresentation()
        .put(CraftPdfName.c, CraftPdfArray.fromDoubles(color.getColorValue()));
  }

  /// Gets color for the outline entry's text.
  Future<CraftColor?> getColor() async {
    final colorArray = await pdfRepresentation().arrayEntry(CraftPdfName.c);
    if (colorArray == null) {
      return null;
    }
    final floats = <double>[];
    for (int i = 0; i < colorArray.size(); i++) {
      final n = await colorArray.numberEntry(i);
      if (n != null) floats.add(n.getValue());
    }
    final cs = await CraftPdfColorSpace.makeColorSpace(CraftPdfName.deviceRgb);
    if (cs != null) {
      return CraftColor.makeColor(cs, floats);
    }
    return null;
  }

  /// Sets text style for the outline entry’s text.
  void setStyle(int style) {
    if (style == flagBold || style == flagItalic) {
      pdfRepresentation().put(CraftPdfName.f, CraftPdfNumber.fromInt(style));
    }
  }

  /// Gets text style for the outline entry's text.
  Future<int?> getStyle() async {
    return await pdfRepresentation().integerEntry(CraftPdfName.f);
  }

  /// Gets content dictionary.
  CraftPdfDictionary getContent() {
    return pdfRepresentation();
  }

  /// Gets list of children outlines.
  List<CraftPdfOutline> getAllChildren() {
    return _children;
  }

  /// Gets parent outline.
  CraftPdfOutline? getParent() {
    return _parent;
  }

  /// Gets [PdfDestination].
  CraftPdfDestination? getDestination() {
    return _destination;
  }

  /// Adds [PdfDestination] for the outline.
  void addDestination(CraftPdfDestination destination) {
    setDestination(destination);
    pdfRepresentation().put(CraftPdfName.dest, destination.pdfRepresentation());

    // Register this outline with the catalog for page removal tracking
    if (_pdfDoc != null && destination is CraftPdfExplicitDestination) {
      final destArray = destination.pdfRepresentation() as CraftPdfArray;
      if (!destArray.isEmpty()) {
        final pageRef = destArray.toList()[0];
        if (pageRef is CraftPdfIndirectReference) {
          final pageObj = pageRef.targetObjectSync();
          if (pageObj != null) {
            _pdfDoc.rootCatalog().registerOutlineWithPage(this, pageObj);
          }
        }
      }
    }
  }

  /// Adds [PdfAction] for the outline.
  Future<void> addAction(CraftPdfAction action) async {
    final actionType =
        await action.pdfRepresentation().nameEntry(CraftPdfName.s);
    if (CraftPdfName.goTo == actionType) {
      final d =
          await action.pdfRepresentation().get(CraftPdfName.d); // Destination
      if (d != null) {
        final dest = await CraftPdfDestination.makeDestination(d);
        if (dest != null) setDestination(dest);
      }
    }
    pdfRepresentation().put(CraftPdfName.a, action.pdfRepresentation());
  }

  void setOpen(bool open) {
    if (!open) {
      pdfRepresentation().put(CraftPdfName.count, CraftPdfNumber.fromInt(-1));
    } else {
      if (_children.isNotEmpty) {
        pdfRepresentation()
            .put(CraftPdfName.count, CraftPdfNumber.fromInt(_children.length));
      } else {
        pdfRepresentation().remove(CraftPdfName.count);
      }
    }
  }

  Future<bool> isOpen() async {
    final count = await pdfRepresentation().integerEntry(CraftPdfName.count);
    return count == null || count >= 0;
  }

  /// Adds a new [PdfOutline] as a child.
  Future<CraftPdfOutline> addOutline(String title, {int position = -1}) async {
    if (position == -1) {
      position = _children.length;
    }
    final dictionary = CraftPdfDictionary();
    final outline = CraftPdfOutline._child(title, dictionary, this);

    dictionary.put(CraftPdfName.title, CraftPdfString(title));
    dictionary.put(CraftPdfName.parent, pdfRepresentation());

    if (_children.isNotEmpty) {
      if (position != 0) {
        final prevContent = _children[position - 1].getContent();
        dictionary.put(CraftPdfName.prev, prevContent);
        prevContent.put(CraftPdfName.next, dictionary);
      }
      if (position != _children.length) {
        final nextContent = _children[position].getContent();
        dictionary.put(CraftPdfName.next, nextContent);
        nextContent.put(CraftPdfName.prev, dictionary);
      }
    }

    if (position == 0) {
      pdfRepresentation().put(CraftPdfName.first, dictionary);
    }
    if (position == _children.length) {
      pdfRepresentation().put(CraftPdfName.last, dictionary);
    }

    final count = await pdfRepresentation().numberEntry(CraftPdfName.count);
    if (count == null || count.getValue() != -1) {
      pdfRepresentation().put(
          CraftPdfName.count, CraftPdfNumber.fromInt(_children.length + 1));
    }

    _children.insert(position, outline);
    return outline;
  }

  void setDestination(CraftPdfDestination destination) {
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
        parentContent.remove(CraftPdfName.first);
        parentContent.remove(CraftPdfName.last);
        parentContent.remove(CraftPdfName.count);
      } else {
        final first = parentContent.getMap()?[CraftPdfName.first];
        if (first == pdfRepresentation()) {
          parentContent.put(
              CraftPdfName.first, parent._children[0].getContent());
        }
        final last = parentContent.getMap()?[CraftPdfName.last];
        if (last == pdfRepresentation()) {
          parentContent.put(CraftPdfName.last,
              parent._children[parent._children.length - 1].getContent());
        }
        final count = parentContent.getMap()?[CraftPdfName.count];
        if (count is CraftPdfNumber && count.intValue() > 0) {
          parentContent.put(CraftPdfName.count,
              CraftPdfNumber.fromInt(parent._children.length));
        }

        if (index > 0) {
          // Link previous child to the next child
          final prevChild = parent._children[index - 1];
          if (index < parent._children.length) {
            prevChild
                .getContent()
                .put(CraftPdfName.next, parent._children[index].getContent());
          } else {
            prevChild.getContent().remove(CraftPdfName.next);
          }
        }

        if (index < parent._children.length) {
          // Link next child to the previous child
          final nextChild = parent._children[index];
          if (index > 0) {
            nextChild.getContent().put(
                CraftPdfName.prev, parent._children[index - 1].getContent());
          } else {
            nextChild.getContent().remove(CraftPdfName.prev);
          }
        }
      }

      final ref = pdfRepresentation().indirectHandle();
      if (ref != null) {
        ref.setState(CraftPdfObject.free);
      }
    }
  }

  /// Clears children.
  void clear() {
    _children.clear();
  }
}
