import '../pdf_array.dart';
import '../pdf_dictionary.dart';
import '../pdf_document.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';
import '../pdf_object.dart';
import '../pdf_object_copier.dart';
import '../pdf_page.dart';
import '../pdf_string.dart';
import 'pdf_struct_elem.dart';
import 'pdf_struct_tree_root.dart';
import 'tagging_names.dart';

/// What [StructureTreeCopier.copyStructure] actually transferred.
class StructureCopyReport {
  /// The top-level structure elements added to the destination tree.
  final List<PdfStructElem> roots;

  /// Structure elements copied, including the roots.
  final int copiedElements;

  /// Marked-content references re-registered in the destination parent tree.
  final int copiedMarkedContentReferences;

  /// Object references (/OBJR) re-registered in the destination.
  final int copiedObjectReferences;

  /// Content items that were dropped because the object they point at was
  /// not part of the copy.
  final int droppedContentItems;

  const StructureCopyReport({
    required this.roots,
    required this.copiedElements,
    required this.copiedMarkedContentReferences,
    required this.copiedObjectReferences,
    required this.droppedContentItems,
  });
}

/// Moves a logical structure tree from one document into another
/// (ISO 32000-1:2008, 14.7.2 and 14.7.4).
///
/// Copying a page verbatim keeps its marked-content identifiers, but the
/// structure that gives them meaning lives outside the page: in the structure
/// elements, in the /ParentTree that maps a content item back to its element,
/// and in the /RoleMap, /ClassMap and /Namespaces of the structure tree root.
/// This copier walks the source tree, keeps only the elements that still have
/// content on a copied page, rebuilds their /K and /P links in the
/// destination, and re-registers every content item under freshly allocated
/// destination parent-tree keys.
class StructureTreeCopier {
  StructureTreeCopier._();

  /// Copies the structure belonging to the pages of [pageMapping] from
  /// [source] into [destination].
  ///
  /// [pageMapping] maps each source page to the page that already holds its
  /// copied content in [destination]. [objectMapping] does the same for whole
  /// objects that are content items in their own right — annotations, form and
  /// image XObjects — so that /OBJR and /Stm references survive the copy;
  /// content items whose object has no mapping are dropped rather than left
  /// dangling.
  static Future<StructureCopyReport> copyStructure(
    PdfDocument source,
    PdfDocument destination,
    Map<PdfPage, PdfPage> pageMapping, {
    Map<PdfObject, PdfObject> objectMapping = const {},
  }) async {
    if (identical(source, destination)) {
      throw ArgumentError('The structure tree copier needs two documents.');
    }
    final sourceRoot = await source.loadStructureRoot();
    if (sourceRoot == null) {
      return const StructureCopyReport(
        roots: [],
        copiedElements: 0,
        copiedMarkedContentReferences: 0,
        copiedObjectReferences: 0,
        droppedContentItems: 0,
      );
    }
    destination.enableTagging();
    final destinationRoot = destination.structureRoot();
    destinationRoot.setDocument(destination);

    final worker = _CopyWorker(
      source: source,
      destination: destination,
      sourceRoot: sourceRoot,
      destinationRoot: destinationRoot,
      pageMapping: pageMapping,
      objectMapping: objectMapping,
    );
    return await worker.run();
  }

