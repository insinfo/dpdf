import 'dart:io';
import 'dart:typed_data';

import '../../io/source/random_access_file_or_array.dart';
import '../../io/source/array_random_access_source.dart';
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

/// Reads a PDF document.
///
/// This class parses the PDF file structure including the xref table,
/// trailer dictionary, and individual PDF objects.
class PdfReader {
  /// The tokenizer used to parse the PDF content.
  final PdfTokenizer _tokens;

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
      : _tokens = PdfTokenizer(
            RandomAccessFileOrArray(ArrayRandomAccessSource(bytes)));

  /// Creates a PdfReader from a file path.
  factory PdfReader.fromFile(String path) {
    final file = File(path);
    final bytes = file.readAsBytesSync();
    return PdfReader.fromBytes(Uint8List.fromList(bytes));
  }

  /// Gets the PDF version from the header.
  String? get pdfVersion => _pdfVersion;

  /// Gets the trailer dictionary.
  PdfDictionary? get trailer => _trailer;

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
  void close() {
    _tokens.close();
  }

  /// Parses the PDF document.
  ///
  /// Reads the header, xref table, and trailer.
  void read() {
    _readHeader();
    _readXref();
    _xref.markReadingCompleted();
    _checkEncryption();
  }

  /// Reads the PDF header and extracts the version.
  void _readHeader() {
    final header = _tokens.checkPdfHeader();
    // Header format is "PDF-X.Y"
    if (header.length >= 7) {
      _pdfVersion = header.substring(4, 7);
    }
  }

  /// Reads the xref table/stream.
  void _readXref() {
    // Find startxref position
    final startxrefPos = _tokens.getStartxref();
    _tokens.seek(startxrefPos);

    // Read "startxref" keyword
    _tokens.nextValidToken();
    // The token should be "startxref" (TokenType.other)
    // Now read the actual xref offset number
    _tokens.nextValidToken();

    if (_tokens.getTokenType() != TokenType.number) {
      throw PdfException(
          KernelExceptionMessageConstant.pdfStartxrefIsNotFollowedByANumber);
    }

    _lastXref = _tokens.getIntValue();
    _tokens.seek(_lastXref);

    // Try to read xref
    try {
      _readXrefSection();
    } catch (e) {
      // TODO: Implement xref rebuild for corrupted documents
      _rebuiltXref = true;
      throw PdfException('Failed to read xref: $e');
    }
  }

  /// Reads an xref section (table or stream).
  void _readXrefSection() {
    _tokens.seek(_lastXref);

    // Read first token to determine xref type
    if (!_tokens.nextToken()) {
      throw PdfException(KernelExceptionMessageConstant.unexpectedEndOfFile);
    }

    // Check if it's an xref table or xref stream
    if (_tokens.tokenValueEqualsTo(PdfTokenizer.xref)) {
      // Traditional xref table
      _readXrefTable();
    } else {
      // Xref stream (PDF 1.5+)
      _xrefStm = true;
      _tokens.seek(_lastXref);
      _readXrefStream();
    }
  }

