import '../../platform/io.dart';
import 'dart:typed_data';

import '../../io/source/random_access_file_or_array.dart';
import '../../io/source/pdf_byte_source.dart';
import '../../io/source/pdf_file_source.dart';
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
import 'package:dpdf/src/kernel/pdf/pdf_xref_table.dart';
import 'package:dpdf/src/commons/dpdf_log_manager.dart';
import 'package:dpdf/src/io/logs/io_log_message_constant.dart';
import 'pdf_document.dart';
import 'pdf_version.dart';
import '../utils/filter_handlers.dart';
import 'reader_properties.dart';
import 'pdf_encryption.dart';
import 'pdf_stream.dart';

class PdfReader {
  static final _logger = LogManager.getLoggerByName('PdfReader');
  final PdfTokenizer _tokens;
  PdfDocument? document;
  final PdfXrefTable _xref = PdfXrefTable();
  String? _pdfVersion;
  PdfDictionary? _trailer;
  int _lastXref = 0;
  bool _rebuiltXref = false;
  bool _xrefStm = false;
  bool _encrypted = false;
  bool _recovering = false;
  int _objectDepth = 0;
  final Map<int, int> _recoveredStreamLengths = {};
  int _recoveryBoundaryStart = 0;
  ReaderProperties properties;
  PdfEncryption? _encryption;

  PdfReader.fromBytes(Uint8List bytes, [ReaderProperties? properties])
      : _tokens = PdfTokenizer(RandomAccessFileOrArray(bytes)),
        properties = properties ?? ReaderProperties();

  PdfReader.fromSource(PdfByteSource source, [ReaderProperties? properties])
      : _tokens = PdfTokenizer(RandomAccessFileOrArray.fromSource(source)),
        properties = properties ?? ReaderProperties();

  static Future<PdfReader> fromFile(String path,
      [ReaderProperties? properties]) async {
    final effective = properties ?? ReaderProperties();
    final file = File(path);
    final threshold = effective.largeFileBlockThreshold;
    final useBlocks = effective.readFileInBlocks ||
        (threshold != null && await file.length() >= threshold);
    if (useBlocks) {
      return PdfReader.fromSource(
          PdfFileSource.open(path,
              blockSize: effective.fileBlockSize,
              maxBlocks: effective.fileCacheBlocks),
          effective);
    }
    final bytes = await file.readAsBytes();
    return PdfReader.fromBytes(bytes, effective);
  }

  void setDocument(PdfDocument doc) {
    document = doc;
  }

  PdfVersion getPdfVersion() {
    return PdfVersion.fromString(_pdfVersion ?? "1.7");
  }

  String? get pdfVersion => _pdfVersion;
  PdfDictionary? get trailer => _trailer;
  PdfDictionary? fileTrailer() => _trailer;
  PdfXrefTable get xref => _xref;
  bool get rebuiltXref => _rebuiltXref;
  bool get xrefStm => _xrefStm;
  bool get encrypted => _encrypted;
  bool get readsFileInBlocks => !_tokens.getSafeFile().isMemoryBacked;
  int get lastXref => _lastXref;
  PdfEncryption? securityCodec() => _encryption;

  void close() {
    _tokens.close();
  }

  RandomAccessFileOrArray getSafeFile() {
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
    _readHeader();
    try {
      await _readXref();
    } on Exception {
      if (properties.recoveryMode == PdfRecoveryMode.strict) rethrow;
      _recovering = true;
      try {
        await _recoverCrossReferences();
      } finally {
        _recovering = false;
      }
    }
    _xref.markReadingCompleted();
    await _checkEncryption();
  }