  /// Copies the pages numbered [pageNumbers] (1-based) from [source] into
  /// [destination] and then the structure that belongs to them.
  ///
  /// The pages are copied verbatim, which preserves their marked-content
  /// identifiers, and their annotations are mapped so that /OBJR content items
  /// keep pointing at the right object. Structure that lives on pages outside
  /// [pageNumbers] stays behind.
  static Future<StructureCopyResult> copyPagesWithStructure(
    PdfDocument source,
    PdfDocument destination,
    List<int> pageNumbers, {
    int? insertBefore,
  }) async {
    if (identical(source, destination)) {
      throw ArgumentError('Copying pages with their structure needs two '
          'documents.');
    }
    if (pageNumbers.toSet().length != pageNumbers.length) {
      throw ArgumentError('A page may only be copied once per batch.');
    }
    var insertIndex = insertBefore ?? (destination.pageTotal() + 1);
    if (insertIndex < 1 || insertIndex > destination.pageTotal() + 1) {
      throw RangeError.range(
          insertIndex, 1, destination.pageTotal() + 1, 'insertBefore');
    }

    final sourcePages = <PdfPage>[];
    for (final number in pageNumbers) {
      if (number < 1 || number > source.pageTotal()) {
        throw RangeError.range(number, 1, source.pageTotal(), 'page');
      }
      sourcePages.add((await source.pageAt(number))!);
    }

    final copier = PdfObjectCopier(destination,
        forbiddenUnmappedTypes: {'Page', 'Pages', 'Catalog'},
        deferIndirectRegistration: true);
    final targets = <PdfDictionary>[];
    for (final page in sourcePages) {
      final target = PdfDictionary();
      copier.register(page.pdfRepresentation(), target);
      targets.add(target);
    }
    for (var i = 0; i < sourcePages.length; i++) {
      final from = sourcePages[i].pdfRepresentation();
      final target = targets[i];
      await copier.copyDictionaryEntries(from, target, excludedKeys: {
        PdfName.parent,
        // The destination allocates its own parent tree keys.
        PdfName.structParents,
      });
      for (final name in ['Resources', 'MediaBox', 'CropBox', 'Rotate']) {
        final key = PdfName(name);
        if (target.containsKey(key)) continue;
        PdfDictionary? ancestor = from;
        final visited = <PdfDictionary>{};
        while (ancestor != null) {
          if (!visited.add(ancestor)) {
            throw FormatException('Cyclic page tree.');
          }
          final value = await ancestor.get(key);
          if (value != null) {
            target.put(key, await copier.copy(value));
            break;
          }
          ancestor = await ancestor.dictionaryEntry(PdfName.parent);
        }
      }
    }
    copier.commit();

    final pageMapping = <PdfPage, PdfPage>{};
    final copiedPages = <PdfPage>[];
    for (var i = 0; i < targets.length; i++) {
      final page = PdfPage(targets[i]);
      await destination.insertPageObject(insertIndex++, page);
      copiedPages.add(page);
      pageMapping[sourcePages[i]] = page;
    }

    final objectMapping = <PdfObject, PdfObject>{};
    for (var i = 0; i < sourcePages.length; i++) {
      final from =
          await sourcePages[i].pdfRepresentation().arrayEntry(PdfName.annots);
      final to = await targets[i].arrayEntry(PdfName.annots);
      if (from == null || to == null) continue;
      for (var j = 0; j < from.size() && j < to.size(); j++) {
        final sourceAnnotation = await from.get(j, true);
        final targetAnnotation = await to.get(j, true);
        if (sourceAnnotation is PdfDictionary &&
            targetAnnotation is PdfDictionary) {
          objectMapping[sourceAnnotation] = targetAnnotation;
        }
      }
    }

    final report = await copyStructure(source, destination, pageMapping,
        objectMapping: objectMapping);
    return StructureCopyResult(copiedPages, report);
  }
}

/// The pages copied by [StructureTreeCopier.copyPagesWithStructure] and what
/// happened to their structure.
class StructureCopyResult {
  final List<PdfPage> pages;
  final StructureCopyReport structure;

  const StructureCopyResult(this.pages, this.structure);
}

class _CopyWorker {
  final PdfDocument source;
  final PdfDocument destination;
  final PdfStructTreeRoot sourceRoot;
  final PdfStructTreeRoot destinationRoot;
  final Map<PdfPage, PdfPage> pageMapping;
  final Map<PdfObject, PdfObject> objectMapping;

