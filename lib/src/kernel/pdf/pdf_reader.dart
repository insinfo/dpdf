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
import '../utils/filter_handlers.dart';

/// Reads a PDF document.
///
/// This class parses the PDF file structure including the xref table,
/// trailer dictionary, and individual PDF objects.
class PdfReader {
  /// The tokenizer used to parse the PDF content.
  final PdfTokenizer _tokens;

  PdfDocument? document;

  /// The xref table for this document.
  final PdfXrefTable _xref = PdfXrefTable();

  /// PDF version from header.
  String? _pdfVersion;

  /// The trailer dictionary.
  PdfDictionary? _trailer;

  /// Position of the last xref section.
  int _lastXref = 0;

  /// Whether the xref was rebuilt due to errors.
  bool _rebuiltXref = false;

  /// Whether xref streams are used.
  bool _xrefStm = false;

  /// Whether the document is encrypted.
  bool _encrypted = false;

  /// Creates a PdfReader from file bytes.
  PdfReader.fromBytes(Uint8List bytes)
      : _tokens = PdfTokenizer(RandomAccessFileOrArray(bytes));

  /// Creates a PdfReader from a file path.
  static Future<PdfReader> fromFile(String path) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    return PdfReader.fromBytes(bytes);
  }

  /// Gets the PDF version from the header.
  String? get pdfVersion => _pdfVersion;

  /// Gets the trailer dictionary.
  PdfDictionary? get trailer => _trailer;

  PdfDictionary? getTrailer() => _trailer;

  /// Gets the xref table.
  PdfXrefTable get xref => _xref;

  /// Whether the xref was rebuilt.
  bool get rebuiltXref => _rebuiltXref;

  /// Whether the document uses xref streams.
  bool get xrefStm => _xrefStm;

  /// Whether the document is encrypted.
  bool get encrypted => _encrypted;

  /// Gets the position of the last xref.
  int get lastXref => _lastXref;

  /// Closes the reader.
  Future<void> close() async {
    await _tokens.close();
  }

  /// Parses the PDF document.
  ///
  /// Reads the header, xref table, and trailer.
  Future<void> read() async {
    await _readHeader();
    await _readXref();
    _xref.markReadingCompleted();
    await _checkEncryption();
  }

  /// Reads the PDF header and extracts the version.
  Future<void> _readHeader() async {
    final header = await _tokens.checkPdfHeader();
    // Header format is "PDF-X.Y"
    if (header.length >= 7) {
      _pdfVersion = header.substring(4, 7);
    }
  }

  /// Reads the xref table/stream.
  Future<void> _readXref() async {
    // Find startxref position
    final startxrefPos = await _tokens.getStartxref();
    _tokens.seek(startxrefPos);

    // Read "startxref" keyword
    await _tokens.nextValidToken();
    // The token should be "startxref" (TokenType.other)
    // Now read the actual xref offset number
    await _tokens.nextValidToken();

    if (_tokens.getTokenType() != TokenType.number) {
      throw PdfException(
          KernelExceptionMessageConstant.pdfStartxrefIsNotFollowedByANumber);
    }

    _lastXref = _tokens.getIntValue();
    _tokens.seek(_lastXref);

    // Try to read xref
    try {
      await _readXrefSection();
    } catch (e) {
      // TODO: Implement xref rebuild for corrupted documents
      _rebuiltXref = true;
      throw PdfException('Failed to read xref: $e');
    }
  }

  /// Reads an xref section (table or stream).
  Future<void> _readXrefSection() async {
    _tokens.seek(_lastXref);

    // Read first token to determine xref type
    if (!await _tokens.nextToken()) {
      throw PdfException(KernelExceptionMessageConstant.unexpectedEndOfFile);
    }

    // Check if it's an xref table or xref stream
    if (_tokens.tokenValueEqualsTo(PdfTokenizer.xref)) {
      // Traditional xref table
      await _readXrefTable();
    } else {
      // Xref stream (PDF 1.5+)
      _xrefStm = true;
      _tokens.seek(_lastXref);
      await _readXrefStream();
    }
  }

  /// Reads a traditional xref table.
  Future<void> _readXrefTable() async {
    while (true) {
      if (!await _tokens.nextToken()) {
        throw PdfException(KernelExceptionMessageConstant.unexpectedEndOfFile);
      }

      // Check for "trailer" keyword
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

      // Read xref entries
      for (var i = 0; i < numEntries; i++) {
        final objNr = firstObj + i;

        if (!await _tokens.nextToken() ||
            _tokens.getTokenType() != TokenType.number) {
          throw PdfException(KernelExceptionMessageConstant
              .invalidCrossReferenceEntryInThisXrefSubsection);
        }
        final offset = _tokens.getIntValue();

        if (!await _tokens.nextToken() ||
            _tokens.getTokenType() != TokenType.number) {
          throw PdfException(KernelExceptionMessageConstant
              .invalidCrossReferenceEntryInThisXrefSubsection);
        }
        final gen = _tokens.getIntValue();

        if (!await _tokens.nextToken() ||
            _tokens.getTokenType() != TokenType.other) {
          throw PdfException(KernelExceptionMessageConstant
              .invalidCrossReferenceEntryInThisXrefSubsection);
        }

        final entryType = _tokens.getStringValue();

        // Skip if reference already exists (we want the newest one in incremental updates)
        if (_xref.get(objNr) != null) {
          continue;
        }

        final ref = PdfIndirectReference(objNr, gen);
        ref.setOffset(offset);

        if (entryType == 'f') {
          ref.setState(PdfObject.free);
        }

        _xref.add(ref);
      }
    }

    // Read trailer dictionary
    // After reading "trailer" keyword, need to read the "<<" token
    await _tokens.nextValidToken();
    if (_tokens.getTokenType() != TokenType.startDic) {
      throw PdfException('Expected dictionary after trailer keyword');
    }
    _trailer = await _readDictionary();

    // Check for /Prev (previous xref for incremental updates)
    final prev = await _trailer!.getAsInt(PdfName.prev);
    if (prev != null) {
      _tokens.seek(prev);
      await _readXrefSection();
    }
  }

  /// Reads an xref stream (PDF 1.5+).
  Future<void> _readXrefStream() async {
    // Read the object number and generation for the xref stream object
    await _tokens.nextValidToken();
    if (_tokens.getTokenType() != TokenType.obj) {
      throw PdfException(KernelExceptionMessageConstant.invalidXrefStream);
    }

    // Read the stream dictionary
    await _tokens.nextValidToken();
    if (_tokens.getTokenType() != TokenType.startDic) {
      throw PdfException(KernelExceptionMessageConstant.invalidXrefStream);
    }

    final streamDict = await _readDictionary();

    // The stream dictionary IS the trailer for xref streams
    _trailer = streamDict;

    // Get required fields
    final size = await streamDict.getAsInt(PdfName.size);
    if (size == null) {
      throw PdfException(KernelExceptionMessageConstant.invalidXrefStream);
    }

    final wArray = await streamDict.getAsArray(PdfName.w);
    if (wArray == null || wArray.size() != 3) {
      throw PdfException(KernelExceptionMessageConstant.invalidXrefStream);
    }

    // Width fields for reading xref stream entries
    final w1Num = await wArray.getAsNumber(0);
    final w1 = w1Num?.intValue() ?? 0; // type field width
    final w2Num = await wArray.getAsNumber(1);
    final w2 = w2Num?.intValue() ?? 0; // field 2 width
    final w3Num = await wArray.getAsNumber(2);
    final w3 = w3Num?.intValue() ?? 0; // field 3 width
    final entrySize = w1 + w2 + w3;

    // Get index array or default to [0 size]
    final indexArrayObj = await streamDict.getAsArray(PdfName.index);
    List<int> xrefIndex;
    if (indexArrayObj != null) {
      xrefIndex = await indexArrayObj.toIntArray();
    } else {
      xrefIndex = [0, size];
    }

    // Read stream content
    final streamLength = await streamDict.getAsInt(PdfName.length);
    if (streamLength == null || streamLength <= 0) {
      throw PdfException(KernelExceptionMessageConstant.invalidXrefStream);
    }

    // Skip "stream" keyword and whitespace
    await _tokens.nextValidToken();
    if (!_tokens.tokenValueEqualsTo(PdfTokenizer.stream)) {
      throw PdfException(KernelExceptionMessageConstant.invalidXrefStream);
    }

    // Skip CR/LF after "stream"
    var ch = await _tokens.read();
    if (ch == 0x0D) {
      // CR
      ch = await _tokens.read();
      if (ch != 0x0A) {
        // Not LF, put back
        _tokens.backOnePosition(ch);
      }
    } else if (ch != 0x0A) {
      // Not LF, put back
      _tokens.backOnePosition(ch);
    }

    // Read raw stream bytes
    final rawBytes = Uint8List(streamLength);
    for (var i = 0; i < streamLength; i++) {
      final b = await _tokens.read();
      if (b == -1) break;
      rawBytes[i] = b;
    }

    // Decompress stream using filters
    final decodedBytes = await _decodeStreamBytes(rawBytes, streamDict);

    // Parse xref entries
    _xref.setCapacity(size);
    var byteOffset = 0;

    for (var i = 0; i < xrefIndex.length; i += 2) {
      final first = xrefIndex[i];
      final count = xrefIndex[i + 1];

      for (var j = 0; j < count; j++) {
        if (byteOffset + entrySize > decodedBytes.length) {
          // Not enough data
          break;
        }

        final objNum = first + j;

        // Read type field (default to 1 if w1 == 0)
        final type =
            w1 > 0 ? _readXrefStreamField(decodedBytes, byteOffset, w1) : 1;
        byteOffset += w1;

        // Read field 2
        final field2 = _readXrefStreamField(decodedBytes, byteOffset, w2);
        byteOffset += w2;

        // Read field 3
        final field3 = _readXrefStreamField(decodedBytes, byteOffset, w3);
        byteOffset += w3;

        // Skip if reference already exists (we want newest in incremental updates)
        if (_xref.get(objNum) != null) {
          continue;
        }

        final ref = PdfIndirectReference(objNum);

        switch (type) {
          case 0:
            // Free object
            ref.setState(PdfObject.free);
            ref.setOffset(field2); // Next free object number
            // field3 is generation number
            break;
          case 1:
            // Object in use, not in object stream
            ref.setOffset(field2); // Byte offset
            // field3 is generation number
            break;
          case 2:
            // Object in object stream
            ref.setObjStreamNumber(field2); // Object stream number
            ref.setIndex(field3); // Index in object stream
            break;
          default:
            // Unknown type, treat as free
            ref.setState(PdfObject.free);
            break;
        }

        _xref.add(ref);
      }
    }

    // Check for /Prev
    final prev = await streamDict.getAsInt(PdfName.prev);
    if (prev != null) {
      _tokens.seek(prev);
      await _readXrefSection();
    }
  }

  /// Reads a multi-byte integer from xref stream data.
  int _readXrefStreamField(Uint8List data, int offset, int width) {
    if (width == 0) return 0;
    var result = 0;
    for (var i = 0; i < width; i++) {
      result = (result << 8) | data[offset + i];
    }
    return result;
  }

  /// Decodes stream bytes using filters specified in the dictionary.
  Future<Uint8List> _decodeStreamBytes(
      Uint8List bytes, PdfDictionary streamDict) async {
    return await FilterHandlers.decodeBytes(bytes, streamDict);
  }

  /// Checks if the document is encrypted.
  Future<void> _checkEncryption() async {
    if (_trailer == null) return;
    final encrypt = await _trailer!.get(PdfName.encrypt);
    _encrypted = encrypt != null && encrypt is! PdfNull;
  }

  /// Reads a PDF dictionary from the current position.
  Future<PdfDictionary> _readDictionary() async {
    final dict = PdfDictionary();

    while (true) {
      await _tokens.nextValidToken();

      if (_tokens.getTokenType() == TokenType.endDic) {
        break;
      }

      if (_tokens.getTokenType() == TokenType.endOfFile) {
        throw PdfException(KernelExceptionMessageConstant.unexpectedEndOfFile);
      }

      if (_tokens.getTokenType() != TokenType.name) {
        throw PdfException('Dictionary key must be a name');
      }

      final key = PdfName(_tokens.getStringValue());

      await _tokens.nextValidToken();
      final value = await _readObject();

      dict.put(key, value);
    }

    return dict;
  }

  /// Reads a PDF array from the current position.
  Future<PdfArray> _readArray() async {
    final arr = PdfArray();

    while (true) {
      await _tokens.nextValidToken();

      if (_tokens.getTokenType() == TokenType.endArray) {
        break;
      }

      if (_tokens.getTokenType() == TokenType.endOfFile) {
        throw PdfException(KernelExceptionMessageConstant.unexpectedEndOfFile);
      }

      arr.add(await _readObject());
    }

    return arr;
  }

  /// Reads a PDF object based on the current token.
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
          _tokens.getDecodedStringContent(),
          _tokens.isHexString(),
        );

      case TokenType.name:
        return PdfName(_tokens.getStringValue());

      case TokenType.ref:
        final objNr = _tokens.getObjNr();
        final genNr = _tokens.getGenNr();
        var ref = _xref.get(objNr);
        if (ref == null) {
          ref = PdfIndirectReference(objNr, genNr);
          _xref.add(ref);
        }
        ref.setDocument(document);
        return ref;

      case TokenType.other:
        final value = _tokens.getStringValue();
        if (value == 'null') {
          return PdfNull();
        } else if (value == 'true') {
          return PdfBoolean(true);
        } else if (value == 'false') {
          return PdfBoolean(false);
        }
        // Unknown token, return null
        return PdfNull();

      default:
        return PdfNull();
    }
  }

  /// Reads an object at the given offset.
  Future<PdfObject?> readObject(int objNr) async {
    final ref = _xref.get(objNr);
    if (ref == null || ref.isFree()) {
      return null;
    }

    _tokens.seek(ref.getOffset());
    await _tokens.nextValidToken();

    if (_tokens.getTokenType() != TokenType.obj) {
      throw PdfException.withParams(
        KernelExceptionMessageConstant.invalidOffsetForThisObject,
        [objNr],
      );
    }

    if (_tokens.getObjNr() != objNr) {
      throw PdfException.withParams(
        KernelExceptionMessageConstant.invalidIndirectReference,
        [objNr, ref.getGenNumber()],
      );
    }

    await _tokens.nextValidToken();
    return await _readObject();
  }

  /// Gets the catalog (root) dictionary.
  Future<PdfDictionary?> getCatalog() async {
    if (_trailer == null) return null;
    final rootRef = await _trailer!.get(PdfName.root);
    if (rootRef is PdfIndirectReference) {
      final obj = await readObject(rootRef.getObjNumber());
      if (obj is PdfDictionary) {
        return obj;
      }
    } else if (rootRef is PdfDictionary) {
      return rootRef;
    }
    return null;
  }

  /// Gets the info dictionary.
  Future<PdfDictionary?> getInfo() async {
    if (_trailer == null) return null;
    final infoRef = await _trailer!.get(PdfName.info);
    if (infoRef is PdfIndirectReference) {
      final obj = await readObject(infoRef.getObjNumber());
      if (obj is PdfDictionary) {
        return obj;
      }
    } else if (infoRef is PdfDictionary) {
      return infoRef;
    }
    return null;
  }

  /// Gets the number of pages in the document.
  Future<int> getNumberOfPages() async {
    final catalog = await getCatalog();
    if (catalog == null) return 0;

    final pages = await catalog.get(PdfName.pages);
    if (pages is PdfIndirectReference) {
      final pagesObj = await readObject(pages.getObjNumber());
      if (pagesObj is PdfDictionary) {
        return await pagesObj.getAsInt(PdfName.count) ?? 0;
      }
    } else if (pages is PdfDictionary) {
      return await pages.getAsInt(PdfName.count) ?? 0;
    }
    return 0;
  }
}
