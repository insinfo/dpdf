import '../pdf_object_wrapper.dart';
import '../pdf_object.dart';
import '../pdf_string.dart';
import '../pdf_name.dart';
import '../pdf_array.dart';
import '../pdf_dictionary.dart';
import '../pdf_null.dart';
import '../pdf_number.dart';
import '../pdf_page.dart';
import '../pdf_name_tree_access.dart';

/// Abstract base class for PDF destinations.
///
/// See ISO 32000-1:2008, 12.3.2 "Destinations".
abstract class PdfDestination extends PdfObjectWrapper<PdfObject> {
  PdfDestination(super.pdfObject);

  Future<PdfObject?> getDestinationPage(PdfNameTreeAccess names);

  /// Creates a PdfDestination from a PdfObject.
  ///
  /// Arrays whose first element is a number are remote explicit destinations
  /// (12.6.4.3): the page is a zero-based page number inside another
  /// document, not a page object of the current one.
  static Future<PdfDestination?> makeDestination(PdfObject pdfObject,
      {bool throwException = true}) async {
    if (pdfObject is PdfIndirectReference) {
      final target = await pdfObject.targetObject(true);
      if (target == null) {
        if (throwException) {
          throw ArgumentError('Destination reference could not be resolved');
        }
        return null;
      }
      return makeDestination(target, throwException: throwException);
    }
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
      final firstObj = await destArray.get(0, false);
      if (firstObj != null) {
        if (firstObj.objectKind() == PdfObjectType.number) {
          // ISO 32000-1:2008, 12.6.4.3: a numeric first element identifies a
          // page inside a remote document.
          return PdfExplicitRemoteGoToDestination(destArray);
        }
        final resolved = firstObj is PdfIndirectReference
            ? await firstObj.targetObject(true)
            : firstObj;
        if (resolved != null && resolved.isDictionary()) {
          final dict = resolved as PdfDictionary;
          final type = await dict.nameEntry(PdfName.type);
          if (PdfName.structElem == type) {
            return PdfStructureDestination(destArray);
          }
          return PdfExplicitDestination(destArray);
        }
        return PdfExplicitDestination(destArray);
      }
    } else {
      if (throwException) {
        throw UnsupportedError("Unsupported destination object type");
      }
    }
    return null;
  }
}

/// A destination named by a byte string, resolved through the `Dests` name
/// tree of the document's name dictionary (PDF 1.2; 12.3.2.3).
class PdfStringDestination extends PdfDestination {
  PdfStringDestination(PdfString super.pdfObject);

  PdfStringDestination.fromString(String s) : super(PdfString(s));

  @override
  Future<PdfObject?> getDestinationPage(PdfNameTreeAccess names) async {
    final destination = await names.getEntry(pdfRepresentation() as PdfString);
    return await _resolvePage(destination);
  }

  @override
  bool requiresIndirectStorage() => false;
}

/// A destination named by a name object, resolved through the catalog's
/// `Dests` dictionary (PDF 1.1; 12.3.2.3).
class PdfNamedDestination extends PdfDestination {
  PdfNamedDestination(PdfName super.pdfObject);

  PdfNamedDestination.fromName(String name) : super(PdfName(name));

  @override
  Future<PdfObject?> getDestinationPage(PdfNameTreeAccess names) async {
    final name = pdfRepresentation() as PdfName;
    final entry = await names.getEntryAsString(name.getValue());
    return await _resolvePage(entry);
  }

  @override
  bool requiresIndirectStorage() => false;
}

/// Resolves the page of a named destination value, which Table 151 allows to
/// be either the destination array itself or a dictionary with a `/D` entry.
Future<PdfObject?> _resolvePage(PdfObject? destination) async {
  if (destination is PdfArray) {
    return await destination.get(0, false);
  }
  if (destination is PdfDictionary) {
    final d = await destination.arrayEntry(PdfName.d);
    return await d?.get(0, false);
  }
  return null;
}

/// An explicit destination array in the current document.
///
/// See ISO 32000-1:2008, 12.3.2.2, Table 151.
class PdfExplicitDestination extends PdfDestination {
  PdfExplicitDestination(PdfArray super.pdfObject);

  PdfExplicitDestination.empty() : super(PdfArray());

