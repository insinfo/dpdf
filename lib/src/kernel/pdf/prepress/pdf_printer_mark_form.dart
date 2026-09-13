import '../../geom/rectangle.dart';
import '../annot/pdf_annotation.dart';
import '../pdf_array.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_object.dart';
import '../pdf_stream.dart';
import '../pdf_string.dart';
import '../xobject/pdf_form_x_object.dart';

/// The form XObject that paints a printer's mark.
///
/// ISO 32000-1:2008, 14.11.3 "Printer's Marks", Table 363. The mark itself is
/// an ordinary form XObject - `/Type /XObject`, `/Subtype /Form` and a `/BBox`
/// as in 8.10.2 - used as the `/N` appearance of a `PrinterMark` annotation.
/// Table 363 adds two optional entries on top of the form dictionary:
///
/// * `/MarkStyle`, a text string describing the mark for a human reader;
/// * `/Colorants`, a dictionary whose keys are colorant names and whose values
///   are Separation colour space arrays for those colorants.
class PdfPrinterMarkForm extends PdfFormXObject {
  /// `/MarkStyle`, PDF 1.4.
  static final PdfName markStyle = PdfName.intern('MarkStyle');

  /// `/Colorants`, PDF 1.4.
  static final PdfName colorants = PdfName.intern('Colorants');

  /// Creates a printer's mark form with the given bounding box.
  PdfPrinterMarkForm(super.bBox);

  /// Wraps an existing form stream as a printer's mark form.
  PdfPrinterMarkForm.fromStream(super.stream) : super.fromStream();

  /// Sets `/MarkStyle`, "a text string representing the printer's mark in
  /// human-readable form and suitable for presentation to the user".
  PdfPrinterMarkForm setMarkStyle(String style) {
    pdfRepresentation().put(markStyle, PdfString(style));
    markChanged();
    return this;
  }

  /// Gets `/MarkStyle`.
  Future<String?> getMarkStyle() async =>
      (await pdfRepresentation().stringEntry(markStyle))?.decodeMappingText();

  /// Adds one entry to `/Colorants`.
  ///
  /// Table 363: "the key is a colorant name and the value is an array defining
  /// a Separation colour space for that colorant... The key shall match the
  /// colorant name given in that colour space." That agreement is enforced
  /// here, since a mismatch makes the entry meaningless.
  Future<PdfPrinterMarkForm> addColorant(String name, PdfArray space) async {
    if (name.isEmpty) {
      throw ArgumentError.value(
          name, 'name', 'A /Colorants key shall name a colorant (Table 363)');
    }
    final declared = await separationColorantName(space);
    if (declared == null) {
      throw ArgumentError.value(space, 'space',
          'A /Colorants value shall be a Separation colour space array (8.6.6.4)');
    }
    if (declared != name) {
      throw ArgumentError.value(
          space,
          'space',
          'The /Colorants key "$name" shall match the colorant name '
              '"$declared" of its colour space (Table 363)');
    }
    var dictionary = await pdfRepresentation().dictionaryEntry(colorants);
    if (dictionary == null) {
      dictionary = PdfDictionary();
      pdfRepresentation().put(colorants, dictionary);
    }
    dictionary.put(PdfName(name), space);
    markChanged();
    return this;
  }

  /// Gets `/Colorants`.
  Future<PdfDictionary?> getColorants() async =>
      await pdfRepresentation().dictionaryEntry(colorants);

  /// The Separation colour space recorded for [name], if any.
  Future<PdfArray?> getColorant(String name) async {
    final dictionary = await getColorants();
    if (dictionary == null) return null;
    final value = await dictionary.get(PdfName(name), true);
    return value is PdfArray ? value : null;
  }

  /// The colorant names listed by `/Colorants`.
  Future<List<String>> colorantNames() async {
    final dictionary = await getColorants();
    if (dictionary == null) return const [];
    final map = dictionary.getMap();
    if (map == null) return const [];
    return map.keys.map((key) => key.getValue()).toList();
  }

  /// The colorant name of a Separation colour space array, or `null` when
  /// [space] is not one.
  ///
  /// 8.6.6.4: a Separation space is `[/Separation name alternateSpace
  /// tintTransform]`.
  static Future<String?> separationColorantName(PdfArray space) async {
    if (space.size() < 2) return null;
    final family = await space.get(0, true);
    if (family is! PdfName || family.getValue() != 'Separation') return null;
    final name = await space.get(1, true);
    return name is PdfName ? name.getValue() : null;
  }