  /// Reconstructs physical objects and indexes unencrypted object streams.
  /// A missing stream length requires a delimiter heuristic: an embedded
  /// endstream/endobj pair is inherently ambiguous in a damaged PDF.
  Future<void> _recoverCrossReferences() async {
    final file = _tokens.getSafeFile();
    if (properties.recoveryScanLimit <= 0 ||
        file.length() > properties.recoveryScanLimit ||
        properties.recoveryObjectLimit <= 0) {
      throw FormatException('PDF recovery exceeds its configured scan limits.');
    }
    _recoveredStreamLengths.clear();
    _xref.clearAllReferences();
    _trailer = null;
    _xrefStm = false;
    _tokens.seek(0);
    // Consume the header comment so the first object never receives offset zero.
    _tokens.nextToken();
    int? trailerPosition;
    int? catalogNumber;
    final objectStreams = <(int, int)>[];
    final definitionOffsets = <int, int>{};
    var recovered = 0;
    while (_tokens.getPosition() < file.length()) {
      final position = _tokens.getPosition();
      _tokens.nextValidToken();
      if (_tokens.getTokenType() == TokenType.endOfFile) break;
      if (_tokens.getTokenType() == TokenType.other &&
          _tokens.getStringValue() == 'trailer') {
        trailerPosition = _tokens.getPosition();
        _tokens.nextValidToken();
        if (_tokens.getTokenType() != TokenType.startDic) {
          throw FormatException('Recovery found a malformed trailer.');
        }
        await _readDictionary();
        continue;
      }
      if (_tokens.getTokenType() != TokenType.obj) continue;
      final number = _tokens.getObjNr();
      final generation = _tokens.getGenNr();
      if (number <= 0 ||
          number > properties.recoveryObjectLimit ||
          generation < 0 ||
          generation > 65535 ||
          ++recovered > properties.recoveryObjectLimit) {
        throw FormatException(
            'Recovery object identifier or count is invalid.');
      }
      definitionOffsets[number] = position;
      _xref.add(PdfIndirectReference(number, generation)
        ..setOffset(position)
        ..setReader(this)
        ..setDocument(document));
      final dictionaryPosition = _tokens.getPosition();
      _tokens.nextValidToken();
      if (_tokens.getTokenType() != TokenType.startDic) continue;
      final dictionary = await _readDictionary();
      final type = await dictionary.get(PdfName.type, false);
      if (type == PdfName.catalog) catalogNumber = number;
      if (type == PdfName.objStm) objectStreams.add((number, position));
      if (type == PdfName.xref) trailerPosition = dictionaryPosition;
      final afterDictionary = _tokens.getPosition();
      _tokens.nextValidToken();
      if (_tokens.getTokenType() == TokenType.other &&
          _tokens.getStringValue() == 'stream') {
        var dataStart = _tokens.getPosition();
        file.seek(dataStart);
        final first = file.read();
        if (first == 13) {
          if (file.read() != 10) file.seek(file.getPosition() - 1);
        } else if (first != 10) {
          throw FormatException('Recovery stream has no line separator.');
        }
        dataStart = file.getPosition();
        final length = await dictionary.get(PdfName.length, false);
        int? end;
        if (properties.recoveryMode == PdfRecoveryMode.skipStreams &&
            length is PdfNumber &&
            length.intValue() >= 0) {
          final candidate = dataStart + length.intValue();
          if (candidate < file.length()) end = _recoveryStreamEnd(candidate);
        }
        if (end == null) {
          for (var candidate = dataStart;
              candidate < file.length();
              candidate++) {
            file.seek(candidate);
            if (file.read() != 101) continue;
            end = _recoveryStreamEnd(candidate, exact: true);
            if (end != null) break;
          }
        }
        if (end == null) {
          throw FormatException(
              'Recovery could not locate the stream boundary.');
        }
        _recoveredStreamLengths[dataStart] = _recoveryBoundaryStart - dataStart;
        _tokens.seek(end);
      } else {
        _tokens.seek(afterDictionary);
      }
    }
    if (recovered == 0) throw FormatException('Recovery found no PDF objects.');
    if (trailerPosition != null) {
      _tokens.seek(trailerPosition);
      _tokens.nextValidToken();
      _trailer = await _readDictionary();
    } else {
      _trailer = PdfDictionary();
    }
    final encryption = await _trailer!.get(PdfName.encrypt, false);
    if (encryption != null && encryption is! PdfNull) {
      throw UnsupportedError(
          'Cross-reference recovery of encrypted PDFs is not supported.');
    }
    final compressedNumbers = <int>[];
    for (final (streamNumber, physicalOffset) in objectStreams) {
      if (definitionOffsets[streamNumber] != physicalOffset) continue;
      final stream = await readObject(streamNumber);
      if (stream is! PdfStream) {
        throw FormatException('Recovered object stream is not a stream.');
      }
      final decoded = await stream.getBytes();
      final first = await stream.integerEntry(PdfName.first);
      final count = await stream.integerEntry(PdfName.n);
      if (decoded == null ||
          first == null ||
          count == null ||
          first < 0 ||
          first > decoded.length ||
          count < 0 ||
          count > properties.recoveryObjectLimit ||
          decoded.length >
              (properties.memoryLimit ?? properties.recoveryScanLimit)) {
        throw FormatException(
            'Recovered object stream exceeds its structural limits.');
      }
      final header = PdfTokenizer(RandomAccessFileOrArray(decoded));
      final seen = <int>{};
      for (var index = 0; index < count; index++) {
        header.nextToken();
        if (header.getTokenType() != TokenType.number) {
          throw FormatException(
              'Object stream header requires an object identifier.');
        }
        final number = header.getIntValue();
        header.nextToken();
        if (header.getTokenType() != TokenType.number) {
          throw FormatException(
              'Object stream header requires a relative offset.');
        }
        final offset = header.getIntValue();
        if (number <= 0 ||
            number > properties.recoveryObjectLimit ||
            number == streamNumber ||
            ++recovered > properties.recoveryObjectLimit ||
            !seen.add(number) ||
            offset < 0 ||
            first + offset >= decoded.length ||
            header.getPosition() > first) {
          throw FormatException(
              'Object stream header contains an invalid entry.');
        }
        if ((definitionOffsets[number] ?? -1) > physicalOffset) continue;
        definitionOffsets[number] = physicalOffset;
        _xref.add(PdfIndirectReference(number, 0)
          ..setObjStreamNumber(streamNumber)
          ..setIndex(index)
          ..setReader(this)
          ..setDocument(document));
        compressedNumbers.add(number);
      }
      header.close();
    }
    // Re-read trailer references now that compressed targets are indexed.
    if (trailerPosition != null) {
      _tokens.seek(trailerPosition);
      _tokens.nextValidToken();
      _trailer = await _readDictionary();
    }
    if (await rootCatalog() == null) {
      for (final number in compressedNumbers.reversed) {
        final object = await readObject(number);
        if (object is PdfDictionary &&
            await object.get(PdfName.type, false) == PdfName.catalog) {
          catalogNumber = number;
          break;
        }
      }
    }
    if (await rootCatalog() == null && catalogNumber != null) {
      final reference = _xref.get(catalogNumber)!;
      final object = await readObject(catalogNumber);
      if (object is PdfDictionary &&
          await object.get(PdfName.type, false) == PdfName.catalog) {
        _trailer!.put(PdfName.root, reference);
      }
    }
    if (await rootCatalog() == null) {
      throw FormatException('Recovery could not locate a usable PDF catalog.');
    }
    _trailer!.put(PdfName.size, PdfNumber(_xref.size().toDouble()));
    _lastXref = 0;
    _rebuiltXref = true;
  }