  late final PdfObjectCopier copier;
  final Map<PdfDictionary, PdfDictionary> _pages = {};
  final Map<PdfObject, PdfObject> _objects = {};
  final Map<PdfDictionary, bool> _retained = {};
  final List<_PendingMcid> _pendingMcids = [];
  final List<_PendingObjRef> _pendingObjRefs = [];

  int _copiedElements = 0;
  int _dropped = 0;

  _CopyWorker({
    required this.source,
    required this.destination,
    required this.sourceRoot,
    required this.destinationRoot,
    required this.pageMapping,
    required this.objectMapping,
  });

  Future<StructureCopyReport> run() async {
    copier = PdfObjectCopier(destination);
    for (final entry in pageMapping.entries) {
      final from = entry.key.pdfRepresentation();
      final to = entry.value.pdfRepresentation();
      to.attachToDocument(destination);
      _pages[from] = to;
      copier.register(from, to);
    }
    for (final entry in objectMapping.entries) {
      _objects[entry.key] = entry.value;
      copier.register(entry.key, entry.value);
    }

    await _resetCopiedStructParents();

    final roots = <PdfStructElem>[];
    for (final kid in await sourceRoot.getKids()) {
      if (kid is! PdfDictionary) continue;
      if (!await PdfStructElem.isStructElem(kid)) continue;
      if (!await _retains(kid, null)) continue;
      final copied = await _copyElement(kid, null);
      if (copied == null) continue;
      final element = PdfStructElem(copied);
      await destinationRoot.addKid(element);
      roots.add(element);
    }

    await _copyRoleMap();
    await _copyClassMap();
    await _copyNamespaces();
    await _registerContentItems();

    return StructureCopyReport(
      roots: roots,
      copiedElements: _copiedElements,
      copiedMarkedContentReferences: _pendingMcids.length,
      copiedObjectReferences: _pendingObjRefs.length,
      droppedContentItems: _dropped,
    );
  }

  /// A page copied verbatim brings the source document's /StructParents key
  /// with it. That key means nothing in the destination parent tree, so it is
  /// dropped unless the destination already registered content under it.
  Future<void> _resetCopiedStructParents() async {
    for (final page in _pages.values) {
      final key = (await page.numberEntry(PdfName.structParents))?.intValue();
      if (key == null) continue;
      if (await destinationRoot.getParentTreeEntry(key) != null) continue;
      page.remove(PdfName.structParents);
      page.markChanged();
    }
  }

  /// True when [element] still has content on a copied page, directly or
  /// through a descendant.
  Future<bool> _retains(PdfDictionary element, PdfDictionary? inherited) async {
    final cached = _retained[element];
    if (cached != null) return cached;
    _retained[element] = false;
    final page = await element.dictionaryEntry(TaggingNames.pg) ?? inherited;
    var retained = false;
    for (final item in await _kidsOf(element)) {
      if (item is PdfNumber) {
        if (page != null && _pages.containsKey(page)) retained = true;
        continue;
      }
      if (item is! PdfDictionary) continue;
      if (await PdfStructElem.isStructElem(item)) {
        if (await _retains(item, page)) retained = true;
        continue;
      }
      final type = await item.nameEntry(PdfName.type);
      if (TaggingNames.objr == type) {
        final referenced = await item.get(TaggingNames.obj, true);
        if (referenced != null && _objects.containsKey(referenced)) {
          retained = true;
        }
        continue;
      }
      final itemPage = await item.dictionaryEntry(TaggingNames.pg) ?? page;
      if (itemPage != null && _pages.containsKey(itemPage)) retained = true;
    }
    _retained[element] = retained;
    return retained;
  }

  Future<List<PdfObject>> _kidsOf(PdfDictionary element) async {
    final k = await element.get(PdfName.k, true);
    if (k == null) return const [];
    if (k is! PdfArray) return [k];
    final items = <PdfObject>[];
    for (var i = 0; i < k.size(); i++) {
      final item = await k.get(i, true);
      if (item != null) items.add(item);
    }
    return items;
  }

