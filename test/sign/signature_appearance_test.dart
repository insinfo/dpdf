import 'package:dpdf/src/kernel/colors/device_rgb.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/sign/signature_field_appearance.dart';
import 'package:dpdf/src/sign/signer_properties.dart';
import 'package:dpdf/src/sign/simple_signature_appearance.dart';
import 'package:test/test.dart';

void main() {
  group('SignatureFieldAppearance', () {
    test('a fresh signer carries a description only appearance', () {
      final appearance = SignerProperties().getSignatureAppearance();
      expect(appearance.getMode(), SignatureAppearanceMode.description);
      expect(appearance.getContentLines(), isEmpty);
      expect(appearance.isRenderingSignerProperties(), isTrue);
    });

    test('naming the signer switches the composition mode', () {
      final appearance = SignatureFieldAppearance()..setSignerName('Isaque');
      expect(appearance.getMode(), SignatureAppearanceMode.nameAndDescription);
      expect(appearance.getSignerName(), 'Isaque');
    });

    test('invalid metrics are rejected', () {
      final appearance = SignatureFieldAppearance();
      expect(() => appearance.setFontSize(0), throwsArgumentError);
      expect(() => appearance.setMargin(-1), throwsArgumentError);
      expect(() => appearance.setBorderWidth(-0.5), throwsArgumentError);
      expect(appearance.setFontSize(8).getFontSize(), 8);
      expect(appearance.setMargin(2).getMargin(), 2);
      expect(appearance.setBorderWidth(0).getBorderWidth(), 0);
    });

    test('colors round trip', () {
      final appearance = SignatureFieldAppearance()
        ..setTextColor(DeviceRgb(1, 0, 0))
        ..setBorderColor(DeviceRgb(0, 1, 0))
        ..setBackgroundColor(DeviceRgb(0, 0, 1));
      expect(appearance.getTextColor(), isA<DeviceRgb>());
      expect(appearance.getBorderColor(), isA<DeviceRgb>());
      expect(appearance.getBackgroundColor(), isA<DeviceRgb>());
    });
  });

  group('SimpleSignatureAppearance line composition', () {
    test('the signer properties become the trailing lines', () {
      final properties = SignerProperties()
        ..setReason('Aprovacao')
        ..setLocation('Brasil')
        ..setContact('suporte@example.org')
        ..setClaimedSignDate(DateTime.utc(2026, 3, 14))
        ..setPageRect(Rectangle(0, 0, 200, 80));
      final lines = SimpleSignatureAppearance(properties).composeLines();
      expect(lines, [
        'Reason: Aprovacao',
        'Location: Brasil',
        'Contact: suporte@example.org',
        'Date: 2026-03-14',
      ]);
    });

    test('the signer name and the declared content come first', () {
      final properties = SignerProperties()
        ..setClaimedSignDate(DateTime.utc(2026, 3, 14))
        ..setSignatureAppearance(SignatureFieldAppearance()
          ..setSignerName('Isaque')
          ..setContent(['Documento conferido']));
      final lines = SimpleSignatureAppearance(properties).composeLines();
      expect(lines,
          ['Isaque', 'Documento conferido', 'Date: 2026-03-14']);
    });

    test('signer property lines can be switched off', () {
      final properties = SignerProperties()
        ..setReason('Aprovacao')
        ..setSignatureAppearance(SignatureFieldAppearance()
          ..setRenderSignerProperties(false)
          ..addContentLine('somente isto'));
      expect(SimpleSignatureAppearance(properties).composeLines(),
          ['somente isto']);
    });

    test('the empty mode paints nothing', () {
      final properties = SignerProperties()
        ..setReason('Aprovacao')
        ..setSignatureAppearance(SignatureFieldAppearance()
          ..setSignerName('Isaque')
          ..setMode(SignatureAppearanceMode.empty));
      expect(SimpleSignatureAppearance(properties).composeLines(), isEmpty);
    });
  });
}
