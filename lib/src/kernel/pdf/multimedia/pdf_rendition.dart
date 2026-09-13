import '../pdf_array.dart';
import '../pdf_catalog.dart';
import '../pdf_dictionary.dart';
import '../pdf_document.dart';
import '../pdf_name.dart';
import '../pdf_object_wrapper.dart';
import '../pdf_string.dart';
import 'pdf_media_clip.dart';
import 'pdf_media_criteria.dart';
import 'pdf_media_play_params.dart';
import 'pdf_media_screen_params.dart';
import 'pdf_software_identifier.dart';

/// Base class of the rendition objects of ISO 32000-1:2008, 13.2.3.
///
/// Table 266 lists the entries common to all rendition dictionaries. 13.2.3.1
/// says that all rendition objects should be indirect objects, because the
/// `/Renditions` name tree may only reference indirect objects.
abstract class PdfRendition extends PdfObjectWrapper<PdfDictionary>
    with PdfViabilityAware {
  /// `/Type /Rendition`.
  static final PdfName typeValue = PdfName.intern('Rendition');

  /// `/S /MR`: a media rendition (13.2.3.2).
  static final PdfName subtypeMedia = PdfName.intern('MR');

  /// `/S /SR`: a selector rendition (13.2.3.3).
  static final PdfName subtypeSelector = PdfName.intern('SR');

  /// The `/Renditions` name tree of the document name dictionary (Table 31).
  static final PdfName renditionsTree = PdfName.intern('Renditions');

  PdfRendition(super.pdfObject);

  @override
  bool requiresIndirectStorage() => true;

  @override
  PdfDictionary viabilityOwner() => pdfRepresentation();

  /// Gets `/S`, the rendition subtype.
  Future<PdfName?> getSubtype() async =>
      await pdfRepresentation().nameEntry(PdfName.s);

  /// Sets `/N`, the rendition name used in the user interface and for name
  /// tree lookup from JavaScript actions.
  PdfRendition setName(String name) {
    pdfRepresentation().put(PdfName.n, PdfString(name));
    return this;
  }

  /// Gets `/N`.
  Future<String?> getName() async =>
      (await pdfRepresentation().stringEntry(PdfName.n))?.decodeMappingText();

  /// Sets `/C` in the `/MH` dictionary, the media criteria that shall be met
  /// for this rendition to be viable (Table 267).
  PdfRendition setMustHonourCriteria(PdfMediaCriteria criteria) {
    mustHonour().put(PdfName.c, criteria.pdfRepresentation());
    return this;
  }

  /// Sets `/C` in the `/BE` dictionary, the best-effort media criteria.
  PdfRendition setBestEffortCriteria(PdfMediaCriteria criteria) {
    bestEffort().put(PdfName.c, criteria.pdfRepresentation());
    return this;
  }

  /// Gets the `/MH` media criteria dictionary.
  Future<PdfMediaCriteria?> getMustHonourCriteria() async {
    final dictionary =
        await (await readMustHonour())?.dictionaryEntry(PdfName.c);
    return dictionary == null ? null : PdfMediaCriteria(dictionary);
  }

  /// Gets the `/BE` media criteria dictionary.
  Future<PdfMediaCriteria?> getBestEffortCriteria() async {
    final dictionary =
        await (await readBestEffort())?.dictionaryEntry(PdfName.c);
    return dictionary == null ? null : PdfMediaCriteria(dictionary);
  }

  /// Registers this rendition in the document's `/Renditions` name tree
  /// (Table 31) under its `/N` name, as 13.2.3.1 describes. The note there
  /// asks that the name in the tree match the `/N` entry.
  Future<PdfRendition> registerIn(PdfDocument document) async {
    final name = await getName();
    if (name == null) {
      throw StateError(
          'A rendition shall have an /N entry to be added to the /Renditions '
          'name tree (13.2.3.1)');
    }
    attachToDocument(document);
    final PdfCatalog catalog = document.rootCatalog();
    await catalog.addNameToNameTree(
        PdfString(name), pdfRepresentation(), renditionsTree);
    return this;
  }

  /// Reads the rendition stored in [dictionary], returning the concrete
  /// subclass identified by `/S`, or null when `/S` is unrecognised (which
  /// Table 266 makes non-viable).
  static Future<PdfRendition?> read(PdfDictionary dictionary) async {
    final subtype = (await dictionary.nameEntry(PdfName.s))?.getValue();
    if (subtype == 'MR') return PdfMediaRendition(dictionary);
    if (subtype == 'SR') return PdfSelectorRendition(dictionary);
    return null;
  }
}

/// Media rendition dictionary.
///
/// See ISO 32000-1:2008, 13.2.3.2 "Media Renditions", Table 271.
class PdfMediaRendition extends PdfRendition {
  static final PdfName _sp = PdfName.intern('SP');

  PdfMediaRendition(super.pdfObject);

  /// Creates a media rendition playing [clip].
  ///
  /// Table 271 allows `/C` to be omitted only when `/P` names a media players
  /// dictionary with a non-empty `/MU` or `/A` array; [PdfMediaRendition.withoutClip]
  /// covers that case.
  PdfMediaRendition.forClip(PdfMediaClip clip) : super(PdfDictionary()) {
    pdfRepresentation()
      ..put(PdfName.type, PdfRendition.typeValue)
      ..put(PdfName.s, PdfRendition.subtypeMedia)
      ..put(PdfName.c, clip.pdfRepresentation());
  }