  /// Keys this copier rebuilds itself instead of copying verbatim.
  static final Set<PdfName> _handledKeys = {
    PdfName.k,
    PdfName.p,
    TaggingNames.pg,
    PdfName.id,
  };

  Future<PdfDictionary?> _copyElement(
      PdfDictionary element, PdfDictionary? inherited) async {
    final sourcePage =
        await element.dictionaryEntry(TaggingNames.pg) ?? inherited;
    final destinationPage = sourcePage == null ? null : _pages[sourcePage];

    final copy = PdfDictionary();
    copy.attachToDocument(destination);
    await copier.copyDictionaryEntries(element, copy,
        excludedKeys: _handledKeys);
    copy.put(PdfName.type, PdfName.structElem);
    if (destinationPage != null) {
      copy.put(
          TaggingNames.pg, destinationPage.indirectHandle() ?? destinationPage);
    }
    await _copyElementId(element, copy);
    _copiedElements++;

    final kids = <PdfObject>[];
    for (final item in await _kidsOf(element)) {
      if (item is PdfNumber) {
        if (destinationPage == null) {
          _dropped++;
          continue;
        }
        kids.add(PdfNumber.fromInt(item.intValue()));
        _pendingMcids.add(_PendingMcid(destinationPage, item.intValue(), copy));
        continue;
      }
      if (item is! PdfDictionary) {
        _dropped++;
        continue;
      }
      if (await PdfStructElem.isStructElem(item)) {
        if (!await _retains(item, sourcePage)) continue;
        final child = await _copyElement(item, sourcePage);
        if (child == null) continue;
        child.put(PdfName.p, copy.indirectHandle() ?? copy);
        child.markChanged();
        kids.add(child.indirectHandle() ?? child);
        continue;
      }
      final type = await item.nameEntry(PdfName.type);
      if (TaggingNames.objr == type) {
        final copied = await _copyObjectReference(item, destinationPage, copy);
        if (copied == null) {
          _dropped++;
          continue;
        }
        kids.add(copied);
        continue;
      }
      final copied = await _copyMarkedContentReference(item, sourcePage, copy);
      if (copied == null) {
        _dropped++;
        continue;
      }
      kids.add(copied);
    }

    if (kids.isEmpty) {
      return null;
    }
    copy.put(
        PdfName.k, kids.length == 1 ? kids.first : PdfArray.fromList(kids));
    copy.markChanged();
    return copy;
  }

  Future<void> _copyElementId(PdfDictionary element, PdfDictionary copy) async {
    final id = await element.stringEntry(PdfName.id);
    if (id == null) return;
    final existing = await destinationRoot.getElementById(id);
    if (existing != null) return;
    copy.put(PdfName.id, PdfString(id.getValue()));
    await destinationRoot.registerElementId(id, PdfStructElem(copy));
  }

  Future<PdfObject?> _copyMarkedContentReference(PdfDictionary reference,
      PdfDictionary? inheritedPage, PdfDictionary owner) async {
    final mcid = (await reference.numberEntry(TaggingNames.mcid))?.intValue();
    if (mcid == null) return null;
    final sourcePage =
        await reference.dictionaryEntry(TaggingNames.pg) ?? inheritedPage;
    if (sourcePage == null) return null;
    final destinationPage = _pages[sourcePage];
    if (destinationPage == null) return null;

    final sourceStream = await reference.get(TaggingNames.stm, true);
    PdfObject? destinationStream;
    if (sourceStream != null) {
      destinationStream = _objects[sourceStream];
      // A sequence living in a stream that was not copied cannot be
      // reconstructed, so the reference is dropped instead of dangling.
      if (destinationStream == null) return null;
    }

    final copy = PdfDictionary();
    copy.put(PdfName.type, TaggingNames.mcr);
    copy.put(
        TaggingNames.pg, destinationPage.indirectHandle() ?? destinationPage);
    if (destinationStream != null) {
      copy.put(TaggingNames.stm,
          destinationStream.indirectHandle() ?? destinationStream);
      final streamOwner = await reference.get(TaggingNames.stmOwn, true);
      final destinationOwner =
          streamOwner == null ? null : _objects[streamOwner];
      if (destinationOwner != null) {
        copy.put(TaggingNames.stmOwn,
            destinationOwner.indirectHandle() ?? destinationOwner);
      }
    }
    copy.put(TaggingNames.mcid, PdfNumber.fromInt(mcid));
    _pendingMcids.add(_PendingMcid(destinationPage, mcid, owner));
    return copy;
  }

