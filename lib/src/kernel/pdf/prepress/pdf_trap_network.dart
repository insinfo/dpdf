import '../pdf_array.dart';
import '../pdf_date.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_object.dart';
import '../pdf_stream.dart';
import '../pdf_string.dart';
import '../xobject/pdf_form_x_object.dart';
import 'pdf_printer_mark_form.dart';

/// The process colour model of `/PCM` in a trap network appearance.
///
/// ISO 32000-1:2008, Table 367: "Valid values are DeviceGray, DeviceRGB,
/// DeviceCMYK, DeviceCMY, DeviceRGBK, and DeviceN."
class PdfProcessColorModel {
  /// `/DeviceGray`.
  static const String deviceGray = 'DeviceGray';

  /// `/DeviceRGB`.
  static const String deviceRgb = 'DeviceRGB';

  /// `/DeviceCMYK`.
  static const String deviceCmyk = 'DeviceCMYK';

  /// `/DeviceCMY`.
  static const String deviceCmy = 'DeviceCMY';

  /// `/DeviceRGBK`.
  static const String deviceRgbk = 'DeviceRGBK';

  /// `/DeviceN`.
  static const String deviceN = 'DeviceN';

  /// Every value Table 367 allows.
  static const List<String> values = [
    deviceGray,
    deviceRgb,
    deviceCmyk,
    deviceCmy,
    deviceRgbk,
    deviceN,
  ];

  /// The colorants a process colour model implies, which "are available
  /// automatically and need not be explicitly declared" in
  /// `/SeparationColorNames`. `/DeviceN` implies none.
  static List<String> impliedColorants(String model) {
    switch (model) {
      case deviceGray:
        return const ['Gray'];
      case deviceRgb:
        return const ['Red', 'Green', 'Blue'];
      case deviceCmyk:
        return const ['Cyan', 'Magenta', 'Yellow', 'Black'];
      case deviceCmy:
        return const ['Cyan', 'Magenta', 'Yellow'];
      case deviceRgbk:
        return const ['Red', 'Green', 'Blue', 'Black'];
      default:
        return const [];
    }
  }

  const PdfProcessColorModel._();
}

/// A trap network appearance stream.
///
/// ISO 32000-1:2008, 14.11.6.3 "Trap Network Appearances", Table 367. A trap
/// network is a form XObject held in the `/N` appearance of a `TrapNet`
/// annotation; its body paints the traps, and its dictionary carries the form
/// entries of 8.10.2 plus `/PCM`, `/SeparationColorNames`, `/TrapRegions` and
/// `/TrapStyles`.
class PdfTrapNetworkAppearance extends PdfFormXObject {
  /// `/PCM`, the process colour model assumed when the network was created.
  static final PdfName processColorModel = PdfName.intern('PCM');

  /// `/SeparationColorNames`.
  static final PdfName separationColorNames =
      PdfName.intern('SeparationColorNames');

  /// `/TrapRegions`.
  static final PdfName trapRegions = PdfName.intern('TrapRegions');

  /// `/TrapStyles`.
  static final PdfName trapStyles = PdfName.intern('TrapStyles');

  /// Creates a trap network appearance with the given bounding box.
  PdfTrapNetworkAppearance(super.bBox);

  /// Wraps an existing form stream as a trap network appearance.
  PdfTrapNetworkAppearance.fromStream(super.stream) : super.fromStream();

  /// Sets `/PCM`, which Table 367 marks required.
  ///
  /// Only the six names Table 367 lists are accepted.
  PdfTrapNetworkAppearance setProcessColorModel(String model) {
    if (!PdfProcessColorModel.values.contains(model)) {
      throw ArgumentError.value(model, 'model',
          'A trap network /PCM shall be one of ${PdfProcessColorModel.values.join(', ')} (Table 367)');
    }
    pdfRepresentation().put(processColorModel, PdfName(model));
    markChanged();
    return this;
  }

  /// Gets `/PCM`.
  Future<String?> getProcessColorModel() async =>
      (await pdfRepresentation().nameEntry(processColorModel))?.getValue();

  /// Sets `/SeparationColorNames`, the colorants assumed beyond the ones
  /// `/PCM` already implies.
  PdfTrapNetworkAppearance setSeparationColorNames(List<String> names) {
    pdfRepresentation()
        .put(separationColorNames, PdfArray.fromStrings(names, asNames: true));
    markChanged();
    return this;
  }

  /// Gets `/SeparationColorNames`.
  ///
  /// "If this entry is absent, the colorants implied by PCM shall be assumed",
  /// so an absent entry yields `null` and not an empty list; use
  /// [effectiveColorants] for the resolved set.
  Future<List<String>?> getSeparationColorNames() async {
    final array = await pdfRepresentation().arrayEntry(separationColorNames);
    if (array == null) return null;
    final names = <String>[];
    for (var i = 0; i < array.size(); i++) {
      final entry = await array.get(i, true);
      if (entry is PdfName) names.add(entry.getValue());
    }
    return names;
  }

