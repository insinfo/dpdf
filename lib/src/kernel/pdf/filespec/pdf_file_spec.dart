import 'dart:typed_data';

import '../pdf_array.dart';
import '../pdf_boolean.dart';
import '../pdf_date.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';
import '../pdf_object.dart';
import '../pdf_object_wrapper.dart';
import '../pdf_stream.dart';
import '../pdf_string.dart';

/// File specification dictionary.
///
/// See ISO 32000-1:2008, 7.11.3 "File Specification Dictionaries", Table 44.
class PdfFileSpec extends PdfObjectWrapper<PdfDictionary> {
  /// The only standard file system name defined by PDF (7.11.5 "URL
  /// Specifications").
  static final PdfName fileSystemUrl = PdfName.intern('URL');

  PdfFileSpec(super.pdfObject);

  /// Creates an empty file specification dictionary with `/Type /Filespec`.
  PdfFileSpec.create() : super(PdfDictionary()) {
    pdfRepresentation().put(PdfName.type, PdfName.intern('Filespec'));
  }

  /// Creates a file specification for an external file.
  ///
  /// Table 44 recommends writing both `/F` (backwards compatibility) and
  /// `/UF` (cross-platform and cross-language compatibility).
  factory PdfFileSpec.external(String path, {String? description}) {
    final spec = PdfFileSpec.create();
    spec.setFileName(path);
    if (description != null) spec.setDescription(description);
    return spec;
  }

  /// Creates a file specification for a URL, setting `/FS` to `/URL` as
  /// required by 7.11.5.
  factory PdfFileSpec.url(String url, {String? description}) {
    final spec = PdfFileSpec.create();
    spec.setFileSystem(fileSystemUrl);
    spec.pdfRepresentation().put(PdfName.f, PdfString(url));
    if (description != null) spec.setDescription(description);
    return spec;
  }

  /// Creates a file specification carrying an embedded file stream in
  /// `/EF /F` and `/EF /UF` (7.11.4 "Embedded File Streams", Table 45).
  ///
  /// [mimeType] is written as the stream's `/Subtype`; [size], [creationDate]
  /// and [modificationDate] populate the embedded file parameter dictionary
  /// of Table 46.
  factory PdfFileSpec.embedded(String fileName, Uint8List bytes,
      {String? description,
      String? mimeType,
      PdfDate? creationDate,
      PdfDate? modificationDate,
      int compressionLevel = 0}) {
    final spec = PdfFileSpec.create();
    spec.setFileName(fileName);
    if (description != null) spec.setDescription(description);

    final stream = PdfStream.withBytes(bytes, compressionLevel);
    stream.put(PdfName.type, PdfName.intern('EmbeddedFile'));
    if (mimeType != null) {
      stream.put(PdfName.subtype, PdfName.intern(mimeType));
    }
    final params = PdfDictionary();
    params.put(PdfName.intern('Size'), PdfNumber.fromInt(bytes.length));
    if (creationDate != null) {
      params.put(PdfName.creationDate, PdfString(creationDate.getValue()));
    }
    if (modificationDate != null) {
      params.put(PdfName.modDate, PdfString(modificationDate.getValue()));
    }
    stream.put(PdfName.intern('Params'), params);
    spec.setEmbeddedFile(stream);
    return spec;
  }

  @override
  bool requiresIndirectStorage() => true;

  /// Sets `/FS`, the name of the file system interpreting the specification.
  PdfFileSpec setFileSystem(PdfName fileSystem) {
    pdfRepresentation().put(PdfName.intern('FS'), fileSystem);
    return this;
  }

  /// Gets `/FS`.
  Future<PdfName?> getFileSystem() async =>
      await pdfRepresentation().nameEntry(PdfName.intern('FS'));

  /// Sets both `/F` and `/UF` to [name], as recommended by Table 44.
  PdfFileSpec setFileName(String name) {
    pdfRepresentation().put(PdfName.f, PdfString(name));
    pdfRepresentation().put(PdfName.intern('UF'), PdfString(name));
    return this;
  }

  /// Gets `/UF` when present, falling back to `/F` (Table 44 says `/UF`
  /// supersedes `/F` for conforming readers).
  Future<String?> getFileName() async {
    final unicode = await pdfRepresentation().stringEntry(PdfName.intern('UF'));
    if (unicode != null) return unicode.decodeMappingText();
    return (await pdfRepresentation().stringEntry(PdfName.f))?.getValue();
  }

  /// Sets `/Desc`, the descriptive text of the file specification.
  PdfFileSpec setDescription(String description) {
    pdfRepresentation().put(PdfName.intern('Desc'), PdfString(description));
    return this;
  }

  /// Gets `/Desc`.
  Future<String?> getDescription() async =>
      (await pdfRepresentation().stringEntry(PdfName.intern('Desc')))
          ?.decodeMappingText();

  /// Sets `/AFRelationship`, the relationship between the file and the PDF
  /// content it is associated with (14.13 "Associated Files").
  PdfFileSpec setAssociatedFileRelationship(PdfName relationship) {
    pdfRepresentation().put(PdfName.afRelationship, relationship);
    return this;
  }