  int? _recoveryStreamEnd(int position, {bool exact = false}) {
    final file = _tokens.getSafeFile();
    bool whitespace(int byte) => const [0, 9, 10, 12, 13, 32].contains(byte);
    file.seek(position);
    if (!exact) {
      while (file.getPosition() < file.length()) {
        final byte = file.read();
        if (!whitespace(byte)) {
          file.seek(file.getPosition() - 1);
          break;
        }
      }
    } else if (position > 0) {
      file.seek(position - 1);
      if (!whitespace(file.read())) return null;
    }
    final boundary = file.getPosition();
    for (final byte in 'endstream'.codeUnits) {
      if (file.read() != byte) return null;
    }
    var next = file.read();
    if (!whitespace(next)) return null;
    while (whitespace(next)) {
      next = file.read();
    }
    if (next != 101) return null;
    for (final byte in 'ndobj'.codeUnits) {
      if (file.read() != byte) return null;
    }
    final end = file.getPosition();
    next = file.read();
    if (next != -1 && !whitespace(next) && next != 37) return null;
    _recoveryBoundaryStart = boundary;
    return end;
  }

  void _readHeader() {
    final header = _tokens.checkPdfHeader();
    if (header.length >= 7) {
      _pdfVersion = header.substring(4, 7);
    }
  }

