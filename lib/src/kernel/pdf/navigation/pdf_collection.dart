import '../pdf_array.dart';
import '../pdf_boolean.dart';
import '../pdf_date.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';
import '../pdf_object.dart';
import '../pdf_object_wrapper.dart';
import '../pdf_string.dart';

/// Collection field dictionary.
///
/// See ISO 32000-1:2008, 12.3.5 "Collections", Table 157.
class PdfCollectionField extends PdfObjectWrapper<PdfDictionary> {
  /// `/Subtype /S`: a text field stored as a PDF text string.
  static final PdfName text = PdfName.intern('S');

  /// `/Subtype /D`: a date field stored as a PDF date string.
  static final PdfName date = PdfName.intern('D');

  /// `/Subtype /N`: a number field stored as a PDF number.
  static final PdfName number = PdfName.intern('N');

  /// `/Subtype /F`: the file name of the embedded file stream.
  static final PdfName fileName = PdfName.intern('F');

  /// `/Subtype /Desc`: the description of the embedded file stream.
  static final PdfName description = PdfName.intern('Desc');

  /// `/Subtype /ModDate`: the modification date of the embedded file.
  static final PdfName modificationDate = PdfName.intern('ModDate');

  /// `/Subtype /CreationDate`: the creation date of the embedded file.
  static final PdfName creationDate = PdfName.intern('CreationDate');

  /// `/Subtype /Size`: the size of the embedded file.
  static final PdfName size = PdfName.intern('Size');

  static final Set<String> _subtypes = {
    text.getValue(),
    date.getValue(),
    number.getValue(),
    fileName.getValue(),
    description.getValue(),
    modificationDate.getValue(),
    creationDate.getValue(),
    size.getValue(),
  };

  PdfCollectionField(super.pdfObject);

  /// Creates a collection field. Table 157 makes `/Subtype` and `/N`
  /// required.
  PdfCollectionField.create(PdfName subtype, String displayName)
      : super(PdfDictionary()) {
    if (!_subtypes.contains(subtype.getValue())) {
      throw ArgumentError.value(
          subtype, 'subtype', 'Unknown collection field subtype (Table 157)');
    }
    pdfRepresentation().put(PdfName.type, PdfName.intern('CollectionField'));
    pdfRepresentation().put(PdfName.subtype, subtype);
    pdfRepresentation().put(PdfName.n, PdfString(displayName));
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Gets `/Subtype`.
  Future<PdfName?> getSubtype() async =>
      await pdfRepresentation().nameEntry(PdfName.subtype);

  /// Gets `/N`, the textual field name presented to the user.
  Future<String?> getDisplayName() async =>
      (await pdfRepresentation().stringEntry(PdfName.n))?.decodeMappingText();

  /// Sets `/O`, the relative order of the field in the user interface.
  PdfCollectionField setOrder(int order) {
    pdfRepresentation().put(PdfName.o, PdfNumber.fromInt(order));
    return this;
  }

  /// Gets `/O`.
  Future<int?> getOrder() async =>
      await pdfRepresentation().integerEntry(PdfName.o);

  /// Sets `/V`, the initial visibility of the field.
  PdfCollectionField setVisible(bool visible) {
    pdfRepresentation().put(PdfName.v, PdfBoolean(visible));
    return this;
  }

  /// Gets `/V`; the default is true per Table 157.
  Future<bool> isVisible() async =>
      (await pdfRepresentation().booleanEntry(PdfName.v))?.getValue() ?? true;

  /// Sets `/E`, whether the reader should support editing the field value.
  PdfCollectionField setEditable(bool editable) {
    pdfRepresentation().put(PdfName.intern('E'), PdfBoolean(editable));
    return this;
  }

  /// Gets `/E`; the default is false per Table 157.
  Future<bool> isEditable() async =>
      (await pdfRepresentation().booleanEntry(PdfName.intern('E')))
          ?.getValue() ??
      false;
}

/// Collection sort dictionary.
///
/// See ISO 32000-1:2008, 12.3.5, Table 158.
class PdfCollectionSort extends PdfObjectWrapper<PdfDictionary> {
  PdfCollectionSort(super.pdfObject);

  /// Creates a sort dictionary over a single field.
  PdfCollectionSort.byField(String field, {bool? ascending})
      : super(PdfDictionary()) {
    pdfRepresentation().put(PdfName.type, PdfName.intern('CollectionSort'));
    pdfRepresentation().put(PdfName.s, PdfName(field));
    if (ascending != null) {
      pdfRepresentation().put(PdfName.a, PdfBoolean(ascending));
    }
  }

