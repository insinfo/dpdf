import 'dart:convert';
import 'dart:typed_data';

import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';
import '../pdf_object.dart';
import '../pdf_object_wrapper.dart';
import '../pdf_stream.dart';
import '../pdf_string.dart';

/// A Web Capture command settings dictionary.
///
/// ISO 32000-1:2008, 14.10.5.4, Table 359. `/G` holds the settings common to
/// every conversion engine and `/C` holds one sub-dictionary per engine, keyed
/// by the engine's internal name.
class PdfWebCaptureCommandSettings extends PdfObjectWrapper<PdfDictionary> {
  /// `/G`, the global conversion engine settings.
  static final PdfName globalSettings = PdfName.intern('G');

  /// `/C`, the per-engine settings.
  static final PdfName engineSettings = PdfName.intern('C');

  PdfWebCaptureCommandSettings(super.pdfObject);

  /// Creates an empty command settings dictionary; an absent entry means the
  /// default settings are used.
  PdfWebCaptureCommandSettings.create() : super(PdfDictionary());

  @override
  bool requiresIndirectStorage() => false;

  /// Sets `/G`.
  PdfWebCaptureCommandSettings setGlobalSettings(PdfDictionary settings) {
    pdfRepresentation().put(globalSettings, settings);
    markChanged();
    return this;
  }

  /// Gets `/G`.
  Future<PdfDictionary?> getGlobalSettings() async =>
      await pdfRepresentation().dictionaryEntry(globalSettings);

  /// Records the settings of one conversion engine under its internal name.
  ///
  /// The name has the form `company:product:version:contentType`; the product
  /// field "may be left blank, but the trailing COLON character is still
  /// required", and no field other than the separators may contain a colon.
  PdfWebCaptureCommandSettings setEngineSettings(
      String engineName, PdfDictionary settings) {
    if (!isValidEngineName(engineName)) {
      throw ArgumentError.value(
          engineName,
          'engineName',
          'A conversion engine name shall read '
              'company:product:version:contentType (14.10.5.4)');
    }
    var container = _engineContainer();
    if (container == null) {
      container = PdfDictionary();
      pdfRepresentation().put(engineSettings, container);
    }
    container.put(PdfName(engineName), settings);
    markChanged();
    return this;
  }

  /// Gets the settings of one conversion engine.
  Future<PdfDictionary?> getEngineSettings(String engineName) async {
    final container = await pdfRepresentation().dictionaryEntry(engineSettings);
    if (container == null) return null;
    final value = await container.get(PdfName(engineName), true);
    return value is PdfDictionary ? value : null;
  }

  /// The internal names of the engines `/C` carries.
  Future<List<String>> engineNames() async {
    final container = await pdfRepresentation().dictionaryEntry(engineSettings);
    final map = container?.getMap();
    if (map == null) return const [];
    return map.keys.map((key) => key.getValue()).toList();
  }

  /// Whether [name] has the `company:product:version:contentType` form of
  /// 14.10.5.4.
  ///
  /// The four fields are separated by exactly three colons; company, version
  /// and content type shall not be empty, while product may be.
  static bool isValidEngineName(String name) {
    final fields = name.split(':');
    if (fields.length != 4) return false;
    return fields[0].isNotEmpty && fields[2].isNotEmpty && fields[3].isNotEmpty;
  }

  /// Reports every way in which this dictionary departs from Table 359.
  Future<List<String>> validate() async {
    final problems = <String>[];
    final dictionary = pdfRepresentation();

    if (dictionary.containsKey(globalSettings) &&
        await getGlobalSettings() == null) {
      problems.add('/G shall be a dictionary (Table 359)');
    }
    if (dictionary.containsKey(engineSettings)) {
      final container = await dictionary.dictionaryEntry(engineSettings);
      if (container == null) {
        problems.add('/C shall be a dictionary (Table 359)');
      } else {
        final map = container.getMap() ?? const <PdfName, PdfObject>{};
        for (final key in map.keys) {
          if (!isValidEngineName(key.getValue())) {
            problems.add('The conversion engine name /${key.getValue()} shall '
                'read company:product:version:contentType (14.10.5.4)');
          }
          if (await container.get(key, true) is! PdfDictionary) {
            problems.add('The settings of /${key.getValue()} shall be a '
                'dictionary (Table 359)');
          }
        }
      }
    }
    return problems;
  }

  PdfDictionary? _engineContainer() {
    final value = pdfRepresentation().getMap()?[engineSettings];
    return value is PdfDictionary ? value : null;
  }
}

