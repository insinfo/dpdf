import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object_wrapper.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'package:dpdf/src/kernel/pdf/layer/pdf_optional_content_group.dart';
import 'package:dpdf/src/kernel/pdf/layer/pdf_optional_content_name.dart';
import 'package:dpdf/src/kernel/pdf/layer/pdf_optional_content_text.dart';

/// One entry of the `/Order` array of a configuration dictionary
/// (ISO 32000-1, table 101).
///
/// An entry is either a group, or a nested list of entries that a reader may
/// show as a subtree. A nested list whose first element is a text string uses
/// that string as a non-selectable [label].
class PdfOptionalContentOrder {
  /// The group this entry stands for, or null for a nested list.
  final PdfDictionary? group;

  /// The label of a nested list, or null when it has none.
  final String? label;

  /// The children of a nested list; empty for a group entry.
  final List<PdfOptionalContentOrder> children;

  const PdfOptionalContentOrder.group(PdfDictionary this.group)
      : label = null,
        children = const <PdfOptionalContentOrder>[];

  const PdfOptionalContentOrder.nested(this.children, {this.label})
      : group = null;

  /// Whether this entry is a group rather than a nested list.
  bool get isGroup => group != null;
}

/// A usage application dictionary, ISO 32000-1, clause 8.11.4.4 (table 103).
///
/// It says which usage categories a reader should consult to set the state of
/// which groups, and on which occasion (`/View`, `/Print` or `/Export`).
class PdfUsageApplication extends PdfObjectWrapper<PdfDictionary> {
  PdfUsageApplication(PdfName event, List<PdfOptionalContentGroup> groups,
      List<PdfName> categories)
      : super(PdfDictionary()) {
    pdfRepresentation()
      ..put(PdfOcName.event, event)
      ..put(
          PdfOcName.ocgs,
          PdfArray.fromList(groups
              .map<PdfObject>((group) => group.pdfRepresentation())
              .toList(growable: false)))
      ..put(PdfOcName.category,
          PdfArray.fromList(List<PdfObject>.of(categories)));
  }

  PdfUsageApplication.fromDictionary(super.pdfObject);

  @override
  bool requiresIndirectStorage() => false;

  /// The `/Event` entry: `/View`, `/Print` or `/Export`.
  Future<PdfName?> getEvent() =>
      pdfRepresentation().nameEntry(PdfOcName.event);

  /// The `/OCGs` entry; an absent entry means no group is affected.
  Future<List<PdfDictionary>> getGroups() async =>
      readGroupArray(await pdfRepresentation().arrayEntry(PdfOcName.ocgs));

  /// The `/Category` entry: the usage dictionary keys to consult.
  Future<List<PdfName>> getCategories() async {
    final array = await pdfRepresentation().arrayEntry(PdfOcName.category);
    if (array == null) return const <PdfName>[];
    final names = <PdfName>[];
    for (var i = 0; i < array.size(); i++) {
      final name = await array.nameEntry(i);
      if (name != null) names.add(name);
    }
    return names;
  }

  /// Resolves an array of group references, dropping anything that is not an
  /// `/OCG` dictionary.
  static Future<List<PdfDictionary>> readGroupArray(PdfArray? array) async {
    if (array == null) return <PdfDictionary>[];
    final groups = <PdfDictionary>[];
    for (var i = 0; i < array.size(); i++) {
      final group = await PdfOptionalContentGroup.parse(await array.get(i));
      if (group != null) groups.add(group.pdfRepresentation());
    }
    return groups;
  }
}

/// An optional content configuration dictionary, ISO 32000-1, clause 8.11.4.3
/// (table 101).
///
/// The `/D` configuration of the properties dictionary sets the state of every
/// group when the document is opened; the entries of `/Configs` are alternate
/// presentations a reader may offer instead.
class PdfOptionalContentConfiguration extends PdfObjectWrapper<PdfDictionary> {
  PdfOptionalContentConfiguration() : super(PdfDictionary());