  Future<void> _readXref() async {
    final startxrefPos = _tokens.getStartxref();
    _tokens.seek(startxrefPos);
    _tokens.nextValidToken();
    _tokens.nextValidToken();
    if (_tokens.getTokenType() != TokenType.number) {
      throw PdfException(
          KernelExceptionMessageConstant.pdfStartxrefIsNotFollowedByANumber);
    }
    _lastXref = _tokens.getIntValue();
    _validateXrefPosition(_lastXref);
    _tokens.seek(_lastXref);

    // Track visited xref positions to prevent infinite loops (cyclic references)
    final visitedXrefPositions = <int>{};

    try {
      await _readXrefSectionWithCycleCheck(_lastXref, visitedXrefPositions);
    } on Exception catch (e) {
      throw PdfException('Failed to read xref: $e');
    }
  }

  /// Reads xref section with cycle detection to prevent infinite loops
  Future<void> _readXrefSectionWithCycleCheck(
      int position, Set<int> visitedPositions) async {
    _validateXrefPosition(position);
    // Check for cyclic reference
    if (visitedPositions.contains(position)) {
      return; // Cyclic reference detected, stop recursion
    }
    visitedPositions.add(position);

    _tokens.seek(position);
    if (!_tokens.nextToken()) {
      throw PdfException(KernelExceptionMessageConstant.unexpectedEndOfFile);
    }
    if (_tokens.tokenValueEqualsTo(PdfTokenizer.xref)) {
      await _readXrefTableWithCycleCheck(visitedPositions);
    } else {
      _xrefStm = true;
      _tokens.seek(position);
      await _readXrefStreamWithCycleCheck(visitedPositions);
    }
  }

  void _validateXrefPosition(int position) {
    if (position < 0 || position >= _tokens.getSafeFile().length()) {
      throw FormatException(
          'Cross-reference offset lies outside the PDF bytes: $position');
    }
  }

  Future<void> _readXrefSection([int? position]) async {
    _validateXrefPosition(position ?? _lastXref);
    _tokens.seek(position ?? _lastXref);
    if (!_tokens.nextToken()) {
      throw PdfException(KernelExceptionMessageConstant.unexpectedEndOfFile);
    }
    if (_tokens.tokenValueEqualsTo(PdfTokenizer.xref)) {
      await _readXrefTable();
    } else {
      _xrefStm = true;
      _tokens.seek(_lastXref);
      await _readXrefStream();
    }
  }

  Future<void> _readXrefTable() async {
    while (true) {
      if (!_tokens.nextToken()) {
        throw PdfException(KernelExceptionMessageConstant.unexpectedEndOfFile);
      }
      if (_tokens.getTokenType() == TokenType.other &&
          _tokens.tokenValueEqualsTo(PdfTokenizer.trailer)) {
        break;
      }
      if (_tokens.getTokenType() != TokenType.number) {
        throw PdfException(KernelExceptionMessageConstant
            .objectNumberOfTheFirstObjectInThisXrefSubsectionNotFound);
      }
      final firstObj = _tokens.getIntValue();
      if (!_tokens.nextToken() || _tokens.getTokenType() != TokenType.number) {
        throw PdfException(KernelExceptionMessageConstant
            .numberOfEntriesInThisXrefSubsectionNotFound);
      }
      final numEntries = _tokens.getIntValue();
      for (var i = 0; i < numEntries; i++) {
        final objNr = firstObj + i;
        _tokens.nextToken();
        final offset = _tokens.getIntValue();
        _tokens.nextToken();
        final gen = _tokens.getIntValue();
        _tokens.nextToken();
        final entryType = _tokens.getStringValue();
        final existing = _xref.get(objNr);
        if (existing != null &&
            (existing.getOffset() > 0 ||
                existing.getObjStreamNumber() > 0 ||
                existing.isFree())) {
          continue;
        }
        final ref = PdfIndirectReference(objNr, gen);
        ref.setReader(this);
        ref.setOffset(offset);
        if (entryType == 'f') ref.setState(PdfObject.free);
        _xref.add(ref);
      }
    }
    _tokens.nextValidToken();
    final sectionTrailer = await _readDictionary();
    if (_trailer == null) {
      _trailer = sectionTrailer;
    } else {
      // Merge properties from older trailers that don't exist in the main one
      await _trailer!.mergeDifferent(sectionTrailer);
    }

    final prev = await sectionTrailer.integerEntry(PdfName.prev);
    if (prev != null) {
      await _readXrefSection(prev);
    }
  }

