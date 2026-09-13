import '../pdf_array.dart';
import '../pdf_catalog.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';
import '../pdf_object.dart';
import '../pdf_object_wrapper.dart';
import 'pdf_web_capture_command.dart';

/// The Web Capture information dictionary.
///
/// ISO 32000-1:2008, 14.10.2, Table 350: the `/SpiderInfo` entry of the
/// document catalogue, holding the Web Capture version number and the commands
/// that were used in building the file.
class PdfWebCaptureInfo extends PdfObjectWrapper<PdfDictionary> {
  /// `/SpiderInfo`, the document catalogue entry of Table 28.
  static final PdfName spiderInfo = PdfName.intern('SpiderInfo');

  /// `/V`, the Web Capture version number.
  static final PdfName version = PdfName.intern('V');

  /// `/C`, the commands used in building the file.
  static final PdfName commands = PdfName.intern('C');

  /// "The version number shall be 1.0 in a conforming file. This value shall
  /// be a single real number, not a major and minor version number."
  static const double conformingVersion = 1.0;

  PdfWebCaptureInfo(super.pdfObject);

  /// Creates a Web Capture information dictionary at version 1.0.
  PdfWebCaptureInfo.create() : super(PdfDictionary()) {
    setVersion(conformingVersion);
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Reads `/SpiderInfo` from [catalog], or `null` when the document has none.
  static Future<PdfWebCaptureInfo?> ofCatalog(PdfCatalog catalog) async {
    final dictionary =
        await catalog.pdfRepresentation().dictionaryEntry(spiderInfo);
    return dictionary == null ? null : PdfWebCaptureInfo(dictionary);
  }

  /// Writes this dictionary into the `/SpiderInfo` entry of [catalog].
  void attachToCatalog(PdfCatalog catalog) {
    catalog.pdfRepresentation().put(spiderInfo, pdfRepresentation());
    catalog.pdfRepresentation().markChanged();
  }

  /// Sets `/V`.
  PdfWebCaptureInfo setVersion(double value) {
    pdfRepresentation().put(version, PdfNumber(value));
    markChanged();
    return this;
  }

  /// Gets `/V`.
  Future<double?> getVersion() async =>
      (await pdfRepresentation().numberEntry(version))?.doubleValue();

  /// Appends one command to `/C`.
  ///
  /// "The commands shall appear in the array in the order in which they were
  /// executed in building the file", and the array holds indirect references,
  /// so the command has to belong to a document already.
  PdfWebCaptureInfo addCommand(PdfWebCaptureCommand command) {
    final reference = command.pdfRepresentation().indirectHandle();
    if (reference == null) {
      throw ArgumentError.value(
          command,
          'command',
          'A /C entry shall be an indirect reference to a command dictionary '
              '(Table 350)');
    }
    var array = _commandArray();
    if (array == null) {
      array = PdfArray();
      pdfRepresentation().put(commands, array);
    }
    array.add(reference);
    markChanged();
    return this;
  }

  /// Gets the commands of `/C`, in execution order.
  Future<List<PdfWebCaptureCommand>> getCommands() async {
    final array = await pdfRepresentation().arrayEntry(commands);
    if (array == null) return const [];
    final result = <PdfWebCaptureCommand>[];
    for (var i = 0; i < array.size(); i++) {
      final entry = await array.dictionaryEntry(i);
      if (entry != null) result.add(PdfWebCaptureCommand(entry));
    }
    return result;
  }

  /// Reports every way in which this dictionary departs from Table 350.
  ///
  /// The version check is part of the table itself: "the version number shall
  /// be 1.0 in a conforming file".
  Future<List<String>> validate() async {
    final problems = <String>[];
    final value = await getVersion();
    if (value == null) {
      problems.add('/V is required in a Web Capture information dictionary '
          '(Table 350)');
    } else if (value != conformingVersion) {
      problems.add('/V shall be 1.0 in a conforming file (Table 350), found '
          '$value');
    }

    if (pdfRepresentation().containsKey(commands)) {
      final array = await pdfRepresentation().arrayEntry(commands);
      if (array == null) {
        problems.add('/C shall be an array of command dictionaries '
            '(Table 350)');
      } else {
        for (var i = 0; i < array.size(); i++) {
          if (await array.get(i, false) is! PdfIndirectReference) {
            problems.add('/C entry $i shall be an indirect reference '
                '(Table 350)');
          }
        }
        for (final command in await getCommands()) {
          problems.addAll(await command.validate());
        }
      }
    }
    return problems;
  }

  PdfArray? _commandArray() {
    final value = pdfRepresentation().getMap()?[commands];
    return value is PdfArray ? value : null;
  }
}
