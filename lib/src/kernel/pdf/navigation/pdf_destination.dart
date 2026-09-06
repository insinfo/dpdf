import '../pdf_object_wrapper.dart';
import '../pdf_object.dart';
import '../pdf_string.dart';
import '../pdf_name.dart';
import '../pdf_array.dart';
import '../pdf_dictionary.dart';
import '../pdf_number.dart';
import '../pdf_page.dart';
import '../i_pdf_name_tree_access.dart';

/// Abstract base class for PDF destinations.
abstract class PdfDestination extends PdfObjectWrapper<PdfObject> {
  PdfDestination(PdfObject pdfObject) : super(pdfObject);

  Future<PdfObject?> getDestinationPage(IPdfNameTreeAccess names);

  /// Creates a PdfDestination from a PdfObject.
  static Future<PdfDestination?> makeDestination(PdfObject pdfObject,
      {bool throwException = true}) async {
    if (pdfObject.getObjectType() == PdfObjectType.string) {
      return PdfStringDestination(pdfObject as PdfString);
    } else if (pdfObject.getObjectType() == PdfObjectType.name) {
      return PdfNamedDestination(pdfObject as PdfName);
    } else if (pdfObject.getObjectType() == PdfObjectType.array) {
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
        if (firstObj.getObjectType() == PdfObjectType.number) {
          // TODO: PdfExplicitRemoteGoToDestination
          return null;
        }
        if (firstObj.isDictionary()) {
          final dict = firstObj as PdfDictionary;
          final type = await dict.getAsName(PdfName.type);
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
  PdfStringDestination(PdfString pdfObject) : super(pdfObject);

  PdfStringDestination.fromString(String s) : super(PdfString(s));

  @override
  Future<PdfObject?> getDestinationPage(IPdfNameTreeAccess names) async {
    final destination = await names.getEntry(getPdfObject() as PdfString);
    if (destination is PdfArray) {
      return await destination.get(0);
    } else if (destination is PdfDictionary) {
      final d = await destination.getAsArray(PdfName.d);
      return await d?.get(0);
    }
    return null;
  }

  @override
  bool isWrappedObjectMustBeIndirect() => false;
}

class PdfNamedDestination extends PdfDestination {
  PdfNamedDestination(PdfName pdfObject) : super(pdfObject);

  PdfNamedDestination.fromName(String name) : super(PdfName(name));

  @override
  Future<PdfObject?> getDestinationPage(IPdfNameTreeAccess names) async {
    final name = getPdfObject() as PdfName;
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
  bool isWrappedObjectMustBeIndirect() => false;
}

class PdfExplicitDestination extends PdfDestination {
  PdfExplicitDestination(PdfArray pdfObject) : super(pdfObject);

  PdfExplicitDestination.empty() : super(PdfArray());

  @override
  Future<PdfObject?> getDestinationPage(IPdfNameTreeAccess names) async {
    return await (getPdfObject() as PdfArray).get(0);
  }

  @override
  bool isWrappedObjectMustBeIndirect() => false;

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
    (getPdfObject() as PdfArray)
        .add(page.getPdfObject().getIndirectReference()!);
  }

  void _addName(PdfName name) {
    (getPdfObject() as PdfArray).add(name);
  }

  void _addNumber(double val) {
    if (!val.isNaN) {
      (getPdfObject() as PdfArray).add(PdfNumber(val));
    }
  }
}
