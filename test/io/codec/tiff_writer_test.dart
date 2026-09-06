import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:pdfcraft/src/io/codec/tiff_writer.dart';

void main() {
  group('TiffWriter', () {
    test('writes TIFF header correctly', () {
      final writer = CraftTiffWriter();
      writer.addField(FieldShort(256, 100)); // ImageWidth
      writer.addField(FieldShort(257, 80)); // ImageHeight

      final output = BytesBuilder();
      writer.writeFile(output);

      final bytes = output.toBytes();

      // Check header
      expect(bytes[0], equals(0x4d)); // M
      expect(bytes[1], equals(0x4d)); // M
      expect(bytes[2], equals(0));
      expect(bytes[3], equals(42)); // Magic
    });

    test('FieldShort encodes correctly', () {
      final field = FieldShort(256, 0x1234);
      expect(field.tag, equals(256));
      expect(field.data[0], equals(0x12));
      expect(field.data[1], equals(0x34));
    });

    test('FieldLong encodes correctly', () {
      final field = FieldLong(273, 0x12345678);
      expect(field.tag, equals(273));
      expect(field.data[0], equals(0x12));
      expect(field.data[1], equals(0x34));
      expect(field.data[2], equals(0x56));
      expect(field.data[3], equals(0x78));
    });

    test('FieldShort.fromList encodes multiple values', () {
      final field = FieldShort.fromList(258, [8, 8, 8]);
      expect(field.count, equals(3));
      expect(field.data.length, equals(6));
    });

    test('FieldAscii includes null terminator', () {
      final field = FieldAscii(305, 'pdfcraft');
      expect(field.count, equals(9)); // 8 ASCII characters + terminator
      expect(field.data.length, equals(9));
      expect(field.data[8], equals(0));
    });

    test('FieldRational encodes numerator/denominator', () {
      final field = FieldRational(282, [72, 1]); // 72/1 dpi
      expect(field.data.length, equals(8));
    });

    test('getIfdSize calculates correctly', () {
      final writer = CraftTiffWriter();
      writer.addField(FieldShort(256, 100));
      writer.addField(FieldShort(257, 80));

      // 6 + (2 fields * 12 bytes each) = 30
      expect(writer.getIfdSize(), equals(30));
    });
  });
}