  @override
  Future<PdfObject?> getDestinationPage(PdfNameTreeAccess names) async {
    return await (pdfRepresentation() as PdfArray).get(0, false);
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Gets the destination type name (`/XYZ`, `/Fit`, ...).
  Future<PdfName?> getType() async =>
      await (pdfRepresentation() as PdfArray).nameEntry(1);

  /// Gets the numeric parameters following the destination type.
  Future<List<double?>> getParameters() async {
    final array = pdfRepresentation() as PdfArray;
    final result = <double?>[];
    for (var i = 2; i < array.size(); i++) {
      final value = await array.get(i);
      result.add(value is PdfNumber ? value.getValue() : null);
    }
    return result;
  }

  /// `[page /XYZ left top zoom]`. A null argument writes a PDF null, which
  /// Table 151 defines as "retain the current value"; a zoom of 0 has the
  /// same meaning as null.
  static PdfExplicitDestination createXYZ(
      PdfPage page, double? left, double? top, double? zoom) {
    final dest = PdfExplicitDestination.empty();
    dest._addPage(page);
    dest._addName(PdfName.xyz);
    dest._addNullableNumber(left);
    dest._addNullableNumber(top);
    dest._addNullableNumber(zoom);
    return dest;
  }

  /// `[page /Fit]`.
  static PdfExplicitDestination createFit(PdfPage page) {
    final dest = PdfExplicitDestination.empty();
    dest._addPage(page);
    dest._addName(PdfName.fit);
    return dest;
  }

  /// `[page /FitH top]`.
  static PdfExplicitDestination createFitH(PdfPage page, double? top) {
    final dest = PdfExplicitDestination.empty();
    dest._addPage(page);
    dest._addName(PdfName.fitH);
    dest._addNullableNumber(top);
    return dest;
  }

  /// `[page /FitV left]`.
  static PdfExplicitDestination createFitV(PdfPage page, double? left) {
    final dest = PdfExplicitDestination.empty();
    dest._addPage(page);
    dest._addName(PdfName.fitV);
    dest._addNullableNumber(left);
    return dest;
  }

  /// `[page /FitR left bottom right top]`.
  static PdfExplicitDestination createFitR(
      PdfPage page, double left, double bottom, double right, double top) {
    final dest = PdfExplicitDestination.empty();
    dest._addPage(page);
    dest._addName(PdfName.fitR);
    dest._addNumber(left);
    dest._addNumber(bottom);
    dest._addNumber(right);
    dest._addNumber(top);
    return dest;
  }

  /// `[page /FitB]` (PDF 1.1).
  static PdfExplicitDestination createFitB(PdfPage page) {
    final dest = PdfExplicitDestination.empty();
    dest._addPage(page);
    dest._addName(PdfName.fitB);
    return dest;
  }

  /// `[page /FitBH top]` (PDF 1.1).
  static PdfExplicitDestination createFitBH(PdfPage page, double? top) {
    final dest = PdfExplicitDestination.empty();
    dest._addPage(page);
    dest._addName(PdfName.fitBH);
    dest._addNullableNumber(top);
    return dest;
  }

  /// `[page /FitBV left]` (PDF 1.1).
  static PdfExplicitDestination createFitBV(PdfPage page, double? left) {
    final dest = PdfExplicitDestination.empty();
    dest._addPage(page);
    dest._addName(PdfName.fitBV);
    dest._addNullableNumber(left);
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
    (pdfRepresentation() as PdfArray).add(PdfNumber(val));
  }

  void _addNullableNumber(double? val) {
    (pdfRepresentation() as PdfArray)
        .add(val == null ? PdfNull() : PdfNumber(val));
  }
}

/// An explicit destination inside a remote document, used by remote and
/// embedded go-to actions.
///
/// See ISO 32000-1:2008, 12.3.2.2 and 12.6.4.3: the first element is a
/// zero-based page number rather than an indirect page reference.
class PdfExplicitRemoteGoToDestination extends PdfDestination {
  PdfExplicitRemoteGoToDestination(PdfArray super.pdfObject);

  PdfExplicitRemoteGoToDestination.empty() : super(PdfArray());

  @override
  bool requiresIndirectStorage() => false;

