import 'dart:typed_data';

import '../kernel/pdf/pdf_array.dart';
import '../kernel/pdf/pdf_boolean.dart';
import '../kernel/pdf/pdf_dictionary.dart';
import '../kernel/pdf/pdf_document.dart';
import '../kernel/pdf/pdf_name.dart';
import '../kernel/pdf/pdf_number.dart';
import '../kernel/pdf/pdf_object.dart';
import '../kernel/pdf/pdf_reader.dart';
import '../kernel/pdf/pdf_stream.dart';
import '../kernel/pdf/pdf_string.dart';
import 'access_permissions.dart';

/// Whether an indirect object appeared, changed or disappeared between two
/// revisions of the same document.
enum PdfChangeKind {
  /// The object number is only reachable in the newer revision.
  added,

  /// The object exists in both revisions with a different value.
  modified,

  /// The object number is only reachable in the signed revision.
  removed,
}

/// The role an indirect object plays, which decides whether a DocMDP
/// transform method permits the change, ISO 32000-1 12.8.2.2.
enum PdfChangeCategory {
  /// A signature field, a signature value dictionary or the entries a new
  /// signature has to add. Signing is permitted at every DocMDP level.
  signature,

  /// Cross reference streams, object streams and other file structure that a
  /// conforming writer rewrites on every incremental update.
  fileStructure,

  /// The value or appearance of a form field that is not a signature.
  formField,

  /// An annotation that is not a form field widget.
  annotation,

  /// The interactive form dictionary itself.
  acroForm,

  /// The document catalog.
  catalog,

  /// A page object or a page content stream.
  page,

  /// The document security store and the objects it references.
  documentSecurityStore,

  /// Anything the analyzer could not attribute to one of the roles above.
  other,
}

/// One difference between the signed revision and the current document.
class PdfObjectChange {
  /// Object number the change was observed on.
  final int objectNumber;

  /// Whether the object was added, modified or removed.
  final PdfChangeKind kind;

  /// The role the object plays in the document.
  final PdfChangeCategory category;

  /// Fully qualified name of the form field the object belongs to, when any.
  final String? fieldName;

  const PdfObjectChange(
      this.objectNumber, this.kind, this.category, this.fieldName);

  @override
  String toString() => 'object $objectNumber ${kind.name} ${category.name}'
      '${fieldName == null ? '' : ' ($fieldName)'}';
}

/// The differences between a signed revision and a later state of the same
/// document, together with the DocMDP verdict for those differences.
class DocumentModificationReport {
  /// Every observed difference.
  final List<PdfObjectChange> changes;

  /// Fully qualified names of the form fields whose value changed.
  final Set<String> changedFieldValues;

  /// Fully qualified names of the form fields that gained a value.
  final Set<String> filledFieldValues;

  /// Number of page objects that were added, modified or removed.
  final int alteredPages;

  const DocumentModificationReport(this.changes, this.changedFieldValues,
      this.filledFieldValues, this.alteredPages);

  /// True when nothing changed at all.
  bool get isEmpty => changes.isEmpty;

  /// The `/Changes` array of ISO 32000-1 table 252: the number of pages
  /// altered, of fields altered and of fields filled in, in that order.
  List<int> toChangesArray() => [
        alteredPages,
        changedFieldValues.length,
        filledFieldValues.length,
      ];

  /// The changes that [permissions] does not allow, ISO 32000-1 table 254.
  ///
  /// Level 1 permits nothing beyond the document security store and the file
  /// structure a conforming writer has to rewrite. Level 2 adds form filling
  /// and signing. Level 3 adds annotation creation, deletion and modification.
  List<PdfObjectChange> violationsFor(AccessPermissions permissions) {
    if (permissions == AccessPermissions.unspecified) {
      return const [];
    }
    return changes
        .where((change) => !_isPermitted(change, permissions))
        .toList(growable: false);
  }