  Future<PdfObject?> _copyObjectReference(PdfDictionary reference,
      PdfDictionary? destinationPage, PdfDictionary owner) async {
    final referenced = await reference.get(TaggingNames.obj, true);
    if (referenced == null) return null;
    final destinationObject = _objects[referenced];
    if (destinationObject is! PdfDictionary) return null;

    final copy = PdfDictionary();
    copy.put(PdfName.type, TaggingNames.objr);
    copy.put(TaggingNames.obj,
        destinationObject.indirectHandle() ?? destinationObject);
    if (destinationPage != null) {
      copy.put(
          TaggingNames.pg, destinationPage.indirectHandle() ?? destinationPage);
    }
    _pendingObjRefs.add(_PendingObjRef(destinationObject, owner));
    return copy;
  }

  Future<void> _registerContentItems() async {
    for (final pending in _pendingMcids) {
      await destinationRoot.registerMarkedContent(
          pending.page, pending.mcid, PdfStructElem(pending.owner));
    }
    final reset = <PdfDictionary>{};
    for (final pending in _pendingObjRefs) {
      // The object arrived with the source document's /StructParent, which
      // means nothing here; the first reference re-keys it.
      if (reset.add(pending.object)) {
        pending.object.remove(PdfName.structParent);
      }
      await destinationRoot.registerObjectReference(
          pending.object, PdfStructElem(pending.owner));
    }
  }

  Future<void> _copyRoleMap() async {
    final sourceMap =
        await sourceRoot.pdfRepresentation().dictionaryEntry(PdfName.roleMap);
    if (sourceMap == null || sourceMap.isEmpty()) return;
    final destinationMap = await destinationRoot.getRoleMap();
    for (final entry in await sourceMap.entrySet()) {
      if (destinationMap.containsKey(entry.key)) continue;
      destinationMap.put(entry.key, await copier.copy(entry.value));
    }
    destinationMap.markChanged();
    destinationRoot.markChanged();
  }

  Future<void> _copyClassMap() async {
    final sourceMap =
        await sourceRoot.pdfRepresentation().dictionaryEntry(PdfName.classMap);
    if (sourceMap == null || sourceMap.isEmpty()) return;
    final destinationMap = await destinationRoot.getClassMap();
    for (final entry in await sourceMap.entrySet()) {
      if (destinationMap.containsKey(entry.key)) continue;
      destinationMap.put(entry.key, await copier.copy(entry.value));
    }
    destinationMap.markChanged();
    destinationRoot.markChanged();
  }

  Future<void> _copyNamespaces() async {
    final namespaces = await sourceRoot.getNamespaces();
    for (final namespace in namespaces) {
      final name = await namespace.getNamespaceName();
      if (name == null) continue;
      if (await destinationRoot.findNamespace(name) != null) continue;
      final copied = await copier.copy(namespace.pdfRepresentation());
      if (copied is! PdfDictionary) continue;
      final array = await destinationRoot.getNamespacesObject();
      array.add(copied.indirectHandle() ?? copied);
      array.markChanged();
      destinationRoot.markChanged();
    }
  }
}

class _PendingMcid {
  final PdfDictionary page;
  final int mcid;
  final PdfDictionary owner;

  _PendingMcid(this.page, this.mcid, this.owner);
}

class _PendingObjRef {
  final PdfDictionary object;
  final PdfDictionary owner;

  _PendingObjRef(this.object, this.owner);
}