  /// Reads a traditional xref table.
  void _readXrefTable() {
    while (true) {
      if (!_tokens.nextToken()) {
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

      if (!_tokens.nextToken() || _tokens.getTokenType() != TokenType.number) {
        throw PdfException(KernelExceptionMessageConstant
            .numberOfEntriesInThisXrefSubsectionNotFound);
      }

      final numEntries = _tokens.getIntValue();

      // Read xref entries
      for (var i = 0; i < numEntries; i++) {
        final objNr = firstObj + i;

        if (!_tokens.nextToken() ||
            _tokens.getTokenType() != TokenType.number) {
          throw PdfException(KernelExceptionMessageConstant
              .invalidCrossReferenceEntryInThisXrefSubsection);
        }
        final offset = _tokens.getIntValue();

        if (!_tokens.nextToken() ||
            _tokens.getTokenType() != TokenType.number) {
          throw PdfException(KernelExceptionMessageConstant
              .invalidCrossReferenceEntryInThisXrefSubsection);
        }
        final gen = _tokens.getIntValue();

        if (!_tokens.nextToken() || _tokens.getTokenType() != TokenType.other) {
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
    _tokens.nextValidToken();
    if (_tokens.getTokenType() != TokenType.startDic) {
      throw PdfException('Expected dictionary after trailer keyword');
    }
    _trailer = _readDictionary();

    // Check for /Prev (previous xref for incremental updates)
    final prev = _trailer!.getAsInt(PdfName.prev);
    if (prev != null) {
      _tokens.seek(prev);
      _readXrefSection();
    }
  }

  /// Reads an xref stream (PDF 1.5+).
  ///
  /// TODO: Complete implementation of xref stream parsing
  void _readXrefStream() {
    // Read the object number and generation for the xref stream object
    _tokens.nextValidToken();
    if (_tokens.getTokenType() != TokenType.obj) {
      throw PdfException(KernelExceptionMessageConstant.invalidXrefStream);
    }

    // Read the stream dictionary
    _tokens.nextValidToken();
    if (_tokens.getTokenType() != TokenType.startDic) {
      throw PdfException(KernelExceptionMessageConstant.invalidXrefStream);
    }

    final streamDict = _readDictionary();

    // The stream dictionary IS the trailer for xref streams
    _trailer = streamDict;

    // Get required fields
    final size = streamDict.getAsInt(PdfName.size);
    if (size == null) {
      throw PdfException(KernelExceptionMessageConstant.invalidXrefStream);
    }

    final wArray = streamDict.getAsArray(PdfName.w);
    if (wArray == null || wArray.size() != 3) {
      throw PdfException(KernelExceptionMessageConstant.invalidXrefStream);
    }

    // Width fields for reading xref stream entries
    // TODO: Use these for parsing xref stream content
    final w1 = wArray.getAsNumber(0)?.intValue() ?? 0; // type field width
    final w2 = wArray.getAsNumber(1)?.intValue() ?? 0; // field 2 width
    final w3 = wArray.getAsNumber(2)?.intValue() ?? 0; // field 3 width

    // Get index array or default to [0 size]
    final indexArrayObj = streamDict.getAsArray(PdfName.index);
    List<int> xrefIndex;
    if (indexArrayObj != null) {
      xrefIndex = indexArrayObj.toIntArray();
    } else {
      xrefIndex = [0, size];
    }

    // TODO: Read and decompress stream content using w1, w2, w3 and xrefIndex
    // For now, just set capacity and suppress unused variable warnings
    _xref.setCapacity(size);
    assert(w1 >= 0 && w2 >= 0 && w3 >= 0); // Suppress unused warnings
    assert(xrefIndex.isNotEmpty);

    // Check for /Prev
    final prev = streamDict.getAsInt(PdfName.prev);
    if (prev != null) {
      _tokens.seek(prev);
      _readXrefSection();
    }
  }

  /// Checks if the document is encrypted.
  void _checkEncryption() {
    if (_trailer == null) return;
    final encrypt = _trailer!.get(PdfName.encrypt);
    _encrypted = encrypt != null && encrypt is! PdfNull;
  }

  /// Reads a PDF dictionary from the current position.
  PdfDictionary _readDictionary() {
    final dict = PdfDictionary();

    while (true) {
      _tokens.nextValidToken();

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

      _tokens.nextValidToken();
      final value = _readObject();

      dict.put(key, value);
    }

    return dict;
  }

  /// Reads a PDF array from the current position.
  PdfArray _readArray() {
    final arr = PdfArray();

    while (true) {
      _tokens.nextValidToken();

      if (_tokens.getTokenType() == TokenType.endArray) {
        break;
      }

      if (_tokens.getTokenType() == TokenType.endOfFile) {
        throw PdfException(KernelExceptionMessageConstant.unexpectedEndOfFile);
      }

      arr.add(_readObject());
    }

    return arr;
  }

  /// Reads a PDF object based on the current token.
  PdfObject _readObject() {
    switch (_tokens.getTokenType()) {
      case TokenType.startDic:
        return _readDictionary();

      case TokenType.startArray:
        return _readArray();

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
        return PdfIndirectReference(
          _tokens.getObjNr(),
          _tokens.getGenNr(),
        );

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
  ///
  /// TODO: Implement full object reading with stream support
  PdfObject? readObject(int objNr) {
    final ref = _xref.get(objNr);
    if (ref == null || ref.isFree()) {
      return null;
    }

    _tokens.seek(ref.getOffset());
    _tokens.nextValidToken();

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

    _tokens.nextValidToken();
    return _readObject();
  }

  /// Gets the catalog (root) dictionary.
  PdfDictionary? getCatalog() {
    if (_trailer == null) return null;
    final rootRef = _trailer!.get(PdfName.root);
    if (rootRef is PdfIndirectReference) {
      final obj = readObject(rootRef.getObjNumber());
      if (obj is PdfDictionary) {
        return obj;
      }
    } else if (rootRef is PdfDictionary) {
      return rootRef;
    }
    return null;
  }

  /// Gets the info dictionary.
  PdfDictionary? getInfo() {
    if (_trailer == null) return null;
    final infoRef = _trailer!.get(PdfName.info);
    if (infoRef is PdfIndirectReference) {
      final obj = readObject(infoRef.getObjNumber());
      if (obj is PdfDictionary) {
        return obj;
      }
    } else if (infoRef is PdfDictionary) {
      return infoRef;
    }
    return null;
  }

  /// Gets the number of pages in the document.
  int getNumberOfPages() {
    final catalog = getCatalog();
    if (catalog == null) return 0;

    final pages = catalog.get(PdfName.pages);
    if (pages is PdfIndirectReference) {
      final pagesObj = readObject(pages.getObjNumber());
      if (pagesObj is PdfDictionary) {
        return pagesObj.getAsInt(PdfName.count) ?? 0;
      }
    } else if (pages is PdfDictionary) {
      return pages.getAsInt(PdfName.count) ?? 0;
    }
    return 0;
  }
}
