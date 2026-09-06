import '../../platform/io.dart';
import 'dart:typed_data';

import '../../io/source/random_access_file_or_array.dart';
import '../../io/source/pdf_tokenizer.dart';
import '../exceptions/pdf_exception.dart';
import '../exceptions/kernel_exception_message_constant.dart';
import 'pdf_object.dart';
import 'pdf_array.dart';
import 'pdf_dictionary.dart';
import 'pdf_name.dart';
import 'pdf_number.dart';
import 'pdf_string.dart';
import 'pdf_boolean.dart';
import 'pdf_null.dart';
import 'package:pdfcraft/src/kernel/pdf/pdf_xref_table.dart';
import 'package:pdfcraft/src/commons/pdfcraft_log_manager.dart';
import 'package:pdfcraft/src/io/logs/io_log_message_constant.dart';
import 'pdf_document.dart';
import 'pdf_version.dart';
import '../utils/filter_handlers.dart';
import 'reader_properties.dart';
import 'pdf_encryption.dart';
import 'pdf_stream.dart';

class CraftPdfReader {
  static final _logger = LogManager.getLoggerByName('PdfReader');
  final CraftPdfTokenizer _tokens;
  CraftPdfDocument? document;
  final CraftPdfXrefTable _xref = CraftPdfXrefTable();
  String? _pdfVersion;
  CraftPdfDictionary? _trailer;
  int _lastXref = 0;
  bool _rebuiltXref = false;
  bool _xrefStm = false;
  bool _encrypted = false;
  CraftReaderProperties properties;
  CraftPdfEncryption? _encryption;

  CraftPdfReader.fromBytes(Uint8List bytes, [CraftReaderProperties? properties])
      : _tokens = CraftPdfTokenizer(CraftRandomAccessFileOrArray(bytes)),
        properties = properties ?? CraftReaderProperties();