  /// Version with cycle detection for following Prev pointers
  Future<void> _readXrefTableWithCycleCheck(Set<int> visitedPositions) async {
    while (true) {
      if (!_tokens.nextToken()) {
        throw PdfException(KernelExceptionMessageConstant.unexpectedEndOfFile);
      }
      if (_tokens.getTokenType() == TokenType.other &&
          _tokens.tokenValueEqualsTo(PdfTokenizer.trailer)) {
        break;
      }
      if (_tokens.getTokenType() != TokenType.number) {
        throw PdfException(KernelExceptionMessageConstant
            .objectNumberOfTheFirstObjectInThisXrefSubsectionNotFound);
      }
      final firstObj = _tokens.getIntValue();
      if (!_tokens.nextToken() || _tokens.getTokenType() != TokenType.number) {
        throw PdfException(KernelExceptionMessageConstant
            .numberOfEntriesInThisXrefSubsectionNotFound);
      }
      final numEntries = _tokens.getIntValue();
      for (var i = 0; i < numEntries; i++) {
        final objNr = firstObj + i;
        _tokens.nextToken();
        final offset = _tokens.getIntValue();
        _tokens.nextToken();
        final gen = _tokens.getIntValue();
        _tokens.nextToken();
        final entryType = _tokens.getStringValue();
        final existing = _xref.get(objNr);
        if (existing != null &&
            (existing.getOffset() > 0 ||
                existing.getObjStreamNumber() > 0 ||
                existing.isFree())) {
          continue;
        }
        final ref = PdfIndirectReference(objNr, gen);
        ref.setReader(this);
        ref.setOffset(offset);
        if (entryType == 'f') ref.setState(PdfObject.free);
        _xref.add(ref);
      }
    }
    _tokens.nextValidToken();
    final sectionTrailer = await _readDictionary();
    if (_trailer == null) {
      _trailer = sectionTrailer;
    } else {
      await _trailer!.mergeDifferent(sectionTrailer);
    }
    final prev = await sectionTrailer.integerEntry(PdfName.prev);
    if (prev != null) {
      await _readXrefSectionWithCycleCheck(prev, visitedPositions);
    }
  }

  Future<void> _readXrefStream() async {
    _tokens.nextValidToken();
    _tokens.nextValidToken();
    final streamDict = await _readDictionary();
    if (_trailer == null) {
      _trailer = streamDict;
    } else {
      await _trailer!.mergeDifferent(streamDict);
    }
    final size = await streamDict.integerEntry(PdfName.size);
    final wArray = await streamDict.arrayEntry(PdfName.w);
    final w1 = (await wArray!.numberEntry(0))?.intValue() ?? 0;
    final w2 = (await wArray.numberEntry(1))?.intValue() ?? 0;
    final w3 = (await wArray.numberEntry(2))?.intValue() ?? 0;
    final indexArrayObj = await streamDict.arrayEntry(PdfName.index);
    List<int> xrefIndex =
        indexArrayObj != null ? await indexArrayObj.toIntArray() : [0, size!];

    final streamLength = await streamDict.integerEntry(PdfName.length);
    _tokens.nextValidToken();
    var ch = _tokens.read();
    if (ch == 0x0D) {
      ch = _tokens.read();
      if (ch != 0x0A) _tokens.backOnePosition(ch);
    } else if (ch != 0x0A) {
      _tokens.backOnePosition(ch);
    }
    if (streamLength == null ||
        streamLength < 0 ||
        streamLength > _tokens.getSafeFile().length() - _tokens.getPosition()) {
      throw FormatException(
          'Cross-reference stream length exceeds the available PDF data.');
    }
    final rawBytes = Uint8List(streamLength);
    _tokens.readFully(rawBytes);
    final decodedBytes = await FilterHandlers.decodeBytes(rawBytes, streamDict);
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
            (existing.getOffset() > 0 ||
                existing.getObjStreamNumber() > 0 ||
                existing.isFree())) {
          continue;
        }
        final ref = PdfIndirectReference(objNum);
        ref.setReader(this);
        switch (type) {
          case 0:
            ref.setState(PdfObject.free);
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
    final prev = await streamDict.integerEntry(PdfName.prev);
    if (prev != null) {
      _validateXrefPosition(prev);
      _tokens.seek(prev);
      await _readXrefSection();
    }
  }

