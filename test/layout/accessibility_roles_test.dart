import 'dart:io';

import 'package:test/test.dart';
import 'package:dpdf/src/io/image/image_data_factory.dart';
import 'package:dpdf/src/layout/element/cell.dart';
import 'package:dpdf/src/layout/element/div.dart';
import 'package:dpdf/src/layout/element/image.dart';
import 'package:dpdf/src/layout/element/list.dart' as elements;
import 'package:dpdf/src/layout/element/list_item.dart';
import 'package:dpdf/src/layout/element/paragraph.dart';
import 'package:dpdf/src/layout/element/table.dart';
import 'package:dpdf/src/layout/properties/property.dart';
import 'package:dpdf/src/layout/properties/unit_value.dart';
import 'package:dpdf/src/layout/tagging/default_accessibility_properties.dart';

void main() {
  group('Standard structure types of layout elements (ISO 32000-1, 14.8.4)',
      () {
    test('block elements carry their standard role', () {
      expect(Div().getAccessibilityProperties().getRole(), 'Div');
      expect(Paragraph().getAccessibilityProperties().getRole(), 'P');
      expect(Cell().getAccessibilityProperties().getRole(), 'TD');
      expect(
          Table([UnitValue.createPointValue(10)])
              .getAccessibilityProperties()
              .getRole(),
          'Table');
      expect(elements.PdfList().getAccessibilityProperties().getRole(), 'L');
      expect(ListItem().getAccessibilityProperties().getRole(), 'LI');
    });

    test('a header cell is tagged TH', () {
      final cell = Cell()..isHeader = true;
      expect(cell.getAccessibilityProperties().getRole(), 'TH');
    });

    test('the properties object is stable across calls', () {
      final div = Div();
      final first = div.getAccessibilityProperties();
      first.setRole('Sect');
      expect(div.getAccessibilityProperties().getRole(), 'Sect');
      expect(identical(div.getAccessibilityProperties(), first), isTrue);
    });

    test('an image is a Figure and accepts an alternate description', () {
      final path = r'test/assets/shapes-rgb.jpg';
      if (!File(path).existsSync()) {
        markTestSkipped('Test image not found at $path');
        return;
      }
      final image =
          Image(ImageDataFactory.create(File(path).readAsBytesSync()));
      expect(image.getAccessibilityProperties().getRole(), 'Figure');
      image.setAlternateDescription('Deserto');
      expect(image.getAccessibilityProperties().getAlternateDescription(),
          'Deserto');
    });

    test('default properties can be built with any role', () {
      final properties = DefaultAccessibilityProperties('Formula');
      expect(properties.getRole(), 'Formula');
      properties.setLanguage('pt-BR');
      expect(properties.getLanguage(), 'pt-BR');
    });
  });

  group('List item symbols', () {
    test('a string symbol becomes a text symbol', () {
      final item = ListItem()..setListSymbol('-> ');
      expect(item.getProperty(Property.LIST_SYMBOL), isNotNull);
    });

    test('an image can be used as the bullet of a single item', () {
      final path = r'test/assets/shapes-rgb.jpg';
      if (!File(path).existsSync()) {
        markTestSkipped('Test image not found at $path');
        return;
      }
      final image = Image(ImageDataFactory.create(File(path).readAsBytesSync()))
          .setWidth(8)
          .setHeight(8);
      final item = ListItem('texto')..setListSymbol(image);
      expect(item.getProperty<Image>(Property.LIST_SYMBOL), same(image));
    });

    test('an unsupported symbol is rejected', () {
      expect(() => ListItem().setListSymbol(42), throwsArgumentError);
    });
  });
}
