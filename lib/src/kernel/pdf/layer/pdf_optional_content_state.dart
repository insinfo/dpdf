import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/layer/pdf_optional_content_config.dart';
import 'package:dpdf/src/kernel/pdf/layer/pdf_optional_content_group.dart';
import 'package:dpdf/src/kernel/pdf/layer/pdf_optional_content_membership.dart';
import 'package:dpdf/src/kernel/pdf/layer/pdf_optional_content_name.dart';

/// The outside factors a reader feeds into the automatic state adjustment of
/// clause 8.11.4.4.
///
/// Every field is optional; a category whose factor is missing yields no
/// recommendation, so the state of the group is left alone.
class PdfOptionalContentUsageContext {
  /// Current magnification, for the `/Zoom` category.
  final double? zoom;

  /// Current language and locale, e.g. `es-MX`, for the `/Language` category.
  final String? language;

  /// Identity of the current user, for the `/User` category.
  final Set<String> userNames;

  const PdfOptionalContentUsageContext(
      {this.zoom, this.language, this.userNames = const <String>{}});
}

/// The resolved ON/OFF state of the optional content groups of a document,
/// ISO 32000-1, clause 8.11.4.5.
///
/// Build one from a configuration dictionary with [fromConfiguration], then
/// ask [isVisible] whether a piece of content that names a group or a
/// membership dictionary should be drawn.
class PdfOptionalContentState {
  /// Group state, keyed by [keyOf].
  final Map<Object, bool> _states = <Object, bool>{};

  /// Every group the state knows about, keyed by [keyOf].
  final Map<Object, PdfDictionary> _groups = <Object, PdfDictionary>{};

  /// Keys of the groups listed in `/Locked`.
  final Set<Object> _locked = <Object>{};

  /// `/RBGroups`, as keys, so that [setGroupOn] can enforce the radio
  /// button behaviour of table 101.
  final List<List<Object>> _radioGroups = <List<Object>>[];

  /// Cache of the intent test, which otherwise re-reads `/Intent` per query.
  final Map<Object, bool> _considered = <Object, bool>{};

  /// The `/Intent` of the configuration this state came from.
  ///
  /// A group takes part in visibility only when one of its own intents is in
  /// this set (clause 8.11.2.3). An empty set means no group does, so all
  /// content is visible.
  final Set<String> intents;

  PdfOptionalContentState({Set<String>? intents})
      : intents = intents ?? <String>{PdfOcName.view.getValue()};

  /// A key that identifies [group] across the resolutions of one document.
  ///
  /// Two references to the same object number may resolve to different
  /// dictionary instances, so the object number is the identity whenever the
  /// group is indirect; direct dictionaries fall back to instance identity.
  static Object keyOf(PdfDictionary group) {
    final reference = group.indirectHandle();
    if (reference != null) return reference.objNr;
    return _Identity(group);
  }

  /// Builds the state a configuration dictionary describes.
  ///
  /// Clause 8.11.4.5 applies `/BaseState` to every group of [allGroups] first
  /// and then overrides it with `/ON` and `/OFF`. A `/BaseState` of
  /// `/Unchanged` keeps whatever [previous] held, or ON when there is none.
  static Future<PdfOptionalContentState> fromConfiguration(
      PdfOptionalContentConfiguration configuration,
      List<PdfDictionary> allGroups,
      {PdfOptionalContentState? previous}) async {
    final intentNames = await configuration.getIntents();
    final state = PdfOptionalContentState(
        intents: intentNames.map((name) => name.getValue()).toSet());

    final baseState = await configuration.getBaseState();
    for (final group in allGroups) {
      final key = keyOf(group);
      state._groups[key] = group;
      if (baseState == PdfOcName.unchanged) {
        state._states[key] = previous?._states[key] ?? true;
      } else {
        state._states[key] = baseState == PdfOcName.on;
      }
    }

    for (final group in await configuration.getOnGroups()) {
      state._put(group, true);
    }
    for (final group in await configuration.getOffGroups()) {
      state._put(group, false);
    }
    for (final group in await configuration.getLockedGroups()) {
      final key = keyOf(group);
      state._groups[key] = group;
      state._locked.add(key);
    }
    for (final set in await configuration.getRadioButtonGroups()) {
      final keys = <Object>[];
      for (final group in set) {
        final key = keyOf(group);
        state._groups[key] = group;
        keys.add(key);
      }
      state._radioGroups.add(keys);
    }
    return state;
  }

