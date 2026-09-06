import 'dart:convert';
import 'dart:typed_data';
import '../commons/xml/xml.dart';
export '../commons/xml/xml.dart';

import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_document.dart';
import '../kernel/pdf/pdf_object.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_stream.dart';
import '../kernel/pdf/pdf_string.dart';
import 'pdf_acro_form.dart';

/// Processes XFA forms.
class CraftXfaForm {
  XmlElement? _templateNode;
  XmlElement? _datasetsNode; // Represents xfa:datasets
  XmlDocument? _domDocument;
  bool _xfaPresent = false;

  /// The URI for the XFA Data schema.
  static const String XFA_DATA_SCHEMA =
      "http://www.xfa.org/schema/xfa-data/1.0/";

  /// Private constructor. Use static create methods.
  CraftXfaForm._();

  /// Creates a new empty XfaForm.
  static CraftXfaForm create() {
    CraftXfaForm form = CraftXfaForm._();
    form._domDocument = XmlDocument.parse(
        '<?xml version="1.0" encoding="UTF-8"?><xdp:xdp xmlns:xdp="http://ns.adobe.com/xdp/"><template xmlns="http://www.xfa.org/schema/xfa-template/3.3/"></template><xfa:datasets xmlns:xfa="http://www.xfa.org/schema/xfa-data/1.0/"><xfa:data></xfa:data></xfa:datasets></xdp:xdp>');
    form._extractNodes();
    form._xfaPresent = true;
    return form;
  }

  /// Creates an XFA form from an XmlDocument.
  static CraftXfaForm createFromXml(XmlDocument domDocument) {
    CraftXfaForm form = CraftXfaForm._();
    form.setDomDocument(domDocument);
    return form;
  }

  /// Creates an XFA form from a [PdfDictionary] (AcroForm dictionary).
  static Future<CraftXfaForm> createFromPdfDictionary(
      CraftPdfDictionary acroFormDictionary) async {
    CraftXfaForm form = CraftXfaForm._();
    CraftPdfObject? xfa = await acroFormDictionary.get(CraftPdfName.xfa);
    if (xfa != null) {
      await form._initXfaForm(xfa);
    }
    return form;
  }

  /// Creates an XFA form from a [PdfDocument].
  static Future<CraftXfaForm> createFromDocument(
      CraftPdfDocument pdfDocument) async {
    CraftXfaForm form = CraftXfaForm._();
    CraftPdfObject? xfa = await _getXfaObject(pdfDocument);
    if (xfa != null) {
      await form._initXfaForm(xfa);
    }
    return form;
  }

  /// Sets the XFA data to the AcroForm.
  static Future<void> setXfaFormWithAcroForm(
      CraftXfaForm form, CraftPdfAcroForm acroForm) async {
    CraftPdfDocument document = acroForm.getPdfDocument(); // access via getter
    CraftPdfObject? xfa = await _getXfaObjectFromAcroForm(acroForm);

    // Logic to update XFA in PDF
    if (xfa != null && xfa is CraftPdfArray) {
      CraftPdfArray ar = xfa;
      int t = -1;
      int d = -1;
      for (int k = 0; k < ar.size(); k += 2) {
        CraftPdfString? s = await ar.stringEntry(k);
        if (s != null) {
          if ("template" == s.decodeMappingText()) {
            t = k + 1;
          }
          if ("datasets" == s.decodeMappingText()) {
            d = k + 1;
          }
        }
      }

      if (t > -1 &&
          d > -1 &&
          form._templateNode != null &&
          form._datasetsNode != null) {
        CraftPdfStream tStream = CraftPdfStream.withBytes(
            Uint8List.fromList(_serializeNode(form._templateNode!)));
        // tStream.setCompressionLevel(document.getWriter().getCompressionLevel()); // TODO: Implement getWriter/Compression if available
        ar.set(t, tStream);

        CraftPdfStream dStream = CraftPdfStream.withBytes(
            Uint8List.fromList(_serializeNode(form._datasetsNode!)));
        // dStream.setCompressionLevel(document.getWriter().getCompressionLevel());
        ar.set(d, dStream);

        ar.markChanged();
        acroForm.pdfRepresentation().put(CraftPdfName.xfa, ar);
        acroForm.pdfRepresentation().markChanged();
        if (!acroForm.pdfRepresentation().usesIndirectStorage()) {
          document.rootCatalog().markChanged();
        }
        return;
      }
    }

    // Default case: simple XFA stream (full DOM)
    if (form._domDocument != null) {
      CraftPdfStream stream = CraftPdfStream.withBytes(
          Uint8List.fromList(_serializeDocument(form._domDocument!)));
      // stream.setCompressionLevel(document.getWriter().getCompressionLevel());
      acroForm.pdfRepresentation().put(CraftPdfName.xfa, stream);
      acroForm.pdfRepresentation().markChanged();
      if (!acroForm.pdfRepresentation().usesIndirectStorage()) {
        document.rootCatalog().markChanged();
      }
    }
  }

