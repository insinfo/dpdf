import 'dart:io';
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
import 'pdf_xref_table.dart';
import 'pdf_document.dart';
import 'pdf_version.dart';
import '../utils/filter_handlers.dart';

class PdfReader {
  final PdfTokenizer _tokens;
  PdfDocument? document;
  final PdfXrefTable _xref = PdfXrefTable();
  String? _pdfVersion;
  PdfDictionary? _trailer;
  int _lastXref = 0;
  bool _rebuiltXref = false;
  bool _xrefStm = false;
  bool _encrypted = false;

  PdfReader.fromBytes(Uint8List bytes)
      : _tokens = PdfTokenizer(RandomAccessFileOrArray(bytes));

  static Future<PdfReader> fromFile(String path) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    return PdfReader.fromBytes(bytes);
  }

  void setDocument(PdfDocument doc) {
    document = doc;
  }

  PdfVersion getPdfVersion() {
    return PdfVersion.fromString(_pdfVersion ?? "1.7");
  }

  String? get pdfVersion => _pdfVersion;
  PdfDictionary? get trailer => _trailer;
  PdfDictionary? getTrailer() => _trailer;
  PdfXrefTable get xref => _xref;
  bool get rebuiltXref => _rebuiltXref;
  bool get xrefStm => _xrefStm;
  bool get encrypted => _encrypted;
  int get lastXref => _lastXref;

  Future<void> close() async {
    await _tokens.close();
  }

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
      throw PdfException(
          KernelExceptionMessageConstant.pdfStartxrefIsNotFollowedByANumber);
    }
    _lastXref = _tokens.getIntValue();
    _tokens.seek(_lastXref);
    try {
      await _readXrefSection();
    } catch (e) {
      _rebuiltXref = true;
      throw PdfException('Failed to read xref: $e');
    }
  }

  Future<void> _readXrefSection() async {
    _tokens.seek(_lastXref);
    if (!await _tokens.nextToken()) {
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
      if (!await _tokens.nextToken()) {
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
      if (!await _tokens.nextToken() ||
          _tokens.getTokenType() != TokenType.number) {
        throw PdfException(KernelExceptionMessageConstant
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
        if (_xref.get(objNr) != null) continue;
        final ref = PdfIndirectReference(objNr, gen);
        ref.setOffset(offset);
        if (entryType == 'f') ref.setState(PdfObject.free);
        _xref.add(ref);
      }
    }
    await _tokens.nextValidToken();
    _trailer = await _readDictionary();
    final prev = await _trailer!.getAsInt(PdfName.prev);
    if (prev != null) {
      _tokens.seek(prev);
      await _readXrefSection();
    }
  }

  Future<void> _readXrefStream() async {
    await _tokens.nextValidToken();
    await _tokens.nextValidToken();
    final streamDict = await _readDictionary();
    _trailer = streamDict;
    final size = await streamDict.getAsInt(PdfName.size);
    final wArray = await streamDict.getAsArray(PdfName.w);
    final w1 = (await wArray!.getAsNumber(0))?.intValue() ?? 0;
    final w2 = (await wArray.getAsNumber(1))?.intValue() ?? 0;
    final w3 = (await wArray.getAsNumber(2))?.intValue() ?? 0;
    final indexArrayObj = await streamDict.getAsArray(PdfName.index);
    List<int> xrefIndex =
        indexArrayObj != null ? await indexArrayObj.toIntArray() : [0, size!];

    final streamLength = await streamDict.getAsInt(PdfName.length);
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
        if (_xref.get(objNum) != null) continue;
        final ref = PdfIndirectReference(objNum);
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
    final prev = await streamDict.getAsInt(PdfName.prev);
    if (prev != null) {
      _tokens.seek(prev);
      await _readXrefSection();
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
    final encrypt = await _trailer!.get(PdfName.encrypt, true);
    _encrypted = encrypt != null && encrypt is! PdfNull;
  }

  Future<PdfDictionary> _readDictionary() async {
    final dict = PdfDictionary();
    while (true) {
      await _tokens.nextValidToken();
      if (_tokens.getTokenType() == TokenType.endDic) break;
      final key = PdfName(_tokens.getStringValue());
      await _tokens.nextValidToken();
      dict.put(key, await _readObject());
    }
    return dict;
  }

  Future<PdfArray> _readArray() async {
    final arr = PdfArray();
    while (true) {
      await _tokens.nextValidToken();
      if (_tokens.getTokenType() == TokenType.endArray) break;
      arr.add(await _readObject());
    }
    return arr;
  }

  Future<PdfObject> _readObject() async {
    switch (_tokens.getTokenType()) {
      case TokenType.startDic:
        return await _readDictionary();
      case TokenType.startArray:
        return await _readArray();
      case TokenType.number:
        return PdfNumber.fromBytes(_tokens.getByteContent());
      case TokenType.string:
        return PdfString.fromBytes(
            _tokens.getDecodedStringContent(), _tokens.isHexString());
      case TokenType.name:
        return PdfName(_tokens.getStringValue());
      case TokenType.ref:
        final objNr = _tokens.getObjNr();
        var ref = _xref.get(objNr);
        if (ref == null) {
          ref = PdfIndirectReference(objNr, _tokens.getGenNr());
          _xref.add(ref);
        }
        ref.setDocument(document);
        ref.setReader(this);
        return ref;
      case TokenType.other:
        final v = _tokens.getStringValue();
        if (v == 'null') return PdfNull();
        if (v == 'true') return PdfBoolean(true);
        if (v == 'false') return PdfBoolean(false);
        return PdfNull();
      default:
        return PdfNull();
    }
  }

  Future<PdfObject?> readObject(int objNr) async {
    final ref = _xref.get(objNr);
    if (ref == null || ref.isFree()) return null;
    _tokens.seek(ref.getOffset());
    await _tokens.nextValidToken();
    await _tokens.nextValidToken();
    return await _readObject();
  }

  Future<PdfDictionary?> getCatalog() async {
    final rootRef = await _trailer?.get(PdfName.root, false);
    if (rootRef is PdfIndirectReference) {
      final obj = await readObject(rootRef.getObjNumber());
      return obj is PdfDictionary ? obj : null;
    }
    return rootRef is PdfDictionary ? rootRef : null;
  }

  Future<PdfDictionary?> getInfo() async {
    final infoRef = await _trailer?.get(PdfName.info, false);
    if (infoRef is PdfIndirectReference) {
      final obj = await readObject(infoRef.getObjNumber());
      return obj is PdfDictionary ? obj : null;
    }
    return infoRef is PdfDictionary ? infoRef : null;
  }

  Future<int> getNumberOfPages() async {
    final catalog = await getCatalog();
    if (catalog == null) return 0;
    final pages = await catalog.getAsDictionary(PdfName.pages);
    return await pages?.getAsInt(PdfName.count) ?? 0;
  }
}