  static bool _isPermitted(
      PdfObjectChange change, AccessPermissions permissions) {
    switch (change.category) {
      case PdfChangeCategory.fileStructure:
      case PdfChangeCategory.documentSecurityStore:
        // A document security store and a document time stamp may always be
        // added; the file structure is rewritten by every incremental update.
        return change.kind != PdfChangeKind.removed;
      case PdfChangeCategory.signature:
      case PdfChangeCategory.acroForm:
        // Signing is a permitted change at levels 2 and 3 and requires the
        // interactive form dictionary to grow.
        return permissions != AccessPermissions.noChangesPermitted &&
            change.kind != PdfChangeKind.removed;
      case PdfChangeCategory.formField:
        return permissions != AccessPermissions.noChangesPermitted &&
            change.kind != PdfChangeKind.removed;
      case PdfChangeCategory.annotation:
        return permissions == AccessPermissions.annotationModification;
      case PdfChangeCategory.catalog:
        // The catalog is touched when the interactive form or the permissions
        // dictionary grows, which accompanies a permitted signature.
        return permissions != AccessPermissions.noChangesPermitted &&
            change.kind == PdfChangeKind.modified;
      case PdfChangeCategory.page:
      case PdfChangeCategory.other:
        return false;
    }
  }
}

/// Compares a signed revision with a later state of the same document.
///
/// ISO 32000-1 12.8.2.2.2 requires a conforming reader to verify the byte
/// range digest first and then to check that every modification is permitted
/// by the transform parameters. This class performs the second half: it walks
/// the indirect objects reachable from both revisions and reports what
/// changed, attributing each difference to the role the object plays.
class SignatureModificationAnalyzer {
  SignatureModificationAnalyzer._();

  /// Compares [signedRevision] with [current].
  ///
  /// [signedRevision] shall be the prefix of [current] that the `/ByteRange`
  /// of the signature covers, which is a self contained PDF because every
  /// later change is an incremental update (7.5.6).
  static Future<DocumentModificationReport> compare(
      Uint8List signedRevision, Uint8List current) async {
    final signedDocument =
        await PdfDocument.open(PdfReader.fromBytes(signedRevision));
    try {
      final currentDocument =
          await PdfDocument.open(PdfReader.fromBytes(current));
      try {
        return await _compareDocuments(signedDocument, currentDocument);
      } finally {
        await currentDocument.close();
      }
    } finally {
      await signedDocument.close();
    }
  }

  static Future<DocumentModificationReport> _compareDocuments(
      PdfDocument signed, PdfDocument current) async {
    final signedRoles = await _DocumentRoles.build(signed);
    final currentRoles = await _DocumentRoles.build(current);

    final objectNumbers = <int>{
      ...signedRoles.objects.keys,
      ...currentRoles.objects.keys,
    };

    final changes = <PdfObjectChange>[];
    var alteredPages = 0;
    for (final number in objectNumbers.toList()..sort()) {
      final before = signedRoles.objects[number];
      final after = currentRoles.objects[number];
      if (before == after) continue;
      final PdfChangeKind kind;
      if (before == null) {
        kind = PdfChangeKind.added;
      } else if (after == null) {
        kind = PdfChangeKind.removed;
      } else {
        kind = PdfChangeKind.modified;
      }
      final roles = after == null ? signedRoles : currentRoles;
      var category = roles.categories[number] ?? PdfChangeCategory.other;
      if (kind == PdfChangeKind.modified) {
        category = _refine(category, number, signedRoles, currentRoles);
      }
      if (category == PdfChangeCategory.page) alteredPages++;
      changes.add(
          PdfObjectChange(number, kind, category, roles.fieldNames[number]));
    }

    final changed = <String>{};
    final filled = <String>{};
    for (final entry in currentRoles.fieldValues.entries) {
      if (!signedRoles.fieldValues.containsKey(entry.key)) continue;
      final before = signedRoles.fieldValues[entry.key];
      if (before == entry.value) continue;
      changed.add(entry.key);
      if (before == null) filled.add(entry.key);
    }
    for (final name in currentRoles.fieldValues.keys) {
      if (!signedRoles.fieldValues.containsKey(name)) {
        changed.add(name);
        if (currentRoles.fieldValues[name] != null) filled.add(name);
      }
    }

    return DocumentModificationReport(
        List.unmodifiable(changes), changed, filled, alteredPages);
  }

  /// Entries a conforming writer touches on the document catalog while signing
  /// or while adding a document security store.
  static const Set<String> _catalogSigningKeys = {
    'AcroForm',
    'Perms',
    'DSS',
    'Extensions',
    'Lang',
    'MarkInfo',
    'Metadata',
    'StructTreeRoot',
    'Version',
  };

