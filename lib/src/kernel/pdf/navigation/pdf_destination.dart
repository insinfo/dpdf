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
abstract class PdfDestination extends PdfObjectWrapper<PdfObject> {
  PdfDestination(PdfObject pdfObject) : super(pdfObject);

  Future<PdfObject?> getDestinationPage(PdfNameTreeAccess names);

  /// Creates a PdfDestination from a PdfObject.
  static Future<PdfDestination?> makeDestination(PdfObject pdfObject,
      {bool throwException = true}) async {
    if (pdfObject.objectKind() == PdfObjectType.string) {
      return PdfStringDestination(pdfObject as PdfString);
    } else if (pdfObject.objectKind() == PdfObjectType.name) {
      return PdfNamedDestination(pdfObject as PdfName);
    } else if (pdfObject.objectKind() == PdfObjectType.array) {
      final destArray = pdfObject as PdfArray;
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
          final dict = firstObj as PdfDictionary;
          final type = await dict.nameEntry(PdfName.type);
          if (PdfName.page == type) {
            return PdfExplicitDestination(destArray);
          }
        }
        // Fallback or structure
        // return PdfStructureDestination(destArray);
        return PdfExplicitDestination(destArray); // Assuming explicit for now
      }
    } else {
      if (throwException) {
        throw UnsupportedError("Unsupported destination object type");
      }
    }
    return null;
  }
}

class PdfStringDestination extends PdfDestination {
  PdfStringDestination(PdfString super.pdfObject);

  PdfStringDestination.fromString(String s) : super(PdfString(s));

  @override
  Future<PdfObject?> getDestinationPage(PdfNameTreeAccess names) async {
    final destination = await names.getEntry(pdfRepresentation() as PdfString);
    if (destination is PdfArray) {
      return await destination.get(0);
    } else if (destination is PdfDictionary) {
      final d = await destination.arrayEntry(PdfName.d);
      return await d?.get(0);
    }
    return null;
  }

  @override
  bool requiresIndirectStorage() => false;
}

class PdfNamedDestination extends PdfDestination {
  PdfNamedDestination(PdfName super.pdfObject);

  PdfNamedDestination.fromName(String name) : super(PdfName(name));

  @override
  Future<PdfObject?> getDestinationPage(PdfNameTreeAccess names) async {
    final name = pdfRepresentation() as PdfName;
    // Map Name to String for lookup if NameTree uses strings?
    // The C# code does names.GetEntry(name.GetValue());
    // IPdfNameTreeAccess has getEntryAsString(String key);
    final entry = await names.getEntryAsString(name.getValue());
    if (entry is PdfArray) {
      return await entry.get(0);
    }
    return null;
  }

  @override
  bool requiresIndirectStorage() => false;
}

class PdfExplicitDestination extends PdfDestination {
  PdfExplicitDestination(PdfArray super.pdfObject);

  PdfExplicitDestination.empty() : super(PdfArray());

  @override
  Future<PdfObject?> getDestinationPage(PdfNameTreeAccess names) async {
    return await (pdfRepresentation() as PdfArray).get(0);
  }

  @override
  bool requiresIndirectStorage() => false;

  // Factory methods for creating explicit destinations
  static PdfExplicitDestination createXYZ(
      PdfPage page, double left, double top, double zoom) {
    return _create(page, PdfName.xyz, left, double.nan, double.nan, top, zoom);
  }

  static PdfExplicitDestination createFit(PdfPage page) {
    return _create(page, PdfName.fit, double.nan, double.nan, double.nan,
        double.nan, double.nan);
  }

  // ... other factory methods (FitH, FitV, etc) can be added as needed

  static PdfExplicitDestination _create(PdfPage page, PdfName type, double left,
      double bottom, double right, double top, double zoom) {
    final dest = PdfExplicitDestination.empty();
    dest._addPage(page);
    dest._addName(type);
    dest._addNumber(left);
    dest._addNumber(bottom);
    dest._addNumber(right);
    dest._addNumber(top);
    dest._addNumber(zoom);
    return dest;
  }

  void _addPage(PdfPage page) {
    (pdfRepresentation() as PdfArray)
        .add(page.pdfRepresentation().indirectHandle()!);
  }

  void _addName(PdfName name) {
    (pdfRepresentation() as PdfArray).add(name);
  }

  void _addNumber(double val) {
    if (!val.isNaN) {
      (pdfRepresentation() as PdfArray).add(PdfNumber(val));
    }
  }
}
