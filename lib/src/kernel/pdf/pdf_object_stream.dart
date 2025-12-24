import 'dart:typed_data';

import 'package:dpdf/src/kernel/exceptions/kernel_exception_message_constant.dart';
import 'package:dpdf/src/kernel/exceptions/pdf_exception.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_output_stream.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';

/// internal class PdfObjectStream : PdfStream
class PdfObjectStream extends PdfStream {
  /// Max number of objects in object stream.
  static const int maxObjStreamSize = 200;

  /// Current object stream size (number of objects inside).
  late PdfNumber _size;

  /// The first object offset in the stream.
  late PdfNumber _first;

  /// Stream containing object indices, a heading part of object stream.
  late PdfOutputStream _indexStream;
  late BytesBuilder _indexBuilder;

  PdfObjectStream(PdfDocument doc) : super() {
    _size = PdfNumber(0);
    _first = PdfNumber(0);
    _indexBuilder = BytesBuilder();
    _indexStream = PdfOutputStream.fromBuilder(_indexBuilder);
    _init(doc);
  }

  /// This constructor is for reusing ByteArrayOutputStreams of indexStream and outputStream.
  PdfObjectStream.reuse(PdfObjectStream prev) : super() {
    final doc = prev.getIndirectReference()!.getDocument()!;
    _size = PdfNumber(0);
    _first = PdfNumber(0);

    _indexBuilder = BytesBuilder();
    _indexStream = PdfOutputStream.fromBuilder(_indexBuilder);

    _init(doc);
    prev.releaseContent();
  }

  void _init(PdfDocument doc) {
    // avoid reuse existed references, create new, opposite to get next reference
    makeIndirect(doc);

    // getOutputStream() initializes _bytesBuilder and _outputStream in PdfStream
    final os = getOutputStream();
    os.document = doc;

    put(PdfName.type, PdfName.objStm);
    put(PdfName.n, _size);
    put(PdfName.first, _first);
  }

  /// Adds object to the object stream.
  Future<void> addObject(PdfObject object) async {
    if (_size.intValue() == maxObjStreamSize) {
      throw PdfException(
          KernelExceptionMessageConstant.pdfObjectStreamReachMaxSize);
    }

    final outputStream = getOutputStream();
    final ref = object.getIndirectReference();
    if (ref == null) {
      throw PdfException(
          "Object must be indirect to be added to object stream");
    }

    _indexStream.writeInteger(ref.getObjNumber());
    _indexStream.writeSpace();
    _indexStream.writeLong(outputStream.getCurrentPos());
    _indexStream.writeSpace();

    await outputStream.writePdfObject(object);

    ref.setObjStreamNumber(getIndirectReference()!.getObjNumber());
    ref.setIndex(_size.intValue());

    outputStream.writeSpace();
    _size.increment();

    _first.setValue(_indexStream.getCurrentPos().toDouble());
  }

  /// Gets object stream size (number of objects inside).
  int getSize() => _size.intValue();

  PdfOutputStream getIndexStream() => _indexStream;

  @override
  void releaseContent() {
    super.releaseContent();
  }
}