  /// Entries a conforming writer touches on the interactive form dictionary
  /// while adding a signature field.
  static const Set<String> _acroFormSigningKeys = {
    'CO',
    'DA',
    'DR',
    'Fields',
    'NeedAppearances',
    'SigFlags',
  };

  /// Entries a conforming writer touches on a page while attaching a widget.
  static const Set<String> _pageAnnotationKeys = {'Annots', 'Tabs'};

  /// Narrows the category of a modified object by looking at which dictionary
  /// entries actually changed.
  ///
  /// Attaching a signature widget necessarily rewrites the `/Annots` array of
  /// its page, the interactive form dictionary and, when the form is new, the
  /// catalog. Those rewrites are part of signing, which table 254 permits at
  /// levels 2 and 3, so they must not be reported as arbitrary page edits.
  static PdfChangeCategory _refine(PdfChangeCategory category, int number,
      _DocumentRoles signed, _DocumentRoles current) {
    final changedKeys =
        _changedKeys(signed.entries[number], current.entries[number]);
    if (changedKeys == null) return category;
    switch (category) {
      case PdfChangeCategory.page:
        if (!changedKeys.every(_pageAnnotationKeys.contains)) {
          return PdfChangeCategory.page;
        }
        final before = signed.annotations[number] ?? const <int>[];
        final after = current.annotations[number] ?? const <int>[];
        if (before.any((annotation) => !after.contains(annotation))) {
          return PdfChangeCategory.annotation;
        }
        final added = after.where((annotation) => !before.contains(annotation));
        return added.every((annotation) =>
                current.categories[annotation] == PdfChangeCategory.signature)
            ? PdfChangeCategory.signature
            : PdfChangeCategory.annotation;
      case PdfChangeCategory.acroForm:
        return changedKeys.every(_acroFormSigningKeys.contains)
            ? PdfChangeCategory.acroForm
            : PdfChangeCategory.other;
      case PdfChangeCategory.catalog:
        return changedKeys.every(_catalogSigningKeys.contains)
            ? PdfChangeCategory.catalog
            : PdfChangeCategory.other;
      default:
        return category;
    }
  }

  /// The dictionary keys whose value differs, or null when either revision
  /// did not expose the object as a dictionary.
  static Set<String>? _changedKeys(
      Map<String, String>? before, Map<String, String>? after) {
    if (before == null || after == null) return null;
    final keys = <String>{...before.keys, ...after.keys};
    return keys.where((key) => before[key] != after[key]).toSet();
  }
}

/// Canonical values and roles of every indirect object of one revision.
class _DocumentRoles {
  final Map<int, String> objects = {};
  final Map<int, PdfChangeCategory> categories = {};
  final Map<int, String> fieldNames = {};

  /// Canonical value of every entry of every dictionary object.
  final Map<int, Map<String, String>> entries = {};

  /// Object numbers listed in the `/Annots` array of every page object.
  final Map<int, List<int>> annotations = {};

  /// Canonical `/V` of every terminal form field, null when it has no value.
  final Map<String, String?> fieldValues = {};

  static Future<_DocumentRoles> build(PdfDocument document) async {
    final roles = _DocumentRoles();
    final table = document.crossReferenceTable();
    for (var number = 1; number < table.size(); number++) {
      final reference = table.get(number);
      if (reference == null || reference.isFree()) continue;
      PdfObject? object;
      try {
        object = await reference.targetObject(true);
      } catch (_) {
        object = null;
      }
      if (object == null) continue;
      Uint8List? raw;
      if (object is PdfStream) {
        try {
          raw = await object.getRawBytes();
        } catch (_) {
          raw = null;
        }
      }
      roles.objects[number] = _canonical(object, 0, raw);
      roles.categories[number] = _structuralCategory(object);
      if (object is PdfDictionary) {
        final map = object.getMap();
        if (map != null) {
          roles.entries[number] = {
            for (final entry in map.entries)
              entry.key.getValue(): _canonical(entry.value, 1)
          };
        }
      }
    }
    await roles._markCatalog(document);
    return roles;
  }