  PdfOptionalContentConfiguration.fromDictionary(super.pdfObject);

  @override
  bool requiresIndirectStorage() => false;

  /// The `/Name` entry: a label for this configuration.
  Future<String?> getName() async {
    final value = await pdfRepresentation().stringEntry(PdfOcName.name);
    return value == null ? null : readOcTextString(value);
  }

  void setName(String name) {
    pdfRepresentation().put(PdfOcName.name, makeOcTextString(name));
  }

  /// The `/Creator` entry: the application that wrote this configuration.
  Future<String?> getCreator() async {
    final value = await pdfRepresentation().stringEntry(PdfOcName.creator);
    return value == null ? null : readOcTextString(value);
  }

  void setCreator(String creator) {
    pdfRepresentation().put(PdfOcName.creator, makeOcTextString(creator));
  }

  /// The `/BaseState` entry: `/ON`, `/OFF` or `/Unchanged`; defaults to `/ON`.
  Future<PdfName> getBaseState() async {
    final value = await pdfRepresentation().nameEntry(PdfOcName.baseState);
    if (value == PdfOcName.off || value == PdfOcName.unchanged) return value!;
    return PdfOcName.on;
  }

  void setBaseState(PdfName baseState) {
    pdfRepresentation().put(PdfOcName.baseState, baseState);
  }

  /// The `/ON` array: groups forced ON when this configuration is applied.
  Future<List<PdfDictionary>> getOnGroups() async => PdfUsageApplication
      .readGroupArray(await pdfRepresentation().arrayEntry(PdfOcName.on));

  /// The `/OFF` array: groups forced OFF when this configuration is applied.
  Future<List<PdfDictionary>> getOffGroups() async => PdfUsageApplication
      .readGroupArray(await pdfRepresentation().arrayEntry(PdfOcName.off));

  void setOnGroups(List<PdfOptionalContentGroup> groups) {
    pdfRepresentation().put(PdfOcName.on, _groupArray(groups));
  }

  void setOffGroups(List<PdfOptionalContentGroup> groups) {
    pdfRepresentation().put(PdfOcName.off, _groupArray(groups));
  }

  /// The `/Intent` entry as a list; defaults to `[/View]` (table 101).
  Future<List<PdfName>> getIntents() =>
      PdfOptionalContentGroup.readIntents(pdfRepresentation());

  void setIntents(List<PdfName> intents) {
    if (intents.length == 1) {
      pdfRepresentation().put(PdfOcName.intent, intents.first);
      return;
    }
    pdfRepresentation()
        .put(PdfOcName.intent, PdfArray.fromList(List<PdfObject>.of(intents)));
  }

  /// The `/Locked` array: groups a reader must not let the user toggle.
  Future<List<PdfDictionary>> getLockedGroups() async => PdfUsageApplication
      .readGroupArray(await pdfRepresentation().arrayEntry(PdfOcName.locked));

  void setLockedGroups(List<PdfOptionalContentGroup> groups) {
    pdfRepresentation().put(PdfOcName.locked, _groupArray(groups));
  }

  /// The `/ListMode` entry: `/AllPages` or `/VisiblePages`; defaults to
  /// `/AllPages`.
  Future<PdfName> getListMode() async {
    final value = await pdfRepresentation().nameEntry(PdfOcName.listMode);
    return value == PdfOcName.visiblePages ? value! : PdfOcName.allPages;
  }

  void setListMode(PdfName listMode) {
    pdfRepresentation().put(PdfOcName.listMode, listMode);
  }