  /// Get the top level DOM document.
  XmlDocument? getDomDocument() {
    return _domDocument;
  }

  /// Sets the top DOM document.
  void setDomDocument(XmlDocument domDocument) {
    _domDocument = domDocument;
    _extractNodes();
    _xfaPresent = true;
  }

  /// Returns true if it is a XFA form.
  bool isXfaPresent() {
    return _xfaPresent;
  }

  Future<void> _initXfaForm(CraftPdfObject xfa) async {
    List<int> bytes = [];

    if (xfa is CraftPdfArray) {
      CraftPdfArray ar = xfa;
      for (int k = 1; k < ar.size(); k += 2) {
        CraftPdfObject? ob = await ar.get(k);
        if (ob is CraftPdfStream) {
          Uint8List? streamBytes = await ob.getBytes();
          if (streamBytes != null) {
            bytes.addAll(streamBytes);
          }
        }
      }
    } else if (xfa is CraftPdfStream) {
      Uint8List? streamBytes = await xfa.getBytes();
      if (streamBytes != null) {
        bytes.addAll(streamBytes);
      }
    }

    if (bytes.isNotEmpty) {
      _initXfaFormFromBytes(bytes);
    }
  }

  void _initXfaFormFromBytes(List<int> bytes) {
    try {
      String xmlStr = utf8.decode(bytes);
      _domDocument = XmlDocument.parse(xmlStr);
      _extractNodes();
      _xfaPresent = true;
    } catch (e) {
      // ignore parsing errors or log? or throw?
      // throw Exception("Error parsing XFA XML: $e");
      print("Error parsing XFA XML: $e");
    }
  }

  void _extractNodes() {
    _templateNode = null;
    _datasetsNode = null;
    if (_domDocument == null) return;

    var xfaNodes = _extractXfaNodes(_domDocument!);

    if (xfaNodes.containsKey("template")) {
      _templateNode = xfaNodes["template"] as XmlElement?;
    }

    if (xfaNodes.containsKey("datasets")) {
      _datasetsNode = xfaNodes["datasets"] as XmlElement?;
    }
  }

  Map<String, XmlNode> _extractXfaNodes(XmlDocument doc) {
    Map<String, XmlNode> xfaNodes = {};
    XmlElement? root = doc.rootElement;

    for (var child in root.children) {
      if (child is XmlElement) {
        xfaNodes[child.name.local] = child;
      }
    }
    return xfaNodes;
  }

  static Future<CraftPdfObject?> _getXfaObject(
      CraftPdfDocument pdfDocument) async {
    CraftPdfDictionary? af = await pdfDocument
        .rootCatalog()
        .pdfRepresentation()
        .dictionaryEntry(CraftPdfName.acroForm);
    return af?.get(CraftPdfName.xfa);
  }

  static Future<CraftPdfObject?> _getXfaObjectFromAcroForm(
      CraftPdfAcroForm acroForm) async {
    return await acroForm.pdfRepresentation().get(CraftPdfName.xfa);
  }

  static List<int> _serializeDocument(XmlDocument doc) {
    return utf8.encode(doc.toXmlString());
  }

  static List<int> _serializeNode(XmlNode node) {
    return utf8.encode(node.toXmlString());
  }
}