  /// The colorants this network assumed: the ones `/PCM` implies, plus the
  /// ones `/SeparationColorNames` declares.
  Future<List<String>> effectiveColorants() async {
    final model = await getProcessColorModel();
    final result = <String>[
      if (model != null) ...PdfProcessColorModel.impliedColorants(model)
    ];
    for (final name in await getSeparationColorNames() ?? const <String>[]) {
      if (!result.contains(name)) result.add(name);
    }
    return result;
  }

  /// Sets `/TrapRegions`, indirect references to the PJTF TrapRegion objects
  /// embedded in the file.
  PdfTrapNetworkAppearance setTrapRegions(List<PdfObject> regions) {
    final array = PdfArray();
    for (final region in regions) {
      final reference = region.indirectHandle();
      if (reference == null) {
        throw ArgumentError.value(regions, 'regions',
            'A /TrapRegions entry shall be an indirect reference (Table 367)');
      }
      array.add(reference);
    }
    pdfRepresentation().put(trapRegions, array);
    markChanged();
    return this;
  }

  /// Gets `/TrapRegions` as written.
  Future<PdfArray?> getTrapRegions() async =>
      await pdfRepresentation().arrayEntry(trapRegions);

  /// Sets `/TrapStyles`, a human-readable description of this network.
  PdfTrapNetworkAppearance setTrapStyles(String styles) {
    pdfRepresentation().put(trapStyles, PdfString(styles));
    markChanged();
    return this;
  }

  /// Gets `/TrapStyles`.
  Future<String?> getTrapStyles() async =>
      (await pdfRepresentation().stringEntry(trapStyles))?.decodeMappingText();

  /// Reports every way in which this appearance departs from Table 367.
  Future<List<String>> validate() async {
    final problems = <String>[];
    final dictionary = pdfRepresentation();

    final subtype = await dictionary.nameEntry(PdfName.subtype);
    if (subtype == null || subtype.getValue() != 'Form') {
      problems.add('A trap network shall be a form XObject, /Subtype /Form '
          '(14.11.6.3)');
    }
    if (!dictionary.containsKey(PdfName.bBox)) {
      problems.add('/BBox is required in a form dictionary (Table 95)');
    }

    final model = await getProcessColorModel();
    if (model == null) {
      problems.add('/PCM is required in a trap network appearance (Table 367)');
    } else if (!PdfProcessColorModel.values.contains(model)) {
      problems.add('/PCM shall be one of '
          '${PdfProcessColorModel.values.join(', ')} (Table 367)');
    }

    if (dictionary.containsKey(separationColorNames) &&
        await dictionary.arrayEntry(separationColorNames) == null) {
      problems.add('/SeparationColorNames shall be an array of names '
          '(Table 367)');
    }

    if (dictionary.containsKey(trapRegions)) {
      final regions = await getTrapRegions();
      if (regions == null) {
        problems.add('/TrapRegions shall be an array (Table 367)');
      } else {
        for (var i = 0; i < regions.size(); i++) {
          if (await regions.get(i, false) is! PdfIndirectReference) {
            problems.add('/TrapRegions entry $i shall be an indirect reference '
                'to a TrapRegion object (Table 367)');
          }
        }
      }
    }

    if (dictionary.containsKey(trapStyles) &&
        await dictionary.stringEntry(trapStyles) == null) {
      problems.add('/TrapStyles shall be a text string (Table 367)');
    }

    return problems;
  }
}

/// Checks a trap network annotation against 14.11.6.2 and Table 366.
///
/// Beyond the type checks of Table 366 this enforces the prose rules:
///
/// * `/AP`, `/AS` and `/F` shall be present, with only the `Print` and
///   `ReadOnly` flags set;
/// * the annotation shall carry either `/LastModified` or the combination of
///   `/Version` and `/AnnotStates`, "but not all three";
/// * `/Version` and `/AnnotStates` are each required when the other is
///   present.
///
/// Returns the list of departures; an empty list means the annotation
/// conforms.
Future<List<String>> validateTrapNetworkAnnotation(
    PdfDictionary annotation) async {
  final problems = <String>[];
  final lastModified = PdfName.intern('LastModified');
  final version = PdfName.intern('Version');
  final annotStates = PdfName.intern('AnnotStates');
  final fontFauxing = PdfName.intern('FontFauxing');

  final subtype = await annotation.nameEntry(PdfName.subtype);
  if (subtype == null || subtype.getValue() != 'TrapNet') {
    problems.add('/Subtype shall be /TrapNet (Table 366)');
  }

  problems
      .addAll(await validatePrintOnlyAnnotation(annotation, 'trap network'));

  // 14.11.6.2 also requires /AS unconditionally on a trap network annotation,
  // not only when several appearances are present.
  if (await annotation.nameEntry(PdfName.intern('AS')) == null) {
    problems.add('/AS shall be present on a trap network annotation '
        '(14.11.6.2)');
  }

  final hasLastModified = annotation.containsKey(lastModified);
  final hasVersion = annotation.containsKey(version);
  final hasStates = annotation.containsKey(annotStates);

  if (hasLastModified && (hasVersion || hasStates)) {
    problems.add('/LastModified shall be absent when /Version and '
        '/AnnotStates are present (Table 366)');
  }
  if (!hasLastModified && !(hasVersion && hasStates)) {
    problems.add('A trap network annotation shall carry either /LastModified '
        'or both /Version and /AnnotStates (Table 366)');
  }
  if (hasVersion != hasStates) {
    problems.add('/Version and /AnnotStates shall be present together '
        '(Table 366)');
  }
  if (hasLastModified && await annotation.stringEntry(lastModified) == null) {
    problems.add('/LastModified shall be a date string (Table 366)');
  }
  if (hasVersion && await annotation.arrayEntry(version) == null) {
    problems.add('/Version shall be an array (Table 366)');
  }
  if (hasStates && await annotation.arrayEntry(annotStates) == null) {
    problems.add('/AnnotStates shall be an array (Table 366)');
  }
  if (annotation.containsKey(fontFauxing) &&
      await annotation.arrayEntry(fontFauxing) == null) {
    problems.add('/FontFauxing shall be an array of font dictionaries '
        '(Table 366)');
  }

  return problems;
}