  /// Creates a media rendition without `/C`, for a player that takes no
  /// meaningful input. Table 271 then requires `/P`, whose `/PL` media
  /// players dictionary shall have a non-empty `/MU` or `/A` array.
  static Future<PdfMediaRendition> withoutClip(
      PdfMediaPlayParams playParams) async {
    final players = await playParams.getPlayers();
    final hasPlayer = players != null &&
        ((await players.getMustUse()).isNotEmpty ||
            (await players.getAllowed()).isNotEmpty);
    if (!hasPlayer) {
      throw ArgumentError.value(
          playParams,
          'playParams',
          'A media rendition without /C requires /P with a /PL media players '
              'dictionary having a non-empty /MU or /A array (Table 271)');
    }
    final rendition = PdfMediaRendition(PdfDictionary());
    rendition.pdfRepresentation()
      ..put(PdfName.type, PdfRendition.typeValue)
      ..put(PdfName.s, PdfRendition.subtypeMedia);
    rendition.setPlayParams(playParams);
    return rendition;
  }

  /// Sets `/C`, the media clip that says what to play.
  PdfMediaRendition setClip(PdfMediaClip clip) {
    pdfRepresentation().put(PdfName.c, clip.pdfRepresentation());
    return this;
  }

  /// Gets `/C`.
  Future<PdfMediaClip?> getClip() async {
    final dictionary = await pdfRepresentation().dictionaryEntry(PdfName.c);
    return dictionary == null ? null : await PdfMediaClip.read(dictionary);
  }

  /// Sets `/P`, the media play parameters saying how to play the rendition.
  PdfMediaRendition setPlayParams(PdfMediaPlayParams playParams) {
    pdfRepresentation().put(PdfName.p, playParams.pdfRepresentation());
    return this;
  }

  /// Gets `/P`; Table 271 defaults it to a play parameters dictionary whose
  /// entries all hold their default values.
  Future<PdfMediaPlayParams?> getPlayParams() async {
    final dictionary = await pdfRepresentation().dictionaryEntry(PdfName.p);
    return dictionary == null ? null : PdfMediaPlayParams(dictionary);
  }

  /// Sets `/SP`, the media screen parameters saying where to play the
  /// rendition.
  PdfMediaRendition setScreenParams(PdfMediaScreenParams screenParams) {
    pdfRepresentation().put(_sp, screenParams.pdfRepresentation());
    return this;
  }

  /// Gets `/SP`; Table 271 defaults it to a screen parameters dictionary
  /// whose entries all hold their default values.
  Future<PdfMediaScreenParams?> getScreenParams() async {
    final dictionary = await pdfRepresentation().dictionaryEntry(_sp);
    return dictionary == null ? null : PdfMediaScreenParams(dictionary);
  }

  /// Whether the structural requirement of Table 271 holds: `/C` may be
  /// omitted only when `/P` names players that take no meaningful input.
  Future<bool> isStructurallyViable() async {
    if (await getClip() != null) return true;
    final playParams = await getPlayParams();
    if (playParams == null) return false;
    final players = await playParams.getPlayers();
    if (players == null) return false;
    return (await players.getMustUse()).isNotEmpty ||
        (await players.getAllowed()).isNotEmpty;
  }
}

/// Selector rendition dictionary.
///
/// See ISO 32000-1:2008, 13.2.3.3 "Selector Renditions", Table 272.
class PdfSelectorRendition extends PdfRendition {
  PdfSelectorRendition(super.pdfObject);

  /// Creates a selector rendition over [renditions], ordered by preference.
  /// `/R` is required by Table 272, though an empty array is legal.
  PdfSelectorRendition.of(List<PdfRendition> renditions)
      : super(PdfDictionary()) {
    pdfRepresentation()
      ..put(PdfName.type, PdfRendition.typeValue)
      ..put(PdfName.s, PdfRendition.subtypeSelector)
      ..put(
          PdfName.r,
          PdfArray.fromList(renditions
              .map((rendition) => rendition.pdfRepresentation())
              .toList()));
  }

  /// Gets `/R`, the ordered list of candidate renditions.
  Future<List<PdfRendition>> getRenditions() async {
    final array = await pdfRepresentation().arrayEntry(PdfName.r);
    if (array == null) return const <PdfRendition>[];
    final result = <PdfRendition>[];
    for (var i = 0; i < array.size(); i++) {
      final dictionary = await array.dictionaryEntry(i);
      if (dictionary == null) continue;
      final rendition = await PdfRendition.read(dictionary);
      if (rendition != null) result.add(rendition);
    }
    return result;
  }

  /// Performs the depth-first search of 13.2.3.3, returning the first media
  /// rendition reachable from this selector. [isViable] decides whether a
  /// rendition is usable; a non-viable selector prunes its whole branch.
  Future<PdfMediaRendition?> firstViableMediaRendition(
      Future<bool> Function(PdfRendition rendition) isViable) async {
    final visited = <PdfDictionary>{};

    Future<PdfMediaRendition?> walk(PdfRendition rendition) async {
      if (!visited.add(rendition.pdfRepresentation())) return null;
      if (!await isViable(rendition)) return null;
      if (rendition is PdfMediaRendition) return rendition;
      for (final child
          in await (rendition as PdfSelectorRendition).getRenditions()) {
        final found = await walk(child);
        if (found != null) return found;
      }
      return null;
    }

    return await walk(this);
  }
}