  /// The destination page lives in another document, so no object of the
  /// current document can be returned.
  @override
  Future<PdfObject?> getDestinationPage(PdfNameTreeAccess names) async => null;

  /// Gets the zero-based page number of the remote document.
  Future<int?> getPageNumber() async =>
      (await (pdfRepresentation() as PdfArray).numberEntry(0))?.intValue();

  /// Gets the destination type name (`/XYZ`, `/Fit`, ...).
  Future<PdfName?> getType() async =>
      await (pdfRepresentation() as PdfArray).nameEntry(1);

  /// Gets the numeric parameters following the destination type.
  Future<List<double?>> getParameters() async {
    final array = pdfRepresentation() as PdfArray;
    final result = <double?>[];
    for (var i = 2; i < array.size(); i++) {
      final value = await array.get(i);
      result.add(value is PdfNumber ? value.getValue() : null);
    }
    return result;
  }

  /// `[page /XYZ left top zoom]` with a remote page number.
  static PdfExplicitRemoteGoToDestination createXYZ(
          int pageNumber, double? left, double? top, double? zoom) =>
      _create(pageNumber, PdfName.xyz, [left, top, zoom]);

  /// `[page /Fit]` with a remote page number.
  static PdfExplicitRemoteGoToDestination createFit(int pageNumber) =>
      _create(pageNumber, PdfName.fit, const []);

  /// `[page /FitH top]` with a remote page number.
  static PdfExplicitRemoteGoToDestination createFitH(
          int pageNumber, double? top) =>
      _create(pageNumber, PdfName.fitH, [top]);

  /// `[page /FitV left]` with a remote page number.
  static PdfExplicitRemoteGoToDestination createFitV(
          int pageNumber, double? left) =>
      _create(pageNumber, PdfName.fitV, [left]);

  /// `[page /FitR left bottom right top]` with a remote page number.
  static PdfExplicitRemoteGoToDestination createFitR(int pageNumber,
          double left, double bottom, double right, double top) =>
      _create(pageNumber, PdfName.fitR, [left, bottom, right, top]);

  /// `[page /FitB]` with a remote page number.
  static PdfExplicitRemoteGoToDestination createFitB(int pageNumber) =>
      _create(pageNumber, PdfName.fitB, const []);

  /// `[page /FitBH top]` with a remote page number.
  static PdfExplicitRemoteGoToDestination createFitBH(
          int pageNumber, double? top) =>
      _create(pageNumber, PdfName.fitBH, [top]);

  /// `[page /FitBV left]` with a remote page number.
  static PdfExplicitRemoteGoToDestination createFitBV(
          int pageNumber, double? left) =>
      _create(pageNumber, PdfName.fitBV, [left]);

  static PdfExplicitRemoteGoToDestination _create(
      int pageNumber, PdfName type, List<double?> parameters) {
    if (pageNumber < 0) {
      throw ArgumentError.value(pageNumber, 'pageNumber',
          'Remote destinations use zero-based page numbers');
    }
    final array = PdfArray();
    array.add(PdfNumber.fromInt(pageNumber));
    array.add(type);
    for (final parameter in parameters) {
      array.add(parameter == null ? PdfNull() : PdfNumber(parameter));
    }
    return PdfExplicitRemoteGoToDestination(array);
  }
}

/// A structure destination, whose first element is a structure element
/// dictionary rather than a page object.
///
/// See ISO 32000-1:2008, 12.3.2.2 combined with 14.7 "Logical Structure":
/// the referenced structure element determines the page shown.
class PdfStructureDestination extends PdfDestination {
  PdfStructureDestination(PdfArray super.pdfObject);

  @override
  bool requiresIndirectStorage() => false;

  @override
  Future<PdfObject?> getDestinationPage(PdfNameTreeAccess names) async {
    final element = await (pdfRepresentation() as PdfArray).get(0, true);
    if (element is PdfDictionary) {
      return await element.get(PdfName.intern('Pg'), false) ??
          await element.get(PdfName.p, false);
    }
    return null;
  }

  /// Gets the structure element the destination points at.
  Future<PdfDictionary?> getStructureElement() async =>
      await (pdfRepresentation() as PdfArray).dictionaryEntry(0);
}