  static PdfChangeCategory _structuralCategory(PdfObject object) {
    if (object is PdfStream) {
      final type = object.getMap()?[PdfName.type];
      if (type is PdfName &&
          (type.getValue() == 'XRef' || type.getValue() == 'ObjStm')) {
        return PdfChangeCategory.fileStructure;
      }
    }
    if (object is PdfDictionary) {
      final type = object.getMap()?[PdfName.type];
      if (type is PdfName) {
        switch (type.getValue()) {
          case 'Sig':
          case 'DocTimeStamp':
            return PdfChangeCategory.signature;
          case 'Page':
            return PdfChangeCategory.page;
          case 'Annot':
            return PdfChangeCategory.annotation;
        }
      }
    }
    return PdfChangeCategory.other;
  }

  void _tag(PdfObject? object, PdfChangeCategory category, {String? field}) {
    final number = object?.indirectHandle()?.objectNumber();
    if (number == null) return;
    categories[number] = category;
    if (field != null) fieldNames[number] = field;
  }

  Future<void> _markCatalog(PdfDocument document) async {
    final catalog = document.rootCatalog().pdfRepresentation();
    _tag(catalog, PdfChangeCategory.catalog);

    final dss = await catalog.dictionaryEntry(PdfName.intern('DSS'));
    if (dss != null) {
      await _tagSubtree(dss, PdfChangeCategory.documentSecurityStore, 0);
    }

    final acroForm = await catalog.dictionaryEntry(PdfName.acroForm);
    if (acroForm != null) {
      _tag(acroForm, PdfChangeCategory.acroForm);
      final fields = await acroForm.arrayEntry(PdfName.fields);
      await _walkFields(fields, null, <PdfDictionary>{});
    }

    await _markPages(document);
  }

  Future<void> _markPages(PdfDocument document) async {
    final pageCount = document.pageTotal();
    for (var index = 1; index <= pageCount; index++) {
      PdfDictionary? page;
      try {
        page = (await document.pageAt(index))?.pdfRepresentation();
      } catch (_) {
        page = null;
      }
      if (page == null) continue;
      _tag(page, PdfChangeCategory.page);
      final contents = page.getMap()?[PdfName.contents];
      if (contents is PdfStream) {
        _tag(contents, PdfChangeCategory.page);
      } else if (contents != null) {
        final resolved = await page.get(PdfName.contents, true);
        if (resolved is PdfStream) {
          _tag(resolved, PdfChangeCategory.page);
        } else if (resolved is PdfArray) {
          for (var i = 0; i < resolved.size(); i++) {
            _tag(await resolved.get(i), PdfChangeCategory.page);
          }
        }
      }
      final pageNumber = page.indirectHandle()?.objectNumber();
      final annotationArray = await page.arrayEntry(PdfName.annots);
      if (annotationArray == null) continue;
      final referenced = <int>[];
      for (var i = 0; i < annotationArray.size(); i++) {
        final annotation = await annotationArray.get(i);
        if (annotation is! PdfDictionary) continue;
        final number = annotation.indirectHandle()?.objectNumber();
        if (number == null) continue;
        referenced.add(number);
        if (categories[number] == PdfChangeCategory.other) {
          categories[number] = PdfChangeCategory.annotation;
        }
      }
      if (pageNumber != null) annotations[pageNumber] = referenced;
    }
  }

  Future<void> _tagSubtree(
      PdfObject object, PdfChangeCategory category, int depth) async {
    if (depth > 8) return;
    _tag(object, category);
    if (object is PdfDictionary) {
      for (final key in object.keySet()) {
        final value = await object.get(key, true);
        if (value != null) await _tagSubtree(value, category, depth + 1);
      }
    } else if (object is PdfArray) {
      for (var index = 0; index < object.size(); index++) {
        final value = await object.get(index);
        if (value != null) await _tagSubtree(value, category, depth + 1);
      }
    }
  }

