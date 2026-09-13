import '../pdf_array.dart';
import '../pdf_boolean.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';
import '../pdf_object_wrapper.dart';
import '../pdf_string.dart';

/// Monitor specifier values.
///
/// See ISO 32000-1:2008, 13.2.7.5 "Monitor Specifier", Table 293.
abstract final class PdfMonitorSpecifier {
  /// The monitor containing the largest section of the document window.
  static const int documentMonitor = 0;

  /// The monitor containing the smallest section of the document window.
  static const int smallestSection = 1;

  /// The primary monitor; treated as [documentMonitor] when none is primary.
  static const int primary = 2;

  /// The monitor with the greatest colour depth.
  static const int greatestColourDepth = 3;

  /// The monitor with the greatest area, in pixels squared.
  static const int greatestArea = 4;

  /// The monitor with the greatest height, in pixels.
  static const int greatestHeight = 5;

  /// The monitor with the greatest width, in pixels.
  static const int greatestWidth = 6;

  /// Whether [value] is one of the values of Table 293. An unrecognised
  /// monitor specifier makes the enclosing object non-viable.
  static bool isValid(int value) => value >= 0 && value <= 6;

  /// Validates [value], throwing when it is outside Table 293.
  static int check(int value, String name) {
    if (!isValid(value)) {
      throw ArgumentError.value(
          value, name, 'Monitor specifier shall lie in [0, 6] (Table 293)');
    }
    return value;
  }
}

/// Software identifier dictionary.
///
/// See ISO 32000-1:2008, 13.2.7.4 "Software Identifier Dictionary", Table 292.
class PdfSoftwareIdentifier extends PdfObjectWrapper<PdfDictionary> {
  /// `/Type /SoftwareIdentifier`.
  static final PdfName typeValue = PdfName.intern('SoftwareIdentifier');

  /// The only URI scheme defined by 13.2.7.4.2 "Software URIs".
  static const String swNameScheme = 'vnd.adobe.swname';

  static final PdfName _l = PdfName.intern('L');
  static final PdfName _li = PdfName.intern('LI');
  static final PdfName _h = PdfName.intern('H');
  static final PdfName _hi = PdfName.intern('HI');
  static final PdfName _os = PdfName.intern('OS');

  PdfSoftwareIdentifier(super.pdfObject);

  /// Creates a software identifier for the URI [uri]. `/U` is required by
  /// Table 292.
  PdfSoftwareIdentifier.forUri(String uri) : super(PdfDictionary()) {
    if (uri.isEmpty) {
      throw ArgumentError.value(
          uri, 'uri', 'Software identifier /U is required (Table 292)');
    }
    pdfRepresentation()
      ..put(PdfName.type, typeValue)
      ..put(PdfName.u, PdfString(uri));
  }