  /// Reports every way in which this form departs from Table 363 and 8.10.2.
  Future<List<String>> validate() async {
    final problems = <String>[];
    final dictionary = pdfRepresentation();

    final type = await dictionary.nameEntry(PdfName.type);
    if (type != null && type.getValue() != 'XObject') {
      problems.add('/Type shall be /XObject for a form XObject (Table 95)');
    }
    final subtype = await dictionary.nameEntry(PdfName.subtype);
    if (subtype == null || subtype.getValue() != 'Form') {
      problems.add('/Subtype shall be /Form for a printer\'s mark (Table 95)');
    }
    final bBox =
        await Rectangle.fromPdfArray(await dictionary.arrayEntry(PdfName.bBox));
    if (bBox == null) {
      problems.add('/BBox is required in a form dictionary (Table 95)');
    }

    if (dictionary.containsKey(markStyle) &&
        await dictionary.stringEntry(markStyle) == null) {
      problems.add('/MarkStyle shall be a text string (Table 363)');
    }

    final colorantDictionary = await getColorants();
    if (dictionary.containsKey(colorants) && colorantDictionary == null) {
      problems.add('/Colorants shall be a dictionary (Table 363)');
    } else if (colorantDictionary != null) {
      final map = colorantDictionary.getMap() ?? const <PdfName, PdfObject>{};
      for (final key in map.keys) {
        final value = await colorantDictionary.get(key, true);
        if (value is! PdfArray) {
          problems.add('/Colorants entry /${key.getValue()} shall be a '
              'Separation colour space array (Table 363)');
          continue;
        }
        final declared = await separationColorantName(value);
        if (declared == null) {
          problems.add('/Colorants entry /${key.getValue()} shall be a '
              'Separation colour space array (8.6.6.4)');
        } else if (declared != key.getValue()) {
          problems.add('/Colorants key /${key.getValue()} shall match the '
              'colorant name /$declared of its colour space (Table 363)');
        }
      }
    }

    return problems;
  }
}

/// Checks a printer's mark annotation against the requirements of 14.11.3.
///
/// Those requirements sit outside Table 362 in the prose of the clause, so
/// they are checked here rather than on the annotation wrapper itself:
///
/// * `/Subtype` shall be `/PrinterMark`;
/// * `/AP` and `/F`, ordinarily optional, shall be present;
/// * `/AS` shall be present when `/AP` `/N` holds more than one appearance;
/// * the `Print` and `ReadOnly` flags of `/F` shall be set and all others
///   clear.
///
/// Returns the list of departures; an empty list means the annotation
/// conforms.
Future<List<String>> validatePrinterMarkAnnotation(
    PdfDictionary annotation) async {
  final problems = <String>[];

  final subtype = await annotation.nameEntry(PdfName.subtype);
  if (subtype == null || subtype.getValue() != 'PrinterMark') {
    problems.add('/Subtype shall be /PrinterMark (Table 362)');
  }
  if (annotation.containsKey(PdfName.intern('MN')) &&
      await annotation.nameEntry(PdfName.intern('MN')) == null) {
    problems.add('/MN shall be a name (Table 362)');
  }

  problems.addAll(await validatePrintOnlyAnnotation(
      annotation,
      'printer\'s '
      'mark'));
  return problems;
}

/// The shared `/AP`, `/AS` and `/F` checks that 14.11.3 imposes on printer's
/// mark annotations and 14.11.6.2 imposes on trap network annotations.
///
/// [kind] names the annotation in the reported messages.
Future<List<String>> validatePrintOnlyAnnotation(
    PdfDictionary annotation, String kind) async {
  final problems = <String>[];

  final appearance = await annotation.dictionaryEntry(PdfName.ap);
  if (appearance == null) {
    problems.add('/AP shall be present on a $kind annotation');
  } else {
    final normal = await appearance.get(PdfName.n, true);
    if (normal == null) {
      problems.add('/AP shall hold an /N appearance on a $kind annotation');
    } else if (normal is PdfDictionary && normal is! PdfStream) {
      final states = normal.getMap()?.length ?? 0;
      if (states > 1 &&
          await annotation.nameEntry(PdfName.intern('AS')) == null) {
        problems.add('/AS shall be present when /AP /N holds more than one '
            'appearance on a $kind annotation');
      }
    }
  }

  final flags = await annotation.numberEntry(PdfName.f);
  if (flags == null) {
    problems.add('/F shall be present on a $kind annotation');
  } else {
    const required = PdfAnnotation.print | PdfAnnotation.readOnly;
    final value = flags.intValue();
    if (value & required != required) {
      problems.add('The Print and ReadOnly flags of /F shall be set on a $kind '
          'annotation (12.5.3)');
    }
    if (value & ~required != 0) {
      problems.add('Only the Print and ReadOnly flags of /F shall be set on a '
          '$kind annotation (12.5.3)');
    }
  }

  return problems;
}