  /// Version with cycle detection for following Prev pointers in xref streams
  Future<void> _readXrefStreamWithCycleCheck(Set<int> visitedPositions) async {
    _tokens.nextValidToken();
    _tokens.nextValidToken();
    final streamDict = await _readDictionary();
    if (_trailer == null) {
      _trailer = streamDict;
    } else {
      await _trailer!.mergeDifferent(streamDict);
    }
    final size = await streamDict.integerEntry(PdfName.size);
    final wArray = await streamDict.arrayEntry(PdfName.w);
    final w1 = (await wArray!.numberEntry(0))?.intValue() ?? 0;
    final w2 = (await wArray.numberEntry(1))?.intValue() ?? 0;
    final w3 = (await wArray.numberEntry(2))?.intValue() ?? 0;

    final indexArrayObj = await streamDict.arrayEntry(PdfName.index);
    List<int> xrefIndex =
        indexArrayObj != null ? await indexArrayObj.toIntArray() : [0, size!];

    final streamLength = await streamDict.integerEntry(PdfName.length);
    _tokens.nextValidToken();
    var ch = _tokens.read();
    if (ch == 0x0D) {
      ch = _tokens.read();
      if (ch != 0x0A) _tokens.backOnePosition(ch);
    } else if (ch != 0x0A) {
      _tokens.backOnePosition(ch);
    }
    if (streamLength == null ||
        streamLength < 0 ||
        streamLength > _tokens.getSafeFile().length() - _tokens.getPosition()) {
      throw FormatException(
          'Cross-reference stream length exceeds the available PDF data.');
    }
    final rawBytes = Uint8List(streamLength);
    _tokens.readFully(rawBytes);
    final decodedBytes = await FilterHandlers.decodeBytes(rawBytes, streamDict);
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
            (existing.getOffset() > 0 ||
                existing.getObjStreamNumber() > 0 ||
                existing.isFree())) {
          continue;
        }
        final ref = PdfIndirectReference(objNum);
        ref.setReader(this);
        switch (type) {
          case 0:
            ref.setState(PdfObject.free);
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
    final prev = await streamDict.integerEntry(PdfName.prev);
    if (prev != null) {
      await _readXrefSectionWithCycleCheck(prev, visitedPositions);
    }
  }

  int _readXrefStreamField(Uint8List data, int offset, int width) {
    if (width == 0) return 0;
    var result = 0;
    for (var i = 0; i < width; i++) {
      result = (result << 8) | data[offset + i];
    }
    return result;
  }

  Future<void> _checkEncryption() async {
    if (_trailer == null) return;
    final encrypt = await _trailer!.get(PdfName.encrypt, true);
    if (encrypt != null && encrypt is! PdfNull) {
      _encrypted = true;
      if (encrypt is PdfDictionary) {
        final idArray = await _trailer!.arrayEntry(PdfName.id);
        Uint8List? documentId;
        if (idArray != null && idArray.size() > 0) {
          final idStr = await idArray.stringEntry(0);
          documentId = idStr?.getValueBytes();
        }

        final password = properties.password ?? Uint8List(0);

        _encryption = await PdfEncryption.createFromDictionary(
            encrypt, password, documentId ?? Uint8List(0));
      }
    }
  }