  /// Creates a software identifier for the software name [name], building the
  /// `vnd.adobe.swname:` URI described in 13.2.7.4.2.
  factory PdfSoftwareIdentifier.forSoftwareName(String name) {
    if (name.isEmpty) {
      throw ArgumentError.value(
          name, 'name', 'Software name shall not be empty');
    }
    return PdfSoftwareIdentifier.forUri(
        '$swNameScheme:${escapeSoftwareName(name)}');
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Gets `/U`, the software URI.
  Future<String?> getUri() async =>
      (await pdfRepresentation().stringEntry(PdfName.u))?.getValue();

  /// Gets the software name encoded in `/U`, or null when `/U` does not use
  /// the `vnd.adobe.swname` scheme. The scheme name is case-insensitive
  /// (13.2.7.4.2); the software name itself is case-sensitive.
  Future<String?> getSoftwareName() async {
    final uri = await getUri();
    if (uri == null) return null;
    final separator = uri.indexOf(':');
    if (separator < 0) return null;
    if (uri.substring(0, separator).toLowerCase() != swNameScheme) return null;
    return unescapeSoftwareName(uri.substring(separator + 1));
  }

  /// Sets `/L`, the lower bound version array. Table 292 forbids negative
  /// subversion numbers.
  PdfSoftwareIdentifier setLowVersion(List<int> version) {
    pdfRepresentation().put(_l, _versionArray(version, 'version'));
    return this;
  }

  /// Gets `/L`; the default of Table 292 is `[0]`.
  Future<List<int>> getLowVersion() async =>
      await (await pdfRepresentation().arrayEntry(_l))?.toIntArray() ??
      const <int>[0];

  /// Sets `/H`, the upper bound version array.
  PdfSoftwareIdentifier setHighVersion(List<int> version) {
    pdfRepresentation().put(_h, _versionArray(version, 'version'));
    return this;
  }

  /// Gets `/H`; the default of Table 292 is the empty array, which
  /// 13.2.7.4.3 defines as infinity.
  Future<List<int>> getHighVersion() async =>
      await (await pdfRepresentation().arrayEntry(_h))?.toIntArray() ??
      const <int>[];

  /// Sets `/LI`, whether the lower bound is inclusive.
  PdfSoftwareIdentifier setLowInclusive(bool inclusive) {
    pdfRepresentation().put(_li, PdfBoolean(inclusive));
    return this;
  }

  /// Gets `/LI`; the default is true per Table 292.
  Future<bool> isLowInclusive() async =>
      (await pdfRepresentation().booleanEntry(_li))?.getValue() ?? true;

  /// Sets `/HI`, whether the upper bound is inclusive.
  PdfSoftwareIdentifier setHighInclusive(bool inclusive) {
    pdfRepresentation().put(_hi, PdfBoolean(inclusive));
    return this;
  }

  /// Gets `/HI`; the default is true per Table 292.
  Future<bool> isHighInclusive() async =>
      (await pdfRepresentation().booleanEntry(_hi))?.getValue() ?? true;

  /// Sets `/OS`, the operating system identifiers this object applies to.
  /// Table 292 forbids duplicates; an empty array means all systems.
  PdfSoftwareIdentifier setOperatingSystems(List<String> identifiers) {
    final seen = <String>{};
    for (final identifier in identifiers) {
      if (!seen.add(identifier)) {
        throw ArgumentError.value(identifiers, 'identifiers',
            'Software identifier /OS shall not repeat an identifier');
      }
    }
    pdfRepresentation().put(_os, PdfArray.fromStrings(identifiers));
    return this;
  }

  /// Gets `/OS`; the default is the empty array, meaning all systems.
  Future<List<String>> getOperatingSystems() async {
    final array = await pdfRepresentation().arrayEntry(_os);
    if (array == null) return const <String>[];
    final result = <String>[];
    for (var i = 0; i < array.size(); i++) {
      final value = await array.stringEntry(i);
      if (value != null) result.add(value.getValue());
    }
    return result;
  }

  /// Applies the "Software identifier" algorithm of 13.2.7.4.1 to decide
  /// whether the software named [name], of version [version], running on the
  /// operating system [operatingSystem], matches this dictionary.
  Future<bool> matches(String name, List<int> version,
      {String? operatingSystem}) async {
    if (await getSoftwareName() != name) return false;

    final low = await getLowVersion();
    final lowComparison = compareVersions(version, low);
    if (await isLowInclusive() ? lowComparison < 0 : lowComparison <= 0) {
      return false;
    }

    final high = await getHighVersion();
    final highComparison = compareVersions(version, high);
    if (await isHighInclusive() ? highComparison > 0 : highComparison >= 0) {
      return false;
    }

    final systems = await getOperatingSystems();
    if (systems.isEmpty) return true;
    return operatingSystem != null && systems.contains(operatingSystem);
  }

  static PdfArray _versionArray(List<int> version, String name) {
    for (final part in version) {
      if (part < 0) {
        throw ArgumentError.value(version, name,
            'Version arrays shall not contain negative numbers (13.2.7.4.3)');
      }
    }
    return PdfArray.fromInts(version);
  }
}

/// Compares two version arrays following the "Comparing version arrays"
/// algorithm of ISO 32000-1:2008, 13.2.7.4.3.
///
/// An empty array is infinity; shorter arrays are padded with zeros.
int compareVersions(List<int> first, List<int> second) {
  final firstInfinite = first.isEmpty;
  final secondInfinite = second.isEmpty;
  if (firstInfinite || secondInfinite) {
    if (firstInfinite && secondInfinite) return 0;
    return firstInfinite ? 1 : -1;
  }
  final length = first.length > second.length ? first.length : second.length;
  for (var i = 0; i < length; i++) {
    final a = i < first.length ? first[i] : 0;
    final b = i < second.length ? second[i] : 0;
    if (a != b) return a < b ? -1 : 1;
  }
  return 0;
}

/// Applies one pass of URL escaping to a software name, as required by
/// ISO 32000-1:2008, 13.2.7.4.2 "Software URIs": the name is UTF-8 encoded
/// and escaped once, leaving only RFC 2396 unreserved characters.
String escapeSoftwareName(String name) => Uri.encodeComponent(name);

/// Reverses [escapeSoftwareName], decoding the result as UTF-8.
String unescapeSoftwareName(String escaped) {
  try {
    return Uri.decodeComponent(escaped);
  } on ArgumentError {
    return escaped;
  } on FormatException {
    return escaped;
  }
}

/// Media player info dictionary.
///
/// See ISO 32000-1:2008, 13.2.7.3 "Media Player Info Dictionary", Table 291.
class PdfMediaPlayerInfo extends PdfObjectWrapper<PdfDictionary> {
  /// `/Type /MediaPlayerInfo`.
  static final PdfName typeValue = PdfName.intern('MediaPlayerInfo');