/// Checks the placement of trap network annotations on a page.
///
/// 14.11.6.2: "There may be at most one trap network annotation per page,
/// which shall be the last element in the page's Annots array." The
/// `/AnnotStates` array, when present, "shall be listed in the same order as
/// the annotations in the page's Annots array... No appearance state shall be
/// included for the trap network annotation itself", so its length shall be
/// one less than the number of annotations.
Future<List<String>> validatePageTrapNetworks(PdfDictionary page) async {
  final problems = <String>[];
  final annots = await page.arrayEntry(PdfName.annots);
  if (annots == null) return problems;

  final trapIndices = <int>[];
  final annotations = <PdfDictionary?>[];
  for (var i = 0; i < annots.size(); i++) {
    final entry = await annots.get(i, true);
    final dictionary = entry is PdfDictionary ? entry : null;
    annotations.add(dictionary);
    if (dictionary == null) continue;
    final subtype = await dictionary.nameEntry(PdfName.subtype);
    if (subtype != null && subtype.getValue() == 'TrapNet') {
      trapIndices.add(i);
    }
  }

  if (trapIndices.isEmpty) return problems;
  if (trapIndices.length > 1) {
    problems.add('A page shall carry at most one trap network annotation '
        '(14.11.6.2), found ${trapIndices.length}');
  }
  final last = trapIndices.last;
  if (last != annots.size() - 1) {
    problems.add('The trap network annotation shall be the last element of '
        '/Annots (14.11.6.2)');
  }

  final trap = annotations[last];
  if (trap != null) {
    final states = await trap.arrayEntry(PdfName.intern('AnnotStates'));
    if (states != null && states.size() != annots.size() - 1) {
      problems.add('/AnnotStates shall list one entry per annotation of the '
          'page other than the trap network annotation itself (Table 366), '
          'expected ${annots.size() - 1} and found ${states.size()}');
    }
  }

  return problems;
}

/// Whether the trap networks of [page] have to be regenerated.
///
/// 14.11.6.2: "If the modification date in the LastModified entry of the page
/// object is more recent than the one in the trap network annotation
/// dictionary, the page's trap networks are invalid and shall be
/// regenerated." Returns `false` when either date is missing or unreadable,
/// since the comparison cannot then be made.
Future<bool> trapNetworkNeedsRegeneration(
    PdfDictionary page, PdfDictionary trapNetworkAnnotation) async {
  final key = PdfName.intern('LastModified');
  final pageDate = await _readDate(page, key);
  final trapDate = await _readDate(trapNetworkAnnotation, key);
  if (pageDate == null || trapDate == null) return false;
  return pageDate.isAfter(trapDate);
}

Future<DateTime?> _readDate(PdfDictionary dictionary, PdfName key) async {
  final value = await dictionary.stringEntry(key);
  if (value == null) return null;
  try {
    return PdfDate.decode(value.getValue());
  } catch (_) {
    return null;
  }
}

/// Installs [appearance] as a named trap network in the `/N` appearance
/// subdictionary of [annotation].
///
/// 14.11.6.3: each entry of the `/N` subdictionary is one trap network, and
/// `/AS` names the current one. The first network installed also becomes the
/// value of `/AS` when the annotation has none.
Future<void> addTrapNetwork(PdfDictionary annotation, String state,
    PdfTrapNetworkAppearance appearance) async {
  var ap = await annotation.dictionaryEntry(PdfName.ap);
  if (ap == null) {
    ap = PdfDictionary();
    annotation.put(PdfName.ap, ap);
  }
  var normal = await ap.get(PdfName.n, true);
  if (normal is PdfStream || normal is! PdfDictionary) {
    normal = PdfDictionary();
    ap.put(PdfName.n, normal);
  }
  normal.put(PdfName(state), appearance.pdfRepresentation());
  if (!annotation.containsKey(PdfName.intern('AS'))) {
    annotation.put(PdfName.intern('AS'), PdfName(state));
  }
  annotation.markChanged();
}