  /// Gets `/AFRelationship`.
  Future<PdfName?> getAssociatedFileRelationship() async =>
      await pdfRepresentation().nameEntry(PdfName.afRelationship);

  /// Sets `/V`, the volatility flag of Table 44.
  PdfFileSpec setVolatile(bool isVolatile) {
    pdfRepresentation().put(PdfName.v, PdfBoolean(isVolatile));
    return this;
  }

  /// Gets `/V`; the default is false per Table 44.
  Future<bool> isVolatile() async =>
      (await pdfRepresentation().booleanEntry(PdfName.v))?.getValue() ?? false;

  /// Sets `/ID`, a two-element file identifier array (14.4).
  PdfFileSpec setFileIdentifier(PdfString first, PdfString second) {
    pdfRepresentation().put(PdfName.id, PdfArray.fromList([first, second]));
    return this;
  }

  /// Gets `/ID`.
  Future<PdfArray?> getFileIdentifier() async =>
      await pdfRepresentation().arrayEntry(PdfName.id);

  /// Stores [stream] under both `/EF /F` and `/EF /UF`, mirroring the `/F`
  /// and `/UF` file name entries recommended by Table 44. Also forces
  /// `/Type /Filespec`, which Table 44 makes required when `/EF` is present.
  PdfFileSpec setEmbeddedFile(PdfStream stream) {
    pdfRepresentation().put(PdfName.type, PdfName.intern('Filespec'));
    final ef = _ensureDictionary(PdfName.intern('EF'));
    ef.put(PdfName.f, stream);
    ef.put(PdfName.intern('UF'), stream);
    return this;
  }

  /// Gets the embedded file stream from `/EF`, preferring `/UF` over `/F`.
  Future<PdfStream?> getEmbeddedFile() async {
    final ef = await pdfRepresentation().dictionaryEntry(PdfName.intern('EF'));
    if (ef == null) return null;
    return await ef.streamEntry(PdfName.intern('UF')) ??
        await ef.streamEntry(PdfName.f);
  }

  /// Gets the decoded bytes of the embedded file, or null when the file
  /// specification carries no `/EF` entry.
  Future<Uint8List?> getEmbeddedFileBytes() async =>
      await (await getEmbeddedFile())?.getBytes();

  /// Sets a related files array for the `/EF` key [key] (7.11.4.2,
  /// "Related Files Arrays"). The array holds `2 x n` elements pairing a name
  /// string with an embedded file stream.
  PdfFileSpec setRelatedFiles(
      PdfName key, List<MapEntry<String, PdfStream>> relatedFiles) {
    final ef = _ensureDictionary(PdfName.intern('EF'));
    if (!ef.containsKey(key)) {
      throw ArgumentError.value(key, 'key',
          'Every /RF key shall also be present in the /EF dictionary');
    }
    final array = PdfArray();
    for (final entry in relatedFiles) {
      array.add(PdfString(entry.key));
      array.add(entry.value);
    }
    pdfRepresentation().put(PdfName.type, PdfName.intern('Filespec'));
    _ensureDictionary(PdfName.intern('RF')).put(key, array);
    return this;
  }

  /// Gets the related files array registered under [key].
  Future<PdfArray?> getRelatedFiles(PdfName key) async {
    final rf = await pdfRepresentation().dictionaryEntry(PdfName.intern('RF'));
    return await rf?.arrayEntry(key);
  }

  /// Sets `/CI`, a collection item dictionary (7.11.6 "Collection Items").
  PdfFileSpec setCollectionItem(PdfDictionary item) {
    pdfRepresentation().put(PdfName.intern('CI'), item);
    return this;
  }

  /// Gets `/CI`.
  Future<PdfDictionary?> getCollectionItem() async =>
      await pdfRepresentation().dictionaryEntry(PdfName.intern('CI'));

  PdfDictionary _ensureDictionary(PdfName key) {
    final existing = pdfRepresentation().getMap()?[key];
    if (existing is PdfDictionary && existing is! PdfStream) return existing;
    final created = PdfDictionary();
    pdfRepresentation().put(key, created);
    return created;
  }
}

/// Standard `/AFRelationship` values (ISO 32000-2 / PDF/A-3 Table 45 style
/// relationships also recognised by PDF 1.7 extensions).
abstract final class PdfAssociatedFileRelationship {
  static final PdfName source = PdfName.intern('Source');
  static final PdfName data = PdfName.intern('Data');
  static final PdfName alternative = PdfName.intern('Alternative');
  static final PdfName supplement = PdfName.intern('Supplement');
  static final PdfName encryptedPayload = PdfName.intern('EncryptedPayload');
  static final PdfName formData = PdfName.intern('FormData');
  static final PdfName schema = PdfName.intern('Schema');
  static final PdfName unspecified = PdfName.intern('Unspecified');
}

/// Helper for reading a file specification that may be written either as a
/// string (7.11.2 "File Specification Strings") or as a dictionary.
Future<String?> readFileSpecificationName(PdfObject? object) async {
  if (object is PdfIndirectReference) {
    return readFileSpecificationName(await object.targetObject(true));
  }
  if (object is PdfString) return object.getValue();
  if (object is PdfDictionary && object is! PdfStream) {
    return await PdfFileSpec(object).getFileName();
  }
  return null;
}