  Future<PdfDictionary> _readDictionary({PdfTokenizer? tokenizer}) async {
    final tokens = tokenizer ?? _tokens;
    final dict = PdfDictionary();
    while (true) {
      tokens.nextValidToken();
      if (tokens.getTokenType() == TokenType.endDic) break;
      if (tokens.getTokenType() != TokenType.name) {
        throw FormatException(
            'PDF dictionary requires a name key and a closing delimiter.');
      }
      final key = PdfName.fromBytes(tokens.getByteContent());
      tokens.nextValidToken();
      dict.put(key, await _readObject(tokenizer: tokens));
    }
    return dict;
  }

  Future<PdfArray> _readArray({PdfTokenizer? tokenizer}) async {
    final tokens = tokenizer ?? _tokens;
    final arr = PdfArray();
    while (true) {
      tokens.nextValidToken();
      if (tokens.getTokenType() == TokenType.endArray) break;
      if (tokens.getTokenType() == TokenType.endOfFile) {
        throw FormatException('PDF array has no closing delimiter.');
      }
      arr.add(await _readObject(tokenizer: tokens));
    }
    return arr;
  }

  Future<PdfObject> _readObject({PdfTokenizer? tokenizer}) async {
    if (_objectDepth >= 128) {
      throw FormatException('PDF object nesting exceeds the supported depth.');
    }
    _objectDepth++;
    try {
      return await _readObjectValue(tokenizer: tokenizer);
    } finally {
      _objectDepth--;
    }
  }