  Future<void> _walkFields(
      PdfArray? fields, String? parentName, Set<PdfDictionary> visited) async {
    if (fields == null) return;
    for (var index = 0; index < fields.size(); index++) {
      final field = await fields.get(index);
      if (field is! PdfDictionary || !visited.add(field)) continue;
      final partial = (await field.stringEntry(PdfName.t))?.decodeMappingText();
      final name = partial == null
          ? parentName
          : (parentName == null ? partial : '$parentName.$partial');
      final kids = await field.arrayEntry(PdfName.kids);
      final type = await field.nameEntry(PdfName.ft);
      final isSignature = type == PdfName.sig;
      _tag(
          field,
          isSignature
              ? PdfChangeCategory.signature
              : PdfChangeCategory.formField,
          field: name);
      final value = await field.get(PdfName.v, true);
      if (isSignature) {
        if (value != null) {
          await _tagSubtree(value, PdfChangeCategory.signature, 0);
        }
      } else if (kids == null || kids.size() == 0) {
        if (name != null) {
          fieldValues[name] = value == null ? null : _canonical(value);
        }
      }
      final appearance = await field.get(PdfName.ap, true);
      if (appearance != null) {
        await _tagSubtree(
            appearance,
            isSignature
                ? PdfChangeCategory.signature
                : PdfChangeCategory.formField,
            0);
      }
      if (kids != null && kids.size() > 0) {
        final firstKid = await kids.get(0);
        final kidIsWidget = firstKid is PdfDictionary &&
            (await firstKid.stringEntry(PdfName.t)) == null;
        if (kidIsWidget) {
          for (var kid = 0; kid < kids.size(); kid++) {
            final widget = await kids.get(kid);
            if (widget is! PdfDictionary) continue;
            _tag(
                widget,
                isSignature
                    ? PdfChangeCategory.signature
                    : PdfChangeCategory.formField,
                field: name);
            final widgetAppearance = await widget.get(PdfName.ap, true);
            if (widgetAppearance != null) {
              await _tagSubtree(
                  widgetAppearance,
                  isSignature
                      ? PdfChangeCategory.signature
                      : PdfChangeCategory.formField,
                  0);
            }
          }
          if (!isSignature && name != null) {
            fieldValues[name] = value == null ? null : _canonical(value);
          }
        } else {
          await _walkFields(kids, name, visited);
        }
      }
    }
  }
}

/// Serializes an object without following indirect references.
///
/// Two objects are considered equal when their canonical forms match, so the
/// serialization has to be stable: dictionary keys are sorted and streams are
/// reduced to their raw bytes.
String _canonical(PdfObject? object, [int depth = 0, Uint8List? streamBytes]) {
  if (object == null || depth > 32) return 'null';
  if (object is PdfIndirectReference) {
    return 'R(${object.objectNumber()} ${object.generationNumber()})';
  }
  if (object is PdfBoolean) return object.getValue() ? 'true' : 'false';
  if (object is PdfNumber) {
    final value = object.getValue();
    return value == value.roundToDouble() && value.abs() < 1e15
        ? value.toInt().toString()
        : value.toString();
  }
  if (object is PdfName) return '/${object.getValue()}';
  if (object is PdfString) {
    final buffer = StringBuffer('(');
    for (final unit in object.getValue().codeUnits) {
      buffer.write(unit.toRadixString(16).padLeft(4, '0'));
    }
    return (buffer..write(')')).toString();
  }
  if (object is PdfStream) {
    final dictionary = _canonicalMap(object.getMap(), depth);
    return 'stream$dictionary#${_streamFingerprint(streamBytes)}';
  }
  if (object is PdfDictionary) return _canonicalMap(object.getMap(), depth);
  if (object is PdfArray) {
    final items =
        object.toListCopy().map((item) => _canonical(item, depth + 1));
    return '[${items.join(' ')}]';
  }
  if (object.objectKind() == PdfObjectType.nullType) return 'null';
  return object.toString();
}

String _canonicalMap(Map<PdfName, PdfObject>? map, int depth) {
  if (map == null) return '<<>>';
  final keys = map.keys.toList()
    ..sort((a, b) => a.getValue().compareTo(b.getValue()));
  final buffer = StringBuffer('<<');
  for (final key in keys) {
    buffer.write('/${key.getValue()} ${_canonical(map[key], depth + 1)} ');
  }
  return (buffer..write('>>')).toString();
}

/// A 64 bit FNV-1a fingerprint of the raw stream bytes.
///
/// The bytes are read without applying filters so that a re-compression with
/// identical content is still reported as a change, which is what a
/// modification detection transform has to do.
String _streamFingerprint(Uint8List? bytes) {
  if (bytes == null) return 'unread';
  var hash = BigInt.parse('14695981039346656037');
  final prime = BigInt.parse('1099511628211');
  final mask = (BigInt.one << 64) - BigInt.one;
  for (final byte in bytes) {
    hash = ((hash ^ BigInt.from(byte)) * prime) & mask;
  }
  return '${bytes.length}:${hash.toRadixString(16)}';
}