/// A Web Capture command dictionary.
///
/// ISO 32000-1:2008, 14.10.5.3, Table 357. It records the parameters of one
/// retrieval command so that the command can be repeated to update the
/// captured content.
class PdfWebCaptureCommand extends PdfObjectWrapper<PdfDictionary> {
  /// `/URL`, the initial URL the source data was requested from.
  static final PdfName url = PdfName.intern('URL');

  /// `/L`, the number of levels of pages retrieved.
  static final PdfName levels = PdfName.intern('L');

  /// `/F`, the command flags of Table 358.
  static final PdfName flags = PdfName.intern('F');

  /// `/P`, the data posted to the URL.
  static final PdfName postedData = PdfName.intern('P');

  /// `/CT`, the content type of the posted data.
  static final PdfName contentType = PdfName.intern('CT');

  /// `/H`, additional HTTP request headers.
  static final PdfName headers = PdfName.intern('H');

  /// `/S`, the command settings dictionary.
  static final PdfName settings = PdfName.intern('S');

  /// Table 358, bit position 1: pages were retrieved only from the host of the
  /// initial URL.
  static const int sameSite = 1;

  /// Table 358, bit position 2: pages were retrieved only from the path of the
  /// initial URL.
  static const int samePath = 2;

  /// Table 358, bit position 3: the command represents a form submission.
  static const int submit = 4;

  /// Every flag Table 358 defines; "all other flags shall be 0".
  static const int definedFlags = sameSite | samePath | submit;

  /// The default of `/L`.
  static const int defaultLevels = 1;

  /// The default of `/CT` for a POST request.
  static const String defaultPostContentType =
      'application/x-www-form-urlencoded';

  PdfWebCaptureCommand(super.pdfObject);

  /// Creates a command dictionary for [initialUrl].
  PdfWebCaptureCommand.create(String initialUrl) : super(PdfDictionary()) {
    setUrl(initialUrl);
  }

  /// Table 350 keeps the commands in an array of indirect references, and a
  /// source information dictionary may only point at one indirectly, so a
  /// command dictionary is always stored as an indirect object.
  @override
  bool requiresIndirectStorage() => true;

  /// Sets `/URL`.
  PdfWebCaptureCommand setUrl(String initialUrl) {
    if (initialUrl.isEmpty) {
      throw ArgumentError.value(initialUrl, 'initialUrl',
          'A Web Capture command /URL is required (Table 357)');
    }
    pdfRepresentation().put(url, PdfString(initialUrl));
    markChanged();
    return this;
  }

  /// Gets `/URL`.
  Future<String?> getUrl() async =>
      (await pdfRepresentation().stringEntry(url))?.getValue();

  /// Sets `/L`, "the number of levels of pages retrieved from the initial
  /// URL".
  PdfWebCaptureCommand setLevels(int value) {
    if (value < 1) {
      throw ArgumentError.value(value, 'value',
          'A Web Capture command /L shall retrieve at least one level');
    }
    pdfRepresentation().put(levels, PdfNumber.fromInt(value));
    markChanged();
    return this;
  }

  /// Gets `/L`; the default is 1, "denoting retrieval of the initial URL
  /// only".
  Future<int> getLevels() async =>
      (await pdfRepresentation().numberEntry(levels))?.intValue() ??
      defaultLevels;

  /// Sets `/F`, a combination of [sameSite], [samePath] and [submit].
  PdfWebCaptureCommand setFlags(int value) {
    if (value & ~definedFlags != 0) {
      throw ArgumentError.value(value, 'value',
          'Only the flags of Table 358 may be set in a Web Capture command /F');
    }
    pdfRepresentation().put(flags, PdfNumber.fromInt(value));
    markChanged();
    return this;
  }

  /// Gets `/F`; the default is 0.
  Future<int> getFlags() async =>
      (await pdfRepresentation().numberEntry(flags))?.intValue() ?? 0;

  /// Whether [flag] is set in `/F`.
  Future<bool> hasFlag(int flag) async => (await getFlags()) & flag == flag;

  /// Sets `/P` to a string, the form the clause suggests for small amounts of
  /// posted data.
  PdfWebCaptureCommand setPostedText(String data) {
    pdfRepresentation().put(postedData, PdfString(data));
    markChanged();
    return this;
  }

  /// Sets `/P` to a stream, the form the clause suggests for large amounts of
  /// posted data "because it can be compressed".
  PdfWebCaptureCommand setPostedStream(PdfStream data) {
    pdfRepresentation().put(postedData, data);
    markChanged();
    return this;
  }

  /// Gets the bytes of `/P`, whatever of the two forms was used.
  Future<Uint8List?> getPostedData() async {
    final value = await pdfRepresentation().get(postedData, true);
    if (value is PdfStream) return await value.getBytes();
    if (value is PdfString) return value.getValueBytes();
    return null;
  }

