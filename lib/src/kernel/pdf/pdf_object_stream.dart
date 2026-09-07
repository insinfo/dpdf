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
class CraftPdfObjectStream extends CraftPdfStream {
  /// Max number of objects in object stream.
  static const int maxObjStreamSize = 200;

  /// Current object stream size (number of objects inside).
  late CraftPdfNumber _size;

  /// The first object offset in the stream.
  late CraftPdfNumber _first;

  /// Object-number and offset entries preceding the object stream body.
  late CraftPdfOutputStream _indexStream;
  late BytesBuilder _indexBuilder;

  CraftPdfObjectStream(CraftPdfDocument doc) : super() {
    _size = CraftPdfNumber(0);
    _first = CraftPdfNumber(0);
    _indexBuilder = BytesBuilder();
    _indexStream = CraftPdfOutputStream.fromBuilder(_indexBuilder);
    _init(doc);
  }

  /// Constructs an object stream with reusable index and output buffers.
  CraftPdfObjectStream.reuse(CraftPdfObjectStream prev) : super() {
    final doc = prev.indirectHandle()!.getDocument()!;
    _size = CraftPdfNumber(0);
    _first = CraftPdfNumber(0);

    _indexBuilder = BytesBuilder();
    _indexStream = CraftPdfOutputStream.fromBuilder(_indexBuilder);

    _init(doc);
    prev.releaseContent();
  }

  void _init(CraftPdfDocument doc) {
    // Allocate a fresh handle instead of recycling an earlier reference.
    attachToDocument(doc);

    // getOutputStream() initializes _bytesBuilder and _outputStream in PdfStream
    final os = getOutputStream();
    os.document = doc;

    put(CraftPdfName.type, CraftPdfName.objStm);
    put(CraftPdfName.n, _size);
    put(CraftPdfName.first, _first);
  }

  /// Adds object to the object stream.
  Future<void> addObject(CraftPdfObject object) async {
    if (_size.intValue() == maxObjStreamSize) {
      throw CraftPdfException(
          CraftKernelExceptionMessageConstant.pdfObjectStreamReachMaxSize);
    }

    final outputStream = getOutputStream();
    final ref = object.indirectHandle();
    if (ref == null) {
      throw CraftPdfException(
          "Object must be indirect to be added to object stream");
    }

    _indexStream.writeInteger(ref.objectNumber());
    _indexStream.writeSpace();
    _indexStream.writeLong(outputStream.getCurrentPos());
    _indexStream.writeSpace();

    await outputStream.writePdfObject(object, forceDirect: true);

    ref.setObjStreamNumber(indirectHandle()!.objectNumber());
    ref.setIndex(_size.intValue());

    outputStream.writeSpace();
    _size.increment();

    _first.setValue(_indexStream.getCurrentPos().toDouble());
  }

  /// Gets object stream size (number of objects inside).
  int getSize() => _size.intValue();

  CraftPdfOutputStream getIndexStream() => _indexStream;
}
