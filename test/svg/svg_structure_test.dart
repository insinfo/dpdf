import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/svg/svg_converter.dart';
import 'package:dpdf/src/svg/utils/svg_conditional_processing.dart';
import 'package:test/test.dart';

/// Draws [svg] on a loose canvas and returns the content stream it produced.
Future<String> _render(String svg, {Rectangle? viewport}) async {
  final stream = PdfStream();
  final canvas = PdfCanvas(stream, null, null);
  await SvgConverter.drawOnCanvas(svg, canvas, viewport: viewport);
  final bytes = await stream.getBytes();
  return String.fromCharCodes(bytes!);
}

int _count(String content, String operator) =>
    operator.allMatches(content).length;

void main() {
  group('SVG symbol and use', () {
    test('a symbol is never painted where it is declared', () async {
      final content = await _render('<svg width="40" height="40">'
          '<symbol id="mark"><rect width="8" height="8"/></symbol></svg>');

      expect(content, isNot(contains(' re\nf\n')));
    });

    test('use instantiates a symbol and sizes its viewport', () async {
      final content = await _render('''
        <svg width="100" height="100">
          <defs>
            <symbol id="mark" viewBox="0 0 10 10">
              <rect width="10" height="10" fill="red"/>
            </symbol>
          </defs>
          <use href="#mark" x="20" y="20" width="40" height="40"/>
        </svg>
      ''');

      expect(content, contains('1 0 0 1 15 15 cm\n'),
          reason: 'x and y of the use become a translation');
      expect(content, contains('0 0 30 30 re\nW\n'),
          reason: 'the generated svg clips to the requested 40px box');
      expect(content, contains('4 0 0 4 0 0 cm\n'),
          reason: '30pt of viewport over 7.5pt of viewBox is a factor of four');
      expect(content, contains('0 0 7.5 7.5 re\n'));
    });

    test('use without width falls back to the full viewport', () async {
      final content = await _render('''
        <svg width="100" height="100">
          <defs><symbol id="mark"><rect width="4" height="4"/></symbol></defs>
          <use href="#mark"/>
        </svg>
      ''');

      expect(content, contains('0 0 75 75 re\nW\n'),
          reason: 'width and height default to 100% of the viewport');
      expect(content, contains('0 0 3 3 re\n'));
    });

    test('use overrides the size of a referenced svg element', () async {
      final content = await _render('''
        <svg width="100" height="100">
          <defs>
            <svg id="inner" width="10" height="10" viewBox="0 0 10 10">
              <rect width="10" height="10"/>
            </svg>
          </defs>
          <use href="#inner" width="40" height="40"/>
        </svg>
      ''');

      expect(content, contains('0 0 30 30 re\nW\n'));
      expect(_count(content, '0 0 7.5 7.5 re\n'), 1,
          reason: 'the definition itself must not leak into the drawing');
    });

    test('use hands its own properties down to the instance', () async {
      final content = await _render('''
        <svg width="40" height="40">
          <defs><rect id="tile" width="4" height="4"/></defs>
          <use href="#tile" fill="#ff0000"/>
        </svg>
      ''');

      expect(content, contains('1 0 0 rg\n'),
          reason: 'the instance inherits fill from the use element');
    });

    test('a property declared on the instance wins over the inherited one',
        () async {
      final content = await _render('''
        <svg width="40" height="40">
          <defs><rect id="tile" width="4" height="4" fill="#00ff00"/></defs>
          <use href="#tile" fill="#ff0000"/>
        </svg>
      ''');

      expect(content, contains('0 1 0 rg\n'));
      expect(content, isNot(contains('1 0 0 rg\n')));
    });
  });

  group('SVG switch', () {
    test('draws only the first child that passes its tests', () async {
      final content = await _render('''
        <svg width="40" height="40">
          <switch>
            <rect requiredExtensions="urn:example" width="4" height="4"/>
            <circle r="2"/>
            <rect width="6" height="6"/>
          </switch>
        </svg>
      ''');

      expect(_count(content, ' c\n'), 4,
          reason: 'the circle is the first branch that passes');
      expect(content, isNot(contains('0 0 4.5 4.5 re\n')),
          reason: 'later branches are skipped even when they would pass');
    });

    test('an unsupported feature string rejects the branch', () async {
      final content = await _render('''
        <svg width="40" height="40">
          <switch>
            <rect requiredFeatures="http://www.w3.org/TR/SVG11/feature#Filter"
                  width="4" height="4"/>
            <rect width="8" height="8"/>
          </switch>
        </svg>
      ''');

      expect(content, contains('0 0 6 6 re\n'));
      expect(content, isNot(contains('0 0 3 3 re\n')));
    });

    test('a supported feature string accepts the branch', () async {
      final content = await _render('''
        <svg width="40" height="40">
          <switch>
            <rect requiredFeatures="http://www.w3.org/TR/SVG11/feature#Shape"
                  width="4" height="4"/>
            <rect width="8" height="8"/>
          </switch>
        </svg>
      ''');

      expect(content, contains('0 0 3 3 re\n'));
      expect(content, isNot(contains('0 0 6 6 re\n')));
    });

    test('systemLanguage selects the branch that matches the user language',
        () async {
      final content = await _render('''
        <svg width="40" height="40">
          <switch>
            <rect systemLanguage="fr,de" width="4" height="4"/>
            <rect systemLanguage="en-GB" width="8" height="8"/>
            <rect width="10" height="10"/>
          </switch>
        </svg>
      ''');

      expect(content, contains('0 0 6 6 re\n'),
          reason: 'en-GB is a prefix match for the default user language');
    });

    test('the configured user language drives systemLanguage', () async {
      SvgConditionalProcessing.setUserLanguage('pt-BR');
      try {
        final content = await _render('''
          <svg width="40" height="40">
            <switch>
              <rect systemLanguage="fr" width="4" height="4"/>
              <rect systemLanguage="pt" width="8" height="8"/>
            </switch>
          </svg>
        ''');

        expect(content, contains('0 0 6 6 re\n'));
      } finally {
        SvgConditionalProcessing.setUserLanguage(null);
      }
    });

    test('nothing is drawn when no branch passes', () async {
      final content = await _render('''
        <svg width="40" height="40">
          <switch>
            <rect systemLanguage="fr" width="4" height="4"/>
            <rect requiredExtensions="urn:example" width="8" height="8"/>
          </switch>
        </svg>
      ''');

      expect(_count(content, ' re\n'), 1,
          reason: 'only the viewport clip of the root svg is left');
    });
  });

  group('SVG conditional attributes outside switch', () {
    test('requiredExtensions hides a plain element', () async {
      final content = await _render('<svg width="40" height="40">'
          '<rect requiredExtensions="urn:example" width="4" height="4"/>'
          '</svg>');

      expect(content, isNot(contains('0 0 3 3 re\n')));
    });

    test('an empty requiredFeatures evaluates to false', () async {
      final content = await _render('<svg width="40" height="40">'
          '<rect requiredFeatures="" width="4" height="4"/></svg>');

      expect(content, isNot(contains('0 0 3 3 re\n')));
    });

    test('a matching systemLanguage keeps the element', () async {
      final content = await _render('<svg width="40" height="40">'
          '<rect systemLanguage="en" width="4" height="4"/></svg>');

      expect(content, contains('0 0 3 3 re\n'));
    });
  });

  group('SVG elements recognised without painting', () {
    test('foreignObject content never reaches the content stream', () async {
      final content = await _render('''
        <svg width="40" height="40">
          <foreignObject x="0" y="0" width="20" height="20">
            <div xmlns="http://www.w3.org/1999/xhtml">text</div>
          </foreignObject>
          <rect width="4" height="4"/>
        </svg>
      ''');

      expect(content, contains('0 0 3 3 re\n'));
      expect(content, isNot(contains('Tj')));
    });

    test('a filter definition is recognised and never painted', () async {
      final content = await _render('''
        <svg width="40" height="40">
          <defs>
            <filter id="blur">
              <feGaussianBlur stdDeviation="2"/>
              <feOffset dx="1" dy="1"/>
            </filter>
          </defs>
          <rect width="4" height="4" filter="url(#blur)" fill="#ff0000"/>
        </svg>
      ''');

      expect(content, contains('0 0 3 3 re\n'),
          reason: 'the referencing element is still drawn, without the effect');
      expect(_count(content, ' re\n'), 2,
          reason: 'only the viewport clip and the rectangle itself');
    });

    test('animation and script elements are dropped', () async {
      final content = await _render('''
        <svg width="40" height="40">
          <script>var x = 1;</script>
          <rect width="4" height="4">
            <animate attributeName="width" to="20"/>
          </rect>
        </svg>
      ''');

      expect(content, contains('0 0 3 3 re\n'));
      expect(_count(content, ' re\n'), 2);
    });
  });
}
