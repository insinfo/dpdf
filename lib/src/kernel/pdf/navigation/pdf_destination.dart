import '../pdf_object_wrapper.dart';
import '../pdf_object.dart';
import '../pdf_string.dart';
import '../pdf_name.dart';
import '../pdf_array.dart';
import '../pdf_dictionary.dart';
import '../pdf_number.dart';
import '../pdf_page.dart';
import '../pdf_name_tree_access.dart';

/// Abstract base class for PDF destinations.
abstract class CraftPdfDestination
    extends CraftPdfObjectWrapper<CraftPdfObject> {
  CraftPdfDestination(CraftPdfObject pdfObject) : super(pdfObject);

  Future<CraftPdfObject?> getDestinationPage(CraftPdfNameTreeAccess names);

  /// Creates a PdfDestination from a PdfObject.
  static Future<CraftPdfDestination?> makeDestination(CraftPdfObject pdfObject,
      {bool throwException = true}) async {
    if (pdfObject.objectKind() == PdfObjectType.string) {
      return CraftPdfStringDestination(pdfObject as CraftPdfString);
    } else if (pdfObject.objectKind() == PdfObjectType.name) {
      return CraftPdfNamedDestination(pdfObject as CraftPdfName);
    } else if (pdfObject.objectKind() == PdfObjectType.array) {
      final destArray = pdfObject as CraftPdfArray;
      if (destArray.isEmpty()) {
        if (throwException) {
          throw ArgumentError("Destination array cannot be empty");
        } else {
          return null;
        }
      }
      final firstObj = await destArray.get(0);
      if (firstObj != null) {
        if (firstObj.objectKind() == PdfObjectType.number) {
          // TODO: PdfExplicitRemoteGoToDestination
          return null;
        }
        if (firstObj.isDictionary()) {
          final dict = firstObj as CraftPdfDictionary;
          final type = await dict.nameEntry(CraftPdfName.type);
          if (CraftPdfName.page == type) {
            return CraftPdfExplicitDestination(destArray);
          }
        }
        // Fallback or structure
        // return PdfStructureDestination(destArray);
        return CraftPdfExplicitDestination(
            destArray); // Assuming explicit for now
      }
    } else {
      if (throwException) {
        throw UnsupportedError("Unsupported destination object type");
      }
    }
    return null;
  }
}

class CraftPdfStringDestination extends CraftPdfDestination {
  CraftPdfStringDestination(CraftPdfString super.pdfObject);

  CraftPdfStringDestination.fromString(String s) : super(CraftPdfString(s));

  @override
  Future<CraftPdfObject?> getDestinationPage(
      CraftPdfNameTreeAccess names) async {
    final destination =
        await names.getEntry(pdfRepresentation() as CraftPdfString);
    if (destination is CraftPdfArray) {
      return await destination.get(0);
    } else if (destination is CraftPdfDictionary) {
      final d = await destination.arrayEntry(CraftPdfName.d);
      return await d?.get(0);
    }
    return null;
  }

  @override
  bool requiresIndirectStorage() => false;
}

class CraftPdfNamedDestination extends CraftPdfDestination {
  CraftPdfNamedDestination(CraftPdfName super.pdfObject);

  CraftPdfNamedDestination.fromName(String name) : super(CraftPdfName(name));

  @override
  Future<CraftPdfObject?> getDestinationPage(
      CraftPdfNameTreeAccess names) async {
    final name = pdfRepresentation() as CraftPdfName;
    // Map Name to String for lookup if NameTree uses strings?
    // The C# code does names.GetEntry(name.GetValue());
    // IPdfNameTreeAccess has getEntryAsString(String key);
    final entry = await names.getEntryAsString(name.getValue());
    if (entry is CraftPdfArray) {
      return await entry.get(0);
    }
    return null;
  }

  @override
  bool requiresIndirectStorage() => false;
}

class CraftPdfExplicitDestination extends CraftPdfDestination {
  CraftPdfExplicitDestination(CraftPdfArray super.pdfObject);

  CraftPdfExplicitDestination.empty() : super(CraftPdfArray());

  @override
  Future<CraftPdfObject?> getDestinationPage(
      CraftPdfNameTreeAccess names) async {
    return await (pdfRepresentation() as CraftPdfArray).get(0);
  }

  @override
  bool requiresIndirectStorage() => false;

  // Factory methods for creating explicit destinations
  static CraftPdfExplicitDestination createXYZ(
      CraftPdfPage page, double left, double top, double zoom) {
    return _create(
        page, CraftPdfName.xyz, left, double.nan, double.nan, top, zoom);
  }

  static CraftPdfExplicitDestination createFit(CraftPdfPage page) {
    return _create(page, CraftPdfName.fit, double.nan, double.nan, double.nan,
        double.nan, double.nan);
  }

  // ... other factory methods (FitH, FitV, etc) can be added as needed

  static CraftPdfExplicitDestination _create(
      CraftPdfPage page,
      CraftPdfName type,
      double left,
      double bottom,
      double right,
      double top,
      double zoom) {
    final dest = CraftPdfExplicitDestination.empty();
    dest._addPage(page);
    dest._addName(type);
    dest._addNumber(left);
    dest._addNumber(bottom);
    dest._addNumber(right);
    dest._addNumber(top);
    dest._addNumber(zoom);
    return dest;
  }

  void _addPage(CraftPdfPage page) {
    (pdfRepresentation() as CraftPdfArray)
        .add(page.pdfRepresentation().indirectHandle()!);
  }

  void _addName(CraftPdfName name) {
    (pdfRepresentation() as CraftPdfArray).add(name);
  }

  void _addNumber(double val) {
    if (!val.isNaN) {
      (pdfRepresentation() as CraftPdfArray).add(CraftPdfNumber(val));
    }
  }
}
