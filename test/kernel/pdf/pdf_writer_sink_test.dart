import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:test/test.dart';

void main() {
  test('o coletor em memória do escritor implementa a codificação de IOSink',
      () {
    final bytes = BytesBuilder(copy: false);
    final sink = CraftPdfWriter.fromBytesBuilder(bytes).getSink();

    expect(sink.encoding, latin1);

    sink.encoding = utf8;
    sink.write('ação');

    expect(bytes.toBytes(), utf8.encode('ação'));
  });
}