  /// The groups this state knows about.
  Iterable<PdfDictionary> get groups => _groups.values;

  /// The raw state of [group], ignoring `/Intent`.
  ///
  /// A group the state never heard of counts as ON: content that names an
  /// unknown group has to keep being drawn.
  bool isGroupOn(PdfDictionary group) => _states[keyOf(group)] ?? true;

  /// Sets the state of [group], honouring `/RBGroups`.
  ///
  /// Turning a group ON turns every other group of each radio set it belongs
  /// to OFF; turning one OFF forces nothing ON (table 101).
  void setGroupOn(PdfDictionary group, bool on) {
    final key = keyOf(group);
    _groups[key] = group;
    _states[key] = on;
    if (!on) return;
    for (final set in _radioGroups) {
      if (!set.contains(key)) continue;
      for (final other in set) {
        if (other != key) _states[other] = false;
      }
    }
  }

  /// Whether `/Locked` forbids a reader from letting the user toggle [group].
  bool isLocked(PdfDictionary group) => _locked.contains(keyOf(group));

  /// Whether [group] takes part in visibility at all (clause 8.11.2.3).
  Future<bool> isConsidered(PdfDictionary group) async {
    final key = keyOf(group);
    final cached = _considered[key];
    if (cached != null) return cached;

    bool result;
    if (intents.isEmpty) {
      result = false;
    } else if (intents.contains(PdfOcName.all.getValue())) {
      result = true;
    } else {
      final groupIntents = await PdfOptionalContentGroup.readIntents(group);
      result = groupIntents.any((intent) =>
          intent == PdfOcName.all || intents.contains(intent.getValue()));
    }
    _considered[key] = result;
    return result;
  }

  /// Whether content controlled by [object] should be drawn.
  ///
  /// [object] is the operand of an `/OC` entry or of an `/OC` marked content
  /// section: a group, a membership dictionary, or an indirect reference to
  /// either. Anything else is not optional content (clause 8.11.3.2), so it is
  /// reported visible.
  Future<bool> isVisible(PdfObject? object) async {
    final dict = await PdfOptionalContentGroup.resolveDictionary(object);
    if (dict == null) return true;

    final membership = await PdfOptionalContentMembership.parse(dict);
    if (membership != null) return _isMembershipVisible(membership);

    final group = await PdfOptionalContentGroup.parse(dict);
    if (group == null) return true;
    if (!await isConsidered(dict)) return true;
    return isGroupOn(dict);
  }

  /// Whether the `/OC` entry of [owner] lets it be drawn.
  ///
  /// This is the test of clause 8.11.3.3 for form and image XObjects and for
  /// annotations; an object without an `/OC` entry is always visible.
  Future<bool> isOwnerVisible(PdfDictionary? owner) async {
    if (owner == null) return true;
    final entry = await owner.get(PdfOcName.oc, false);
    if (entry == null) return true;
    return isVisible(entry);
  }

  /// Whether a `/OC name BDC` section is visible (clause 8.11.3.2).
  ///
  /// [operand] is the second operand of `BDC`: either a name to look up in the
  /// `/Properties` subdictionary of [resources], or an inline dictionary.
  Future<bool> isMarkedContentVisible(
      PdfDictionary? resources, PdfObject? operand) async {
    if (operand is PdfName) {
      final properties = await resources?.dictionaryEntry(PdfOcName.properties);
      if (properties == null) return true;
      return isVisible(await properties.get(operand, false));
    }
    return isVisible(operand);
  }