  /// The `/RBGroups` entry: sets of groups that behave like radio buttons.
  Future<List<List<PdfDictionary>>> getRadioButtonGroups() async {
    final array = await pdfRepresentation().arrayEntry(PdfOcName.rbGroups);
    if (array == null) return <List<PdfDictionary>>[];
    final result = <List<PdfDictionary>>[];
    for (var i = 0; i < array.size(); i++) {
      final inner = await array.arrayEntry(i);
      if (inner == null) continue;
      final groups = await PdfUsageApplication.readGroupArray(inner);
      if (groups.isNotEmpty) result.add(groups);
    }
    return result;
  }

  void setRadioButtonGroups(List<List<PdfOptionalContentGroup>> sets) {
    final array = PdfArray();
    for (final set in sets) {
      array.add(_groupArray(set));
    }
    pdfRepresentation().put(PdfOcName.rbGroups, array);
  }

  /// The `/AS` array of usage application dictionaries (table 103).
  Future<List<PdfUsageApplication>> getUsageApplications() async {
    final array = await pdfRepresentation().arrayEntry(PdfOcName.autoStates);
    if (array == null) return const <PdfUsageApplication>[];
    final result = <PdfUsageApplication>[];
    for (var i = 0; i < array.size(); i++) {
      final dict = await array.dictionaryEntry(i);
      if (dict != null) result.add(PdfUsageApplication.fromDictionary(dict));
    }
    return result;
  }

  void setUsageApplications(List<PdfUsageApplication> applications) {
    pdfRepresentation().put(
        PdfOcName.autoStates,
        PdfArray.fromList(applications
            .map<PdfObject>((app) => app.pdfRepresentation())
            .toList(growable: false)));
  }

  /// The `/Order` entry, as a tree of [PdfOptionalContentOrder] entries.
  Future<List<PdfOptionalContentOrder>> getOrder() async {
    final array = await pdfRepresentation().arrayEntry(PdfOcName.order);
    if (array == null) return const <PdfOptionalContentOrder>[];
    return _readOrder(array, 0);
  }

  /// Writes a flat `/Order` array listing [groups] in the given sequence.
  void setOrder(List<PdfOptionalContentGroup> groups) {
    pdfRepresentation().put(PdfOcName.order, _groupArray(groups));
  }

  /// Writes `/Order` from a tree of entries.
  void setOrderTree(List<PdfOptionalContentOrder> order) {
    pdfRepresentation().put(PdfOcName.order, _writeOrder(order));
  }

  static PdfArray _writeOrder(List<PdfOptionalContentOrder> order) {
    final array = PdfArray();
    for (final entry in order) {
      final group = entry.group;
      if (group != null) {
        array.add(group);
        continue;
      }
      final nested = _writeOrder(entry.children);
      final label = entry.label;
      if (label != null) nested.insert(0, makeOcTextString(label));
      array.add(nested);
    }
    return array;
  }

  /// Reads an `/Order` array. [depth] guards against a self-referencing array.
  static Future<List<PdfOptionalContentOrder>> _readOrder(
      PdfArray array, int depth) async {
    if (depth > 32) return const <PdfOptionalContentOrder>[];
    final entries = <PdfOptionalContentOrder>[];
    for (var i = 0; i < array.size(); i++) {
      final element = await array.get(i);
      if (element is PdfArray) {
        String? label;
        var start = 0;
        final first = element.size() > 0 ? await element.get(0) : null;
        if (first is PdfString) {
          label = readOcTextString(first);
          start = 1;
        }
        final tail = PdfArray.fromList(element.toListCopy().sublist(start));
        entries.add(PdfOptionalContentOrder.nested(
            await _readOrder(tail, depth + 1),
            label: label));
        continue;
      }
      final group = await PdfOptionalContentGroup.parse(element);
      if (group != null) {
        entries.add(PdfOptionalContentOrder.group(group.pdfRepresentation()));
      }
    }
    return entries;
  }

  static PdfArray _groupArray(List<PdfOptionalContentGroup> groups) {
    return PdfArray.fromList(groups
        .map<PdfObject>((group) => group.pdfRepresentation())
        .toList(growable: false));
  }
}