  /// Creates a sort dictionary over several fields, where each extra field
  /// breaks the ties of the previous one.
  PdfCollectionSort.byFields(List<String> fields, {List<bool>? ascending})
      : super(PdfDictionary()) {
    if (fields.isEmpty) {
      throw ArgumentError.value(
          fields, 'fields', 'Collection sort /S requires at least one field');
    }
    pdfRepresentation().put(PdfName.type, PdfName.intern('CollectionSort'));
    pdfRepresentation().put(
        PdfName.s, PdfArray.fromList([for (final f in fields) PdfName(f)]));
    if (ascending != null) {
      pdfRepresentation().put(PdfName.a, PdfArray.fromBooleans(ascending));
    }
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Gets `/S` as a list of field names, flattening the single-name form.
  Future<List<String>> getFields() async {
    final value = await pdfRepresentation().get(PdfName.s, true);
    if (value is PdfName) return [value.getValue()];
    if (value is PdfArray) {
      final names = <String>[];
      for (var i = 0; i < value.size(); i++) {
        final entry = await value.get(i);
        if (entry is PdfName) names.add(entry.getValue());
      }
      return names;
    }
    return const [];
  }

  /// Gets `/A` as a list aligned with [getFields]. Table 158 says missing
  /// entries default to true and extra entries are ignored.
  Future<List<bool>> getAscending() async {
    final fields = await getFields();
    final value = await pdfRepresentation().get(PdfName.a, true);
    if (value is PdfBoolean) {
      return List<bool>.filled(fields.length, value.getValue());
    }
    if (value is PdfArray) {
      final flags = <bool>[];
      for (var i = 0; i < fields.length; i++) {
        final entry = i < value.size() ? await value.get(i) : null;
        flags.add(entry is PdfBoolean ? entry.getValue() : true);
      }
      return flags;
    }
    return List<bool>.filled(fields.length, true);
  }
}

/// Collection dictionary describing a portable collection.
///
/// See ISO 32000-1:2008, 12.3.5, Table 155.
class PdfCollection extends PdfObjectWrapper<PdfDictionary> {
  /// `/View /D`: details mode.
  static final PdfName viewDetails = PdfName.intern('D');

  /// `/View /T`: tile mode.
  static final PdfName viewTile = PdfName.intern('T');

  /// `/View /H`: the collection view is initially hidden.
  static final PdfName viewHidden = PdfName.intern('H');

  static final Set<String> _views = {
    viewDetails.getValue(),
    viewTile.getValue(),
    viewHidden.getValue(),
  };

  PdfCollection(super.pdfObject);

  /// Creates a collection dictionary with `/Type /Collection`.
  PdfCollection.create() : super(PdfDictionary()) {
    pdfRepresentation().put(PdfName.type, PdfName.collection);
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Adds a field to `/Schema` under [key], the name used to look the field
  /// up in a file specification's `/CI` collection item dictionary.
  PdfCollection addSchemaField(String key, PdfCollectionField field) {
    final existing = pdfRepresentation().getMap()?[PdfName.schema];
    PdfDictionary schema;
    if (existing is PdfDictionary) {
      schema = existing;
    } else {
      schema = PdfDictionary();
      schema.put(PdfName.type, PdfName.intern('CollectionSchema'));
      pdfRepresentation().put(PdfName.schema, schema);
    }
    schema.put(PdfName(key), field.pdfRepresentation());
    return this;
  }

  /// Gets `/Schema`.
  Future<PdfDictionary?> getSchema() async =>
      await pdfRepresentation().dictionaryEntry(PdfName.schema);

  /// Sets `/D`, the `EmbeddedFiles` key of the initially presented document.
  PdfCollection setInitialDocument(String embeddedFileKey) {
    pdfRepresentation().put(PdfName.d, PdfString(embeddedFileKey));
    return this;
  }

  /// Gets `/D`.
  Future<String?> getInitialDocument() async =>
      (await pdfRepresentation().stringEntry(PdfName.d))?.getValue();

  /// Sets `/View`, the initial view.
  PdfCollection setView(PdfName view) {
    if (!_views.contains(view.getValue())) {
      throw ArgumentError.value(
          view, 'view', 'Collection /View shall be /D, /T or /H');
    }
    pdfRepresentation().put(PdfName.intern('View'), view);
    return this;
  }

  /// Gets `/View`; the default is [viewDetails] per Table 155.
  Future<PdfName> getView() async =>
      await pdfRepresentation().nameEntry(PdfName.intern('View')) ??
      viewDetails;

  /// Sets `/Sort`.
  PdfCollection setSort(PdfCollectionSort sort) {
    pdfRepresentation().put(PdfName.intern('Sort'), sort.pdfRepresentation());
    return this;
  }

  /// Gets `/Sort`.
  Future<PdfCollectionSort?> getSort() async {
    final dictionary =
        await pdfRepresentation().dictionaryEntry(PdfName.intern('Sort'));
    return dictionary == null ? null : PdfCollectionSort(dictionary);
  }
}

/// Collection item dictionary, referenced from a file specification's `/CI`
/// entry.
///
/// See ISO 32000-1:2008, 7.11.6 "Collection Items".
class PdfCollectionItem extends PdfObjectWrapper<PdfDictionary> {
  PdfCollectionItem(super.pdfObject);

  PdfCollectionItem.create() : super(PdfDictionary()) {
    pdfRepresentation().put(PdfName.type, PdfName.intern('CollectionItem'));
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Adds a text value for the schema field named [key].
  PdfCollectionItem addText(String key, String value) {
    pdfRepresentation().put(PdfName(key), PdfString(value));
    return this;
  }

  /// Adds a date value for the schema field named [key].
  PdfCollectionItem addDate(String key, PdfDate value) {
    pdfRepresentation().put(PdfName(key), PdfString(value.getValue()));
    return this;
  }

  /// Adds a numeric value for the schema field named [key].
  PdfCollectionItem addNumber(String key, double value) {
    pdfRepresentation().put(PdfName(key), PdfNumber(value));
    return this;
  }

  /// Adds a collection subitem, which pairs a prefix `/P` with the sorted
  /// data `/D` (7.11.6).
  PdfCollectionItem addSubitem(String key, String prefix, PdfObject data) {
    final subitem = PdfDictionary();
    subitem.put(PdfName.type, PdfName.intern('CollectionSubitem'));
    subitem.put(PdfName.p, PdfString(prefix));
    subitem.put(PdfName.d, data);
    pdfRepresentation().put(PdfName(key), subitem);
    return this;
  }

  /// Gets the raw value stored for the schema field named [key].
  Future<PdfObject?> get(String key) async =>
      await pdfRepresentation().get(PdfName(key), true);
}