  /// Applies the usage application dictionaries of [configuration] whose
  /// `/Event` is [event] (clauses 8.11.4.4 and 8.11.4.5).
  ///
  /// A group keeps its current state unless at least one category produced a
  /// recommendation; when several do, or when the group appears in more than
  /// one `/OCGs` array, the state is ON only if every recommendation is ON.
  Future<void> applyUsageApplications(
      PdfOptionalContentConfiguration configuration, PdfName event,
      {PdfOptionalContentUsageContext context =
          const PdfOptionalContentUsageContext()}) async {
    final recommendations = <Object, bool>{};

    for (final application in await configuration.getUsageApplications()) {
      if (await application.getEvent() != event) continue;
      final applicationGroups = await application.getGroups();
      final categories = await application.getCategories();
      if (applicationGroups.isEmpty || categories.isEmpty) continue;

      final languageStates =
          await _languageRecommendations(applicationGroups, context.language);

      for (final group in applicationGroups) {
        final usage =
            await PdfOptionalContentGroup.fromDictionary(group).getUsage();
        if (usage == null) continue;
        final key = keyOf(group);
        _groups[key] = group;

        for (final category in categories) {
          bool? recommendation;
          if (category == PdfOcName.view) {
            recommendation = await usage.getViewState();
          } else if (category == PdfOcName.print) {
            recommendation = await usage.getPrintState();
          } else if (category == PdfOcName.export) {
            recommendation = await usage.getExportState();
          } else if (category == PdfOcName.zoom) {
            recommendation = _zoomRecommendation(context.zoom,
                await usage.getZoomMin(), await usage.getZoomMax());
          } else if (category == PdfOcName.user) {
            recommendation =
                await _userRecommendation(usage, context.userNames);
          } else if (category == PdfOcName.language) {
            recommendation = languageStates[key];
          }
          if (recommendation == null) continue;
          recommendations[key] =
              (recommendations[key] ?? true) && recommendation;
        }
      }
    }

    recommendations.forEach((key, state) => _states[key] = state);
  }

  Future<bool> _isMembershipVisible(
      PdfOptionalContentMembership membership) async {
    final expression = await membership.getVisibilityExpression();
    if (expression != null) {
      // Clause 8.11.2.2 prefers /VE over /OCGs and /P when a reader supports
      // it. The states are resolved up front because evaluation is a plain
      // synchronous walk of the parsed tree.
      final leaves = <PdfDictionary>[];
      expression.collectGroups(leaves);
      final states = <Object, bool>{};
      for (final leaf in leaves) {
        // A group the configuration ignores has no effect on visibility, so
        // it must not be able to hide the expression on its own: it reads ON.
        states[keyOf(leaf)] = await isConsidered(leaf) ? isGroupOn(leaf) : true;
      }
      return expression.evaluate((group) => states[keyOf(group)] ?? true);
    }

    final states = <bool>[];
    for (final group in await membership.getGroups()) {
      if (!await isConsidered(group)) continue;
      states.add(isGroupOn(group));
    }
    return PdfOptionalContentMembership.applyPolicy(
        await membership.getPolicy(), states);
  }

  void _put(PdfDictionary group, bool on) {
    final key = keyOf(group);
    _groups[key] = group;
    _states[key] = on;
  }

  /// `/Zoom`: ON while `min <= zoom < max` (clause 8.11.4.4).
  static bool? _zoomRecommendation(double? zoom, double min, double max) {
    if (zoom == null) return null;
    return zoom >= min && zoom < max;
  }

  /// `/User`: ON on an exact match against the identity of the reader.
  static Future<bool?> _userRecommendation(
      PdfOptionalContentUsage usage, Set<String> userNames) async {
    final names = await usage.getUserNames();
    if (names.isEmpty) return null;
    if (userNames.isEmpty) return false;
    return names.any(userNames.contains);
  }

  /// `/Language`: an exact language and locale match wins; failing that, a
  /// partial match counts only for groups whose `/Preferred` is ON.
  static Future<Map<Object, bool>> _languageRecommendations(
      List<PdfDictionary> groups, String? language) async {
    if (language == null) return const <Object, bool>{};

    final wanted = language.toLowerCase();
    final wantedLanguage = wanted.split('-').first;

    final exact = <Object>{};
    final partial = <Object>{};
    final known = <Object>{};
    for (final group in groups) {
      final usage =
          await PdfOptionalContentGroup.fromDictionary(group).getUsage();
      final tag = (await usage?.getLanguage())?.toLowerCase();
      if (tag == null) continue;
      final key = keyOf(group);
      known.add(key);
      if (tag == wanted) {
        exact.add(key);
      } else if (tag.split('-').first == wantedLanguage) {
        if (await usage?.isLanguagePreferred() ?? false) partial.add(key);
      }
    }

    final result = <Object, bool>{};
    for (final key in known) {
      result[key] =
          exact.isNotEmpty ? exact.contains(key) : partial.contains(key);
    }
    return result;
  }
}

/// Wraps a direct dictionary so that a map keyed by [PdfOptionalContentState.keyOf]
/// can use instance identity without colliding with object numbers.
class _Identity {
  final PdfDictionary value;

  const _Identity(this.value);

  @override
  bool operator ==(Object other) =>
      other is _Identity && identical(other.value, value);

  @override
  int get hashCode => identityHashCode(value);
}