  PdfMediaPlayerInfo(super.pdfObject);

  /// Creates a media player info dictionary. `/PID` is required by Table 291.
  PdfMediaPlayerInfo.forPlayer(PdfSoftwareIdentifier player)
      : super(PdfDictionary()) {
    pdfRepresentation()
      ..put(PdfName.type, typeValue)
      ..put(PdfName.intern('PID'), player.pdfRepresentation());
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Gets `/PID`, the software identifier of the player.
  Future<PdfSoftwareIdentifier?> getPlayerId() async {
    final dictionary =
        await pdfRepresentation().dictionaryEntry(PdfName.intern('PID'));
    return dictionary == null ? null : PdfSoftwareIdentifier(dictionary);
  }
}

/// Media players dictionary.
///
/// See ISO 32000-1:2008, 13.2.7.2 "Media Players Dictionary", Table 290.
class PdfMediaPlayers extends PdfObjectWrapper<PdfDictionary> {
  /// `/Type /MediaPlayers`.
  static final PdfName typeValue = PdfName.intern('MediaPlayers');

  static final PdfName _mu = PdfName.intern('MU');
  static final PdfName _nu = PdfName.intern('NU');

  PdfMediaPlayers(super.pdfObject);

  /// Creates an empty media players dictionary.
  PdfMediaPlayers.create() : super(PdfDictionary()) {
    pdfRepresentation().put(PdfName.type, typeValue);
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Sets `/MU`, the players one of which shall be used.
  PdfMediaPlayers setMustUse(List<PdfMediaPlayerInfo> players) =>
      _setArray(_mu, players);

  /// Gets `/MU`.
  Future<List<PdfMediaPlayerInfo>> getMustUse() => _getArray(_mu);

  /// Sets `/A`, the players any of which may be used.
  PdfMediaPlayers setAllowed(List<PdfMediaPlayerInfo> players) =>
      _setArray(PdfName.a, players);

  /// Gets `/A`.
  Future<List<PdfMediaPlayerInfo>> getAllowed() => _getArray(PdfName.a);

  /// Sets `/NU`, the players that shall not be used.
  PdfMediaPlayers setNeverUse(List<PdfMediaPlayerInfo> players) =>
      _setArray(_nu, players);

  /// Gets `/NU`.
  Future<List<PdfMediaPlayerInfo>> getNeverUse() => _getArray(_nu);

  PdfMediaPlayers _setArray(PdfName key, List<PdfMediaPlayerInfo> players) {
    pdfRepresentation().put(
        key,
        PdfArray.fromList(
            players.map((player) => player.pdfRepresentation()).toList()));
    return this;
  }

  Future<List<PdfMediaPlayerInfo>> _getArray(PdfName key) async {
    final array = await pdfRepresentation().arrayEntry(key);
    if (array == null) return const <PdfMediaPlayerInfo>[];
    final result = <PdfMediaPlayerInfo>[];
    for (var i = 0; i < array.size(); i++) {
      final dictionary = await array.dictionaryEntry(i);
      if (dictionary != null) result.add(PdfMediaPlayerInfo(dictionary));
    }
    return result;
  }

  /// Applies the "Media Player" algorithm of 13.2.7.2 to decide whether the
  /// player named [name] of version [version] may be used, given this
  /// dictionary and the optional second one carried by the other of the media
  /// clip data / media play parameters pair.
  ///
  /// [contentTypeKnown] reports whether a `/CT` entry identifies the content
  /// type, and [playerSupportsContentType] whether the player supports it.
  Future<bool> mayUsePlayer(String name, List<int> version,
      {PdfMediaPlayers? other,
      String? operatingSystem,
      bool contentTypeKnown = false,
      bool playerSupportsContentType = true}) async {
    // a) The content type is known and the player does not support the type.
    if (contentTypeKnown && !playerSupportsContentType) return false;

    Future<bool> found(Future<List<PdfMediaPlayerInfo>> Function() reader) =>
        _contains(reader, name, version, operatingSystem);

    // b) The player is found in the NU array of either dictionary.
    if (await found(getNeverUse)) return false;
    if (other != null && await found(other.getNeverUse)) return false;

    final thisMustUse = await getMustUse();
    final otherMustUse =
        other == null ? const <PdfMediaPlayerInfo>[] : await other.getMustUse();

    // c) Non-empty MU arrays constrain the choice.
    if (thisMustUse.isNotEmpty || otherMustUse.isNotEmpty) {
      if (thisMustUse.isNotEmpty &&
          !await _matchAny(thisMustUse, name, version, operatingSystem)) {
        return false;
      }
      if (otherMustUse.isNotEmpty &&
          !await _matchAny(otherMustUse, name, version, operatingSystem)) {
        return false;
      }
      return true;
    }

    // d) No MU array, unknown content type: the player shall be in some A.
    if (!contentTypeKnown) {
      if (await found(getAllowed)) return true;
      if (other != null && await found(other.getAllowed)) return true;
      return false;
    }
    return true;
  }

  Future<bool> _contains(Future<List<PdfMediaPlayerInfo>> Function() reader,
          String name, List<int> version, String? operatingSystem) async =>
      _matchAny(await reader(), name, version, operatingSystem);

  static Future<bool> _matchAny(List<PdfMediaPlayerInfo> players, String name,
      List<int> version, String? operatingSystem) async {
    for (final player in players) {
      final id = await player.getPlayerId();
      if (id != null &&
          await id.matches(name, version, operatingSystem: operatingSystem)) {
        return true;
      }
    }
    return false;
  }
}

/// Builds a `/MH` or `/BE` viability dictionary holder shared by several
/// multimedia objects (13.2.2 "Viability").
mixin PdfViabilityAware {
  /// The dictionary carrying `/MH` and `/BE`.
  PdfDictionary viabilityOwner();

  /// Gets (creating when absent) the `/MH` dictionary, whose entries shall be
  /// honoured for the object to be viable.
  PdfDictionary mustHonour() => _ensure(PdfName.intern('MH'));

  /// Gets (creating when absent) the `/BE` dictionary, whose entries are
  /// honoured only in a best-effort sense.
  PdfDictionary bestEffort() => _ensure(PdfName.intern('BE'));

  /// Reads `/MH` without creating it.
  Future<PdfDictionary?> readMustHonour() async =>
      await viabilityOwner().dictionaryEntry(PdfName.intern('MH'));

  /// Reads `/BE` without creating it.
  Future<PdfDictionary?> readBestEffort() async =>
      await viabilityOwner().dictionaryEntry(PdfName.intern('BE'));

  PdfDictionary _ensure(PdfName key) {
    final owner = viabilityOwner();
    final existing = owner.getMap()?[key];
    if (existing is PdfDictionary) return existing;
    final created = PdfDictionary();
    owner.put(key, created);
    return created;
  }
}

/// Writes an integer into a dictionary, validating a closed range.
void putRangedInt(PdfDictionary dictionary, PdfName key, int value, int min,
    int max, String message) {
  if (value < min || value > max) {
    throw ArgumentError.value(value, key.getValue(), message);
  }
  dictionary.put(key, PdfNumber.fromInt(value));
}