  static Future<CraftPdfReader> fromFile(String path,
      [CraftReaderProperties? properties]) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    return CraftPdfReader.fromBytes(bytes, properties);
  }

  void setDocument(CraftPdfDocument doc) {
    document = doc;
  }

  CraftPdfVersion getPdfVersion() {
    return CraftPdfVersion.fromString(_pdfVersion ?? "1.7");
  }

  String? get pdfVersion => _pdfVersion;
  CraftPdfDictionary? get trailer => _trailer;
  CraftPdfDictionary? fileTrailer() => _trailer;
  CraftPdfXrefTable get xref => _xref;
  bool get rebuiltXref => _rebuiltXref;
  bool get xrefStm => _xrefStm;
  bool get encrypted => _encrypted;
  int get lastXref => _lastXref;
  CraftPdfEncryption? securityCodec() => _encryption;

  Future<void> close() async {
    await _tokens.close();
  }

  CraftRandomAccessFileOrArray getSafeFile() {
    return _tokens.getSafeFile();
  }

  /// Gets the original bytes of the PDF document.
  /// Essential for append mode to preserve the original content.
  Uint8List? getOriginalBytes() {
    return _tokens.getSafeFile().getBytes();
  }

  /// Gets the position of the last xref section.
  /// Used in append mode to set the Prev pointer in the new trailer.
  int getLastXrefPosition() => _lastXref;

  Future<void> read() async {
    await _readHeader();
    await _readXref();
    _xref.markReadingCompleted();
    await _checkEncryption();
  }

  Future<void> _readHeader() async {
    final header = await _tokens.checkPdfHeader();
    if (header.length >= 7) {
      _pdfVersion = header.substring(4, 7);
    }
  }

  Future<void> _readXref() async {
    final startxrefPos = await _tokens.getStartxref();
    _tokens.seek(startxrefPos);
    await _tokens.nextValidToken();
    await _tokens.nextValidToken();
    if (_tokens.getTokenType() != TokenType.number) {
      throw CraftPdfException(CraftKernelExceptionMessageConstant
          .pdfStartxrefIsNotFollowedByANumber);
    }
    _lastXref = _tokens.getIntValue();
    _tokens.seek(_lastXref);

    // Track visited xref positions to prevent infinite loops (cyclic references)
    final visitedXrefPositions = <int>{};

    try {
      await _readXrefSectionWithCycleCheck(_lastXref, visitedXrefPositions);
    } catch (e) {
      _rebuiltXref = true;
      throw CraftPdfException('Failed to read xref: $e');
    }
  }

  /// Reads xref section with cycle detection to prevent infinite loops
  Future<void> _readXrefSectionWithCycleCheck(
      int position, Set<int> visitedPositions) async {
    // Check for cyclic reference
    if (visitedPositions.contains(position)) {
      return; // Cyclic reference detected, stop recursion
    }
    visitedPositions.add(position);

    _tokens.seek(position);
    if (!await _tokens.nextToken()) {
      throw CraftPdfException(
          CraftKernelExceptionMessageConstant.unexpectedEndOfFile);
    }
    if (_tokens.tokenValueEqualsTo(CraftPdfTokenizer.xref)) {
      await _readXrefTableWithCycleCheck(visitedPositions);
    } else {
      _xrefStm = true;
      _tokens.seek(position);
      await _readXrefStreamWithCycleCheck(visitedPositions);
    }
  }

  Future<void> _readXrefSection([int? position]) async {
    _tokens.seek(position ?? _lastXref);
    if (!await _tokens.nextToken()) {
      throw CraftPdfException(
          CraftKernelExceptionMessageConstant.unexpectedEndOfFile);
    }
    if (_tokens.tokenValueEqualsTo(CraftPdfTokenizer.xref)) {
      await _readXrefTable();
    } else {
      _xrefStm = true;
      _tokens.seek(_lastXref);
      await _readXrefStream();
    }
  }

  Future<void> _readXrefTable() async {
    while (true) {
      if (!await _tokens.nextToken()) {
        throw CraftPdfException(
            CraftKernelExceptionMessageConstant.unexpectedEndOfFile);
      }
      if (_tokens.getTokenType() == TokenType.other &&
          _tokens.tokenValueEqualsTo(CraftPdfTokenizer.trailer)) {
        break;
      }
      if (_tokens.getTokenType() != TokenType.number) {
        throw CraftPdfException(CraftKernelExceptionMessageConstant
            .objectNumberOfTheFirstObjectInThisXrefSubsectionNotFound);
      }
      final firstObj = _tokens.getIntValue();
      if (!await _tokens.nextToken() ||
          _tokens.getTokenType() != TokenType.number) {
        throw CraftPdfException(CraftKernelExceptionMessageConstant
            .numberOfEntriesInThisXrefSubsectionNotFound);
      }
      final numEntries = _tokens.getIntValue();
      for (var i = 0; i < numEntries; i++) {
        final objNr = firstObj + i;
        await _tokens.nextToken();
        final offset = _tokens.getIntValue();
        await _tokens.nextToken();
        final gen = _tokens.getIntValue();
        await _tokens.nextToken();
        final entryType = _tokens.getStringValue();
        final existing = _xref.get(objNr);
        if (existing != null &&
            (existing.getOffset() > 0 || existing.isFree())) {
          continue;
        }
        final ref = CraftPdfIndirectReference(objNr, gen);
        ref.setReader(this);
        ref.setOffset(offset);
        if (entryType == 'f') ref.setState(CraftPdfObject.free);
        _xref.add(ref);
      }
    }
    await _tokens.nextValidToken();
    final sectionTrailer = await _readDictionary();
    if (_trailer == null) {
      _trailer = sectionTrailer;
    } else {
      // Merge properties from older trailers that don't exist in the main one
      await _trailer!.mergeDifferent(sectionTrailer);
    }

    final prev = await sectionTrailer.integerEntry(CraftPdfName.prev);
    if (prev != null) {
      await _readXrefSection(prev);
    }
  }

  /// Version with cycle detection for following Prev pointers
  Future<void> _readXrefTableWithCycleCheck(Set<int> visitedPositions) async {
    while (true) {
      if (!await _tokens.nextToken()) {
        throw CraftPdfException(
            CraftKernelExceptionMessageConstant.unexpectedEndOfFile);
      }
      if (_tokens.getTokenType() == TokenType.other &&
          _tokens.tokenValueEqualsTo(CraftPdfTokenizer.trailer)) {
        break;
      }
      if (_tokens.getTokenType() != TokenType.number) {
        throw CraftPdfException(CraftKernelExceptionMessageConstant
            .objectNumberOfTheFirstObjectInThisXrefSubsectionNotFound);
      }
      final firstObj = _tokens.getIntValue();
      if (!await _tokens.nextToken() ||
          _tokens.getTokenType() != TokenType.number) {
        throw CraftPdfException(CraftKernelExceptionMessageConstant
            .numberOfEntriesInThisXrefSubsectionNotFound);
      }
      final numEntries = _tokens.getIntValue();
      for (var i = 0; i < numEntries; i++) {
        final objNr = firstObj + i;
        await _tokens.nextToken();
        final offset = _tokens.getIntValue();
        await _tokens.nextToken();
        final gen = _tokens.getIntValue();
        await _tokens.nextToken();
        final entryType = _tokens.getStringValue();
        final existing = _xref.get(objNr);
        if (existing != null &&
            (existing.getOffset() > 0 || existing.isFree())) {
          continue;
        }
        final ref = CraftPdfIndirectReference(objNr, gen);
        ref.setReader(this);
        ref.setOffset(offset);
        if (entryType == 'f') ref.setState(CraftPdfObject.free);
        _xref.add(ref);
      }
    }
    await _tokens.nextValidToken();
    _trailer = await _readDictionary();
    final prev = await _trailer!.integerEntry(CraftPdfName.prev);
    if (prev != null) {
      await _readXrefSectionWithCycleCheck(prev, visitedPositions);
    }
  }

  Future<void> _readXrefStream() async {
    await _tokens.nextValidToken();
    await _tokens.nextValidToken();
    final streamDict = await _readDictionary();
    _trailer = streamDict;
    final size = await streamDict.integerEntry(CraftPdfName.size);
    final wArray = await streamDict.arrayEntry(CraftPdfName.w);
    final w1 = (await wArray!.numberEntry(0))?.intValue() ?? 0;
    final w2 = (await wArray.numberEntry(1))?.intValue() ?? 0;
    final w3 = (await wArray.numberEntry(2))?.intValue() ?? 0;
    final indexArrayObj = await streamDict.arrayEntry(CraftPdfName.index);
    List<int> xrefIndex =
        indexArrayObj != null ? await indexArrayObj.toIntArray() : [0, size!];

    final streamLength = await streamDict.integerEntry(CraftPdfName.length);
    await _tokens.nextValidToken();
    var ch = await _tokens.read();
    if (ch == 0x0D) {
      ch = await _tokens.read();
      if (ch != 0x0A) _tokens.backOnePosition(ch);
    } else if (ch != 0x0A) {
      _tokens.backOnePosition(ch);
    }
    final rawBytes = Uint8List(streamLength!);
    for (var i = 0; i < streamLength; i++) {
      rawBytes[i] = await _tokens.read();
    }
    final decodedBytes =
        await CraftFilterHandlers.decodeBytes(rawBytes, streamDict);
    _xref.setCapacity(size!);
    var byteOffset = 0;
    for (var i = 0; i < xrefIndex.length; i += 2) {
      final first = xrefIndex[i];
      final count = xrefIndex[i + 1];
      for (var j = 0; j < count; j++) {
        final objNum = first + j;
        final type =
            w1 > 0 ? _readXrefStreamField(decodedBytes, byteOffset, w1) : 1;
        byteOffset += w1;
        final field2 = _readXrefStreamField(decodedBytes, byteOffset, w2);
        byteOffset += w2;
        final field3 = _readXrefStreamField(decodedBytes, byteOffset, w3);
        byteOffset += w3;
        final existing = _xref.get(objNum);
        if (existing != null &&
            (existing.getOffset() > 0 || existing.isFree())) {
          continue;
        }
        final ref = CraftPdfIndirectReference(objNum);
        ref.setReader(this);
        switch (type) {
          case 0:
            ref.setState(CraftPdfObject.free);
            ref.setOffset(field2);
            break;
          case 1:
            ref.setOffset(field2);
            break;
          case 2:
            ref.setObjStreamNumber(field2);
            ref.setIndex(field3);
            break;
        }
        _xref.add(ref);
      }
    }
    final prev = await streamDict.integerEntry(CraftPdfName.prev);
    if (prev != null) {
      _tokens.seek(prev);
      await _readXrefSection();
    }
  }

  /// Version with cycle detection for following Prev pointers in xref streams
  Future<void> _readXrefStreamWithCycleCheck(Set<int> visitedPositions) async {
    await _tokens.nextValidToken();
    await _tokens.nextValidToken();
    final streamDict = await _readDictionary();
    _trailer = streamDict;
    final size = await streamDict.integerEntry(CraftPdfName.size);
    final wArray = await streamDict.arrayEntry(CraftPdfName.w);
    final w1 = (await wArray!.numberEntry(0))?.intValue() ?? 0;
    final w2 = (await wArray.numberEntry(1))?.intValue() ?? 0;
    final w3 = (await wArray.numberEntry(2))?.intValue() ?? 0;

    final indexArrayObj = await streamDict.arrayEntry(CraftPdfName.index);
    List<int> xrefIndex =
        indexArrayObj != null ? await indexArrayObj.toIntArray() : [0, size!];

    final streamLength = await streamDict.integerEntry(CraftPdfName.length);
    await _tokens.nextValidToken();
    var ch = await _tokens.read();
    if (ch == 0x0D) {
      ch = await _tokens.read();
      if (ch != 0x0A) _tokens.backOnePosition(ch);
    } else if (ch != 0x0A) {
      _tokens.backOnePosition(ch);
    }
    final rawBytes = Uint8List(streamLength!);
    for (var i = 0; i < streamLength; i++) {
      rawBytes[i] = await _tokens.read();
    }
    final decodedBytes =
        await CraftFilterHandlers.decodeBytes(rawBytes, streamDict);
    _xref.setCapacity(size!);
    var byteOffset = 0;
    for (var i = 0; i < xrefIndex.length; i += 2) {
      final first = xrefIndex[i];
      final count = xrefIndex[i + 1];
      for (var j = 0; j < count; j++) {
        final objNum = first + j;
        final type =
            w1 > 0 ? _readXrefStreamField(decodedBytes, byteOffset, w1) : 1;
        byteOffset += w1;
        final field2 = _readXrefStreamField(decodedBytes, byteOffset, w2);
        byteOffset += w2;
        final field3 = _readXrefStreamField(decodedBytes, byteOffset, w3);
        byteOffset += w3;
        final existing = _xref.get(objNum);
        if (existing != null &&
            (existing.getOffset() > 0 || existing.isFree())) {
          continue;
        }
        final ref = CraftPdfIndirectReference(objNum);
        ref.setReader(this);
        switch (type) {
          case 0:
            ref.setState(CraftPdfObject.free);
            ref.setOffset(field2);
            break;
          case 1:
            ref.setOffset(field2);
            break;
          case 2:
            ref.setObjStreamNumber(field2);
            ref.setIndex(field3);
            break;
        }
        _xref.add(ref);
      }
    }
    final prev = await streamDict.integerEntry(CraftPdfName.prev);
    if (prev != null) {
      await _readXrefSectionWithCycleCheck(prev, visitedPositions);
    }
  }

  int _readXrefStreamField(Uint8List data, int offset, int width) {
    if (width == 0) return 0;
    var result = 0;
    for (var i = 0; i < width; i++) result = (result << 8) | data[offset + i];
    return result;
  }

  Future<void> _checkEncryption() async {
    if (_trailer == null) return;
    final encrypt = await _trailer!.get(CraftPdfName.encrypt, true);
    if (encrypt != null && encrypt is! CraftPdfNull) {
      _encrypted = true;
      if (encrypt is CraftPdfDictionary) {
        final idArray = await _trailer!.arrayEntry(CraftPdfName.id);
        Uint8List? documentId;
        if (idArray != null && idArray.size() > 0) {
          final idStr = await idArray.stringEntry(0);
          documentId = idStr?.getValueBytes();
        }

        final password = properties.password ?? Uint8List(0);

        _encryption = await CraftPdfEncryption.createFromDictionary(
            encrypt, password, documentId ?? Uint8List(0));
      }
    }
  }

  Future<CraftPdfDictionary> _readDictionary(
      {CraftPdfTokenizer? tokenizer}) async {
    final tokens = tokenizer ?? _tokens;
    final dict = CraftPdfDictionary();
    while (true) {
      await tokens.nextValidToken();
      if (tokens.getTokenType() == TokenType.endDic) break;
      final key = CraftPdfName.fromBytes(tokens.getByteContent());
      await tokens.nextValidToken();
      dict.put(key, await _readObject(tokenizer: tokens));
    }
    return dict;
  }

  Future<CraftPdfArray> _readArray({CraftPdfTokenizer? tokenizer}) async {
    final tokens = tokenizer ?? _tokens;
    final arr = CraftPdfArray();
    while (true) {
      await tokens.nextValidToken();
      if (tokens.getTokenType() == TokenType.endArray) break;
      arr.add(await _readObject(tokenizer: tokens));
    }
    return arr;
  }

  Future<CraftPdfObject> _readObject({CraftPdfTokenizer? tokenizer}) async {
    final tokens = tokenizer ?? _tokens;
    switch (tokens.getTokenType()) {
      case TokenType.startDic:
        final dict = await _readDictionary(tokenizer: tokens);
        final pos = tokens.getPosition();
        if (await tokens.nextToken() &&
            tokens.getTokenType() == TokenType.other &&
            tokens.getStringValue() == 'stream') {
          return await _readStream(dict, tokenizer: tokens);
        } else {
          tokens.seek(pos);
          return dict;
        }
      case TokenType.startArray:
        return await _readArray(tokenizer: tokens);
      case TokenType.number:
        return CraftPdfNumber.fromBytes(tokens.getByteContent());
      case TokenType.string:
        return CraftPdfString.fromBytes(
            tokens.getDecodedStringContent(), tokens.isHexString());
      case TokenType.name:
        return CraftPdfName.fromBytes(tokens.getByteContent());
      case TokenType.ref:
        final objNr = tokens.getObjNr();
        var ref = _xref.get(objNr);
        if (ref != null && ref.isFree()) {
          _logger.logWarning(CraftIoLogMessageConstant.invalidIndirectReference
              .replaceAll("{0}", objNr.toString())
              .replaceAll("{1}", tokens.getGenNr().toString()));
          return CraftPdfNull();
        }
        if (ref == null) {
          ref = CraftPdfIndirectReference(objNr, tokens.getGenNr());
          _xref.add(ref);
        }
        ref.setDocument(document);
        ref.setReader(this);
        return ref;
      case TokenType.other:
        final v = tokens.getStringValue();
        if (v == 'null') return CraftPdfNull();
        if (v == 'true') return CraftPdfBoolean(true);
        if (v == 'false') return CraftPdfBoolean(false);
        return CraftPdfNull();
      default:
        return CraftPdfNull();
    }
  }

  Future<CraftPdfStream> _readStream(CraftPdfDictionary dict,
      {CraftPdfTokenizer? tokenizer}) async {
    final tokens = tokenizer ?? _tokens;
    final lengthObj = await dict.numberEntry(CraftPdfName.length);
    if (lengthObj == null) {
      throw CraftPdfException("Stream length not found");
    }
    int length = lengthObj.intValue();

    var ch = await tokens.read();
    if (ch == 0x0D) {
      ch = await tokens.read();
      if (ch != 0x0A) tokens.backOnePosition(ch);
    } else if (ch != 0x0A) {
      tokens.backOnePosition(ch);
    }

    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = await tokens.read();
    }

    await tokens.nextValidToken();
    if (!tokens.tokenValueEqualsTo(CraftPdfTokenizer.endStream)) {
      throw CraftPdfException("Stream did not end with 'endstream'");
    }

    final stream = CraftPdfStream.withBytes(bytes);
    final entries = await dict.entrySet();
    for (final entry in entries) {
      stream.put(entry.key, entry.value);
    }
    return stream;
  }

  Future<CraftPdfObject?> readObject(int objNr) async {
    final ref = _xref.get(objNr);
    if (ref == null || ref.isFree()) return null;

    if (ref.getObjStreamNumber() > 0) {
      final streamRef = _xref.get(ref.getObjStreamNumber());
      if (streamRef != null) {
        final streamObj = await readObject(streamRef.objNr);
        if (streamObj is CraftPdfStream) {
          return await _readObjectFromStream(streamObj, ref);
        }
      }
    }

    _tokens.seek(ref.getOffset());
    await _tokens.nextValidToken();
    await _tokens.nextValidToken();
    final obj = await _readObject();

    // Set indirect reference and document on the returned object
    ref.setDocument(document);
    ref.setReader(this);
    ref.assignTargetObject(obj);
    obj.setIndirectReference(ref);

    return obj;
  }

  Future<CraftPdfObject?> _readObjectFromStream(
      CraftPdfStream stream, CraftPdfIndirectReference ref) async {
    final bytes = await stream.getBytes();
    if (bytes == null) return null;

    final firstObj = await stream.numberEntry(CraftPdfName.first);
    final nObj = await stream.numberEntry(CraftPdfName.n);
    final first = firstObj?.intValue() ?? 0;
    final n = nObj?.intValue() ?? 0;

    final tokenizer = CraftPdfTokenizer(CraftRandomAccessFileOrArray(bytes));

    int objOffset = -1;
    for (int k = 0; k < n; k++) {
      await tokenizer.nextValidToken();
      final objNum = tokenizer.getIntValue();
      await tokenizer.nextValidToken();
      final off = tokenizer.getIntValue();

      if (objNum == ref.objNr) {
        objOffset = off;
        break;
      }
    }

    if (objOffset == -1) return null;

    tokenizer.seek(first + objOffset);
    await tokenizer.nextValidToken();

    return await _readObject(tokenizer: tokenizer);
  }

  Future<CraftPdfDictionary?> rootCatalog() async {
    final rootRef = await _trailer?.get(CraftPdfName.root, false);
    if (rootRef is CraftPdfIndirectReference) {
      final obj = await readObject(rootRef.objectNumber());
      return obj is CraftPdfDictionary ? obj : null;
    }
    return rootRef is CraftPdfDictionary ? rootRef : null;
  }

  Future<CraftPdfDictionary?> getInfo() async {
    final infoRef = await _trailer?.get(CraftPdfName.info, false);
    if (infoRef is CraftPdfIndirectReference) {
      final obj = await readObject(infoRef.objectNumber());
      return obj is CraftPdfDictionary ? obj : null;
    }
    return infoRef is CraftPdfDictionary ? infoRef : null;
  }

  Future<int> pageTotal() async {
    final catalog = await rootCatalog();
    if (catalog == null) return 0;
    final pages = await catalog.dictionaryEntry(CraftPdfName.pages);
    return await pages?.integerEntry(CraftPdfName.count) ?? 0;
  }
}