  /// Whether this command is an HTTP POST request.
  ///
  /// 14.10.5.3: "If no P (posted data) entry is present, the submitted data
  /// shall be encoded in the URL (an HTTP GET request). If P is present, the
  /// command shall be an HTTP POST request."
  bool isPost() => pdfRepresentation().containsKey(postedData);

  /// Sets `/CT`, which "shall only be present for POST requests".
  PdfWebCaptureCommand setContentType(String type) {
    pdfRepresentation().put(contentType, PdfString(type));
    markChanged();
    return this;
  }

  /// Gets `/CT`; the default is `application/x-www-form-urlencoded`.
  Future<String> getContentType() async =>
      (await pdfRepresentation().stringEntry(contentType))?.getValue() ??
      defaultPostContentType;

  /// Sets `/H`, the additional HTTP request headers.
  ///
  /// Each header line is terminated with a CARRIAGE RETURN and a LINE FEED, as
  /// the example of 14.10.5.3 shows. The value is written as a hexadecimal
  /// string (7.3.4.3), because a literal string cannot carry a bare CARRIAGE
  /// RETURN: 7.3.4.2 folds any end-of-line marker inside one down to a single
  /// LINE FEED when the string is read back.
  PdfWebCaptureCommand setHeaders(List<String> headerLines) {
    final buffer = BytesBuilder();
    for (final line in headerLines) {
      buffer.add(latin1.encode(line));
      buffer.add(const [0x0d, 0x0a]);
    }
    pdfRepresentation()
        .put(headers, PdfString.fromBytes(buffer.toBytes(), true));
    markChanged();
    return this;
  }

  /// Gets `/H` split back into header lines.
  ///
  /// A lone LINE FEED separates lines as well, since a producer that stored
  /// the headers in a literal string will have lost the CARRIAGE RETURN.
  Future<List<String>> getHeaders() async {
    final value = await pdfRepresentation().stringEntry(headers);
    if (value == null) return const [];
    return latin1
        .decode(value.getValueBytes() ?? Uint8List(0))
        .split(RegExp(r'\r\n|\n'))
        .where((line) => line.isNotEmpty)
        .toList();
  }

  /// Sets `/S`.
  PdfWebCaptureCommand setSettings(PdfWebCaptureCommandSettings value) {
    pdfRepresentation().put(settings, value.pdfRepresentation());
    markChanged();
    return this;
  }

  /// Gets `/S`.
  Future<PdfWebCaptureCommandSettings?> getSettings() async {
    final dictionary = await pdfRepresentation().dictionaryEntry(settings);
    return dictionary == null ? null : PdfWebCaptureCommandSettings(dictionary);
  }

  /// Reports every way in which this dictionary departs from Tables 357 to
  /// 359.
  Future<List<String>> validate() async {
    final problems = <String>[];
    final dictionary = pdfRepresentation();

    if (await getUrl() == null) {
      problems.add('/URL is required in a Web Capture command dictionary '
          '(Table 357)');
    }

    if (dictionary.containsKey(levels)) {
      final value = (await dictionary.numberEntry(levels))?.intValue();
      if (value == null) {
        problems.add('/L shall be an integer (Table 357)');
      } else if (value < 1) {
        problems.add('/L shall retrieve at least one level (Table 357)');
      }
    }

    if (dictionary.containsKey(flags)) {
      final value = (await dictionary.numberEntry(flags))?.intValue();
      if (value == null) {
        problems.add('/F shall be an integer (Table 357)');
      } else if (value & ~definedFlags != 0) {
        problems.add('Only the flags of Table 358 may be set in /F');
      }
    }

    if (dictionary.containsKey(postedData)) {
      final value = await dictionary.get(postedData, true);
      if (value is! PdfStream && value is! PdfString) {
        problems.add('/P shall be a string or a stream (Table 357)');
      }
    }

    if (dictionary.containsKey(contentType)) {
      if (await dictionary.stringEntry(contentType) == null) {
        problems.add('/CT shall be an ASCII string (Table 357)');
      }
      if (!isPost()) {
        problems.add('/CT shall only be present for POST requests, that is '
            'when /P is present (14.10.5.3)');
      }
    }

    if (dictionary.containsKey(headers) &&
        await dictionary.stringEntry(headers) == null) {
      problems.add('/H shall be a string (Table 357)');
    }

    if (dictionary.containsKey(settings)) {
      final value = await getSettings();
      if (value == null) {
        problems.add('/S shall be a command settings dictionary (Table 357)');
      } else {
        problems.addAll(await value.validate());
      }
    }

    return problems;
  }
}