  Future<PdfObject> _readObjectValue({PdfTokenizer? tokenizer}) async {
    final tokens = tokenizer ?? _tokens;
    switch (tokens.getTokenType()) {
      case TokenType.startDic:
        final dict = await _readDictionary(tokenizer: tokens);
        final pos = tokens.getPosition();
        if (tokens.nextToken() &&
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
        return PdfNumber.fromBytes(tokens.getByteContent());
      case TokenType.string:
        return PdfString.fromBytes(
            tokens.getDecodedStringContent(), tokens.isHexString());
      case TokenType.name:
        return PdfName.fromBytes(tokens.getByteContent());
      case TokenType.ref:
        final objNr = tokens.getObjNr();
        if (objNr < 0 ||
            (_recovering && objNr > properties.recoveryObjectLimit)) {
          throw FormatException(
              'PDF reference identifier exceeds recovery limits.');
        }
        var ref = _xref.get(objNr);
        if (ref != null &&
            (ref.isFree() || ref.generationNumber() != tokens.getGenNr())) {
          _logger.logWarning(IoLogMessageConstant.invalidIndirectReference
              .replaceAll("{0}", objNr.toString())
              .replaceAll("{1}", tokens.getGenNr().toString()));
          return PdfNull();
        }
        if (ref == null) {
          ref = PdfIndirectReference(objNr, tokens.getGenNr());
          _xref.add(ref);
        }
        ref.setDocument(document);
        ref.setReader(this);
        return ref;
      case TokenType.other:
        final v = tokens.getStringValue();
        if (v == 'null') return PdfNull();
        if (v == 'true') return PdfBoolean(true);
        if (v == 'false') return PdfBoolean(false);
        return PdfNull();
      default:
        return PdfNull();
    }
  }

  Future<PdfStream> _readStream(PdfDictionary dict,
      {PdfTokenizer? tokenizer}) async {
    final tokens = tokenizer ?? _tokens;
    var ch = tokens.read();
    if (ch == 0x0D) {
      ch = tokens.read();
      if (ch != 0x0A) tokens.backOnePosition(ch);
    } else if (ch != 0x0A) {
      tokens.backOnePosition(ch);
    }

    final dataPosition = tokens.getPosition();
    final repairedLength = identical(tokens, _tokens)
        ? _recoveredStreamLengths[dataPosition]
        : null;
    final length =
        repairedLength ?? (await dict.numberEntry(PdfName.length))?.intValue();
    if (length == null) throw PdfException('Stream length not found');
    if (length < 0 || length > tokens.getSafeFile().length() - dataPosition) {
      throw FormatException('Stream length exceeds the available PDF data.');
    }
    if (repairedLength != null) {
      dict.put(PdfName.length, PdfNumber(length.toDouble()));
    }
    tokens.seek(dataPosition);

    final bytes = Uint8List(length);
    tokens.readFully(bytes);

    tokens.nextValidToken();
    if (!tokens.tokenValueEqualsTo(PdfTokenizer.endStream)) {
      throw PdfException("Stream did not end with 'endstream'");
    }

    final stream = PdfStream.withBytes(bytes);
    final entries = await dict.entrySet();
    for (final entry in entries) {
      stream.put(entry.key, entry.value);
    }
    return stream;
  }

  Future<PdfObject?> readObject(int objNr) async {
    final ref = _xref.get(objNr);
    if (ref == null || ref.isFree()) return null;

    if (ref.getObjStreamNumber() > 0) {
      final streamRef = _xref.get(ref.getObjStreamNumber());
      if (streamRef != null) {
        final streamObj = await readObject(streamRef.objNr);
        if (streamObj is PdfStream) {
          final object = await _readObjectFromStream(streamObj, ref);
          if (object != null) {
            ref.setDocument(document);
            ref.setReader(this);
            ref.assignTargetObject(object);
            object.setIndirectReference(ref);
          }
          return object;
        }
      }
    }

    if (ref.getOffset() <= 0) return null;
    _validateXrefPosition(ref.getOffset());
    _tokens.seek(ref.getOffset());
    _tokens.nextValidToken();
    if (_tokens.getTokenType() != TokenType.obj ||
        _tokens.getObjNr() != objNr ||
        _tokens.getGenNr() != ref.generationNumber()) {
      throw FormatException(
          'Cross-reference entry does not match its object header.');
    }
    _tokens.nextValidToken();
    final obj = await _readObject();

    // Set indirect reference and document on the returned object
    ref.setDocument(document);
    ref.setReader(this);
    ref.assignTargetObject(obj);
    obj.setIndirectReference(ref);

    return obj;
  }

  Future<PdfObject?> _readObjectFromStream(
      PdfStream stream, PdfIndirectReference ref) async {
    final bytes = await stream.getBytes();
    if (bytes == null) return null;

    final firstObj = await stream.numberEntry(PdfName.first);
    final nObj = await stream.numberEntry(PdfName.n);
    final first = firstObj?.intValue() ?? 0;
    final n = nObj?.intValue() ?? 0;

    final tokenizer = PdfTokenizer(RandomAccessFileOrArray(bytes));

    int objOffset = -1;
    for (int k = 0; k < n; k++) {
      tokenizer.nextValidToken();
      final objNum = tokenizer.getIntValue();
      tokenizer.nextValidToken();
      final off = tokenizer.getIntValue();

      if (objNum == ref.objNr) {
        objOffset = off;
        break;
      }
    }

    if (objOffset == -1) return null;

    tokenizer.seek(first + objOffset);
    tokenizer.nextValidToken();

    return await _readObject(tokenizer: tokenizer);
  }

  Future<PdfDictionary?> rootCatalog() async {
    final rootRef = await _trailer?.get(PdfName.root, false);
    if (rootRef is PdfIndirectReference) {
      final obj = await readObject(rootRef.objectNumber());
      return obj is PdfDictionary ? obj : null;
    }
    return rootRef is PdfDictionary ? rootRef : null;
  }

  Future<PdfDictionary?> getInfo() async {
    final infoRef = await _trailer?.get(PdfName.info, false);
    if (infoRef is PdfIndirectReference) {
      final obj = await readObject(infoRef.objectNumber());
      return obj is PdfDictionary ? obj : null;
    }
    return infoRef is PdfDictionary ? infoRef : null;
  }

  Future<int> pageTotal() async {
    final catalog = await rootCatalog();
    if (catalog == null) return 0;
    final pages = await catalog.dictionaryEntry(PdfName.pages);
    return await pages?.integerEntry(PdfName.count) ?? 0;
  }
}
