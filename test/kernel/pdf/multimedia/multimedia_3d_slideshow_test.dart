import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

Uint8List artwork(String tag) => Uint8List.fromList(
    List<int>.generate(tag.length, (i) => tag.codeUnitAt(i)));

void main() {
  group('13.5 alternate presentations (Table 297)', () {
    test('/StartResource shall name an entry of /Resources', () {
      expect(
          () => PdfSlideShow.create('missing.svg', {
                'present.svg': PdfStream.withBytes(artwork('svg'), 0),
              }),
          throwsArgumentError);
    });

    test('A slideshow writes /Type, /Subtype and its virtual file system',
        () async {
      final root = PdfStream.withBytes(artwork('svg'), 0);
      final show = PdfSlideShow.create('mysvg.svg', {
        'mysvg.svg': root,
        'abc0001.jpg': PdfStream.withBytes(artwork('jpg'), 0),
      });
      expect(
          (await show.pdfRepresentation().nameEntry(PdfName('Type')))!
              .getValue(),
          'SlideShow');
      expect(
          (await show.pdfRepresentation().nameEntry(PdfName('Subtype')))!
              .getValue(),
          'Embedded');
      expect(await show.getStartResource(), 'mysvg.svg');
      expect((await show.getResourceNames())..sort(),
          ['abc0001.jpg', 'mysvg.svg']);
      expect(await show.getStartObject(), same(root));
      expect(await show.isStructurallyValid(), isTrue);
    });

    test('A slideshow survives a round trip through /AlternatePresentations',
        () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      await document.appendBlankPage();

      final svg = PdfStream.withBytes(artwork('<svg/>'), 0)
        ..put(PdfName('Type'), PdfName('EmbeddedFile'))
        ..attachToDocument(document);
      final music = PdfStream.withBytes(artwork('mp3'), 0)
        ..put(PdfName('Type'), PdfName('EmbeddedFile'))
        ..attachToDocument(document);

      final show = PdfSlideShow.create('mysvg.svg', {
        'mysvg.svg': svg,
        'mymusic.mp3': music,
      });
      await show.registerIn(document, 'MySlideShow');
      await document.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(bytes.takeBytes()));
      addTearDown(reopened.close);

      final stored = await PdfSlideShow.read(reopened, 'MySlideShow');
      expect(stored, isNotNull);
      expect(await stored!.getStartResource(), 'mysvg.svg');
      expect(await stored.isStructurallyValid(), isTrue);
      expect((await stored.getResourceNames())..sort(),
          ['mymusic.mp3', 'mysvg.svg']);
      final startObject = await stored.getStartObject();
      expect(startObject, isA<PdfStream>());
      expect(await (startObject as PdfStream).getBytes(), artwork('<svg/>'));
      expect(await PdfSlideShow.read(reopened, 'Absent'), isNull);
    });
  });

  group('13.6.3 3D streams (Table 300)', () {
    test('A 3D stream writes /Type /3D and its /Subtype', () async {
      final stream =
          Pdf3DStream.fromArtwork(artwork('U3D-data'), Pdf3DStream.subtypeU3D);
      expect(
          (await stream.pdfRepresentation().nameEntry(PdfName('Type')))!
              .getValue(),
          '3D');
      expect((await stream.getSubtype())!.getValue(), 'U3D');
      expect(await stream.getArtwork(), artwork('U3D-data'));
    });

    test('The PRC subtype is accepted as an opaque payload', () async {
      final stream =
          Pdf3DStream.fromArtwork(artwork('PRC'), Pdf3DStream.subtypePRC);
      expect((await stream.getSubtype())!.getValue(), 'PRC');
    });

    test('/DV resolves against /VA in all four forms of Table 300', () async {
      final first = Pdf3DView.named('Front', internalName: 'front');
      final middle = Pdf3DView.named('Side', internalName: 'side');
      final last = Pdf3DView.named('Top', internalName: 'top');
      final stream =
          Pdf3DStream.fromArtwork(artwork('U3D'), Pdf3DStream.subtypeU3D)
            ..setViews([first, middle, last]);

      expect(
          await (await stream.resolveDefaultView())!.getExternalName(), 'Front',
          reason: '/DV defaults to index 0 when /VA is present');

      stream.setDefaultViewIndex(1);
      expect(
          await (await stream.resolveDefaultView())!.getExternalName(), 'Side');

      stream.setDefaultViewName('top');
      expect(
          await (await stream.resolveDefaultView())!.getExternalName(), 'Top');

      stream.setDefaultViewPosition(Pdf3DStream.defaultViewLast);
      expect(
          await (await stream.resolveDefaultView())!.getExternalName(), 'Top');

      stream.setDefaultViewPosition(Pdf3DStream.defaultViewFirst);
      expect(await (await stream.resolveDefaultView())!.getExternalName(),
          'Front');

      expect(() => stream.setDefaultViewIndex(-1), throwsArgumentError);
      expect(() => stream.setDefaultViewPosition(PdfName('X')),
          throwsArgumentError);
    });

    test('A 3D animation style validates /Subtype and /TM', () async {
      final style =
          Pdf3DAnimationStyle.ofStyle(Pdf3DAnimationStyle.styleOscillating)
            ..setPlayCount(-1)
            ..setTimeMultiplier(2);
      expect((await style.getStyle()).getValue(), 'Oscillating');
      expect(await style.isRepeatForever(), isTrue);
      expect(await style.getTimeMultiplier(), 2.0);
      expect(() => Pdf3DAnimationStyle.ofStyle(PdfName('Bounce')),
          throwsArgumentError);
      expect(() => style.setTimeMultiplier(0), throwsArgumentError);

      final defaults = Pdf3DAnimationStyle(PdfDictionary());
      expect((await defaults.getStyle()).getValue(), 'None');
      expect(await defaults.getPlayCount(), 0);
      expect(await defaults.getTimeMultiplier(), 1.0);
    });
  });

  group('13.6.4 3D views (Tables 304 to 310)', () {
    test('/MS /M requires a twelve-element /C2W', () async {
      final view = Pdf3DView.named('Front');
      expect(await view.isMatrixSourceSatisfied(), isTrue,
          reason: 'a missing /MS uses the view stored in the artwork');
      expect(() => view.setCameraToWorldMatrix([1, 0, 0]), throwsArgumentError);
      view.setCameraToWorldMatrix([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, -100]);
      expect((await view.getMatrixSource())!.getValue(), 'M');
      expect((await view.getCameraToWorldMatrix())!.length, 12);
      expect(await view.isMatrixSourceSatisfied(), isTrue);
    });

    test('/MS /U3D requires /U3DPath and accepts both its forms', () async {
      final single = Pdf3DView.named('Front')..setU3DPath(['root']);
      expect((await single.getMatrixSource())!.getValue(), 'U3D');
      expect(await single.getU3DPath(), ['root']);
      expect(await single.isMatrixSourceSatisfied(), isTrue);

      final nested = Pdf3DView.named('Nested')..setU3DPath(['root', 'child']);
      expect(await nested.getU3DPath(), ['root', 'child']);

      expect(() => Pdf3DView.named('Bad').setU3DPath([]), throwsArgumentError);

      final broken = Pdf3DView.named('Broken');
      broken.pdfRepresentation().put(PdfName('MS'), PdfName('U3D'));
      expect(await broken.isMatrixSourceSatisfied(), isFalse);
    });

    test('An unrecognised /MS makes the view unsatisfiable', () async {
      final view = Pdf3DView.named('Front');
      view.pdfRepresentation().put(PdfName('MS'), PdfName('XX'));
      expect(await view.isMatrixSourceSatisfied(), isFalse);
    });

    test('A projection validates /FOV, clipping and scaling', () async {
      final perspective = Pdf3DProjection.perspective(fieldOfView: 60);
      expect((await perspective.getSubtype())!.getValue(), 'P');
      expect(await perspective.getFieldOfView(), 60);
      expect((await perspective.getClippingStyle()).getValue(), 'ANF');
      expect(() => Pdf3DProjection.perspective(fieldOfView: 181),
          throwsArgumentError);

      await perspective.setExplicitClipping(1, far: 500);
      expect((await perspective.getClippingStyle()).getValue(), 'XNF');
      expect(await perspective.getNearClipping(), 1);
      expect(await perspective.getFarClipping(), 500);
      await expectLater(perspective.setExplicitClipping(0), throwsArgumentError,
          reason: 'a perspective /N shall be positive');
      await expectLater(
          perspective.setExplicitClipping(10, far: 5), throwsArgumentError);

      perspective.setProjectionScaleName('Min');
      expect((await perspective.getProjectionScale() as PdfName).getValue(),
          'Min');
      expect(() => perspective.setProjectionScaleName('Middle'),
          throwsArgumentError);
      perspective.setProjectionScaleDiameter(120);
      expect((await perspective.getProjectionScale() as PdfNumber).getValue(),
          120);
      expect(
          () => perspective.setProjectionScaleDiameter(0), throwsArgumentError);

      final orthographic = Pdf3DProjection.orthographic(scale: 2);
      expect((await orthographic.getSubtype())!.getValue(), 'O');
      expect(await orthographic.getOrthographicScale(), 2.0);
      expect(
          (await orthographic.getOrthographicBinding()).getValue(), 'Absolute');
      await orthographic.setExplicitClipping(0);
      expect(await orthographic.getNearClipping(), 0,
          reason: 'an orthographic /N may be zero');
      orthographic.setOrthographicBinding('Max');
      expect((await orthographic.getOrthographicBinding()).getValue(), 'Max');
      expect(() => orthographic.setOrthographicBinding('Fit'),
          throwsArgumentError);
      expect(() => orthographic.setOrthographicScale(0), throwsArgumentError);
      expect(await Pdf3DProjection.orthographic().getOrthographicScale(), 1.0);
    });

    test('A background defaults to opaque DeviceRGB white', () async {
      final defaults = Pdf3DBackground(PdfDictionary());
      expect((await defaults.getColourSpace()).getValue(), 'DeviceRGB');
      expect(await defaults.isEntireAnnotation(), isFalse);

      final background =
          Pdf3DBackground.solid([0.2, 0.4, 0.6], applyToEntireAnnotation: true);
      expect(await background.getColour(), [0.2, 0.4, 0.6]);
      expect(await background.isEntireAnnotation(), isTrue);
      expect(() => Pdf3DBackground.solid([]), throwsArgumentError);
    });

    test('Render modes and lighting schemes validate their /Subtype', () async {
      final render = Pdf3DRenderMode.ofStyle('ShadedIllustration');
      expect((await render.getStyle())!.getValue(), 'ShadedIllustration');
      expect(() => Pdf3DRenderMode.ofStyle('Cartoon'), throwsArgumentError);

      final lighting = Pdf3DLightingScheme.ofScheme('Headlamp');
      expect((await lighting.getScheme()).getValue(), 'Headlamp');
      expect(() => Pdf3DLightingScheme.ofScheme('Sunset'), throwsArgumentError);
      expect(
          (await Pdf3DLightingScheme(PdfDictionary()).getScheme()).getValue(),
          'Artwork');
    });
  });

  group('13.6.2 3D annotations (Tables 298 and 299)', () {
    test('Activation defaults and validation follow Table 299', () async {
      final activation = Pdf3DActivation.create();
      expect((await activation.getActivation()).getValue(), 'XA');
      expect((await activation.getDeactivation()).getValue(), 'PI');
      expect((await activation.getActivationState()).getValue(), 'L');
      expect((await activation.getDeactivationState()).getValue(), 'U');
      expect(await activation.isShowToolbar(), isTrue);
      expect(await activation.isShowModelTree(), isFalse);

      expect(
          () => activation.setActivation(PdfName('XX')), throwsArgumentError);
      expect(
          () => activation.setDeactivation(PdfName('XX')), throwsArgumentError);
      expect(
          () => activation
              .setActivationState(Pdf3DActivation.stateUninstantiated),
          throwsArgumentError,
          reason: '/AIS shall be /I or /L only');
      expect(() => activation.setDeactivationState(PdfName('X')),
          throwsArgumentError);
    });

    test('/3DB defaults to the annotation rect in target coordinates',
        () async {
      final stream =
          Pdf3DStream.fromArtwork(artwork('U3D'), Pdf3DStream.subtypeU3D);
      final annotation =
          Pdf3DAnnotation.forStream(Rectangle(20, 30, 100, 60), stream);
      expect(await annotation.getViewBox(), isNull);
      expect(await annotation.defaultViewBox(), [-50.0, -30.0, 50.0, 30.0]);
      expect(
          await annotation.getEffectiveViewBox(), [-50.0, -30.0, 50.0, 30.0]);
      annotation.setViewBox([-40, -20, 40, 20]);
      expect(
          await annotation.getEffectiveViewBox(), [-40.0, -20.0, 40.0, 20.0]);
      expect(() => annotation.setViewBox([1, 2, 3]), throwsArgumentError);
    });

    test('/3DV falls back to the stream /DV and accepts every Table 298 form',
        () async {
      final front = Pdf3DView.named('Front', internalName: 'front');
      final back = Pdf3DView.named('Back', internalName: 'back');
      final stream =
          Pdf3DStream.fromArtwork(artwork('U3D'), Pdf3DStream.subtypeU3D)
            ..setViews([front, back])
            ..setDefaultViewIndex(1);
      final annotation =
          Pdf3DAnnotation.forStream(Rectangle(0, 0, 100, 100), stream);

      expect(await (await annotation.resolveDefaultView())!.getExternalName(),
          'Back',
          reason: 'a missing /3DV defers to the 3D stream /DV');

      annotation.setDefaultViewIndex(0);
      expect(await (await annotation.resolveDefaultView())!.getExternalName(),
          'Front');

      annotation.setDefaultViewName('back');
      expect(await (await annotation.resolveDefaultView())!.getExternalName(),
          'Back');

      annotation.setDefaultViewPosition(PdfName('L'));
      expect(await (await annotation.resolveDefaultView())!.getExternalName(),
          'Back');

      annotation.setDefaultViewPosition(PdfName('D'));
      expect(await (await annotation.resolveDefaultView())!.getExternalName(),
          'Back');

      annotation.setDefaultViewDictionary(Pdf3DView.named('Ad hoc'));
      expect(await (await annotation.resolveDefaultView())!.getExternalName(),
          'Ad hoc');

      expect(() => annotation.setDefaultViewPosition(PdfName('X')),
          throwsArgumentError);
      expect(() => annotation.setDefaultViewIndex(-1), throwsArgumentError);
    });

    test('A 3D reference dictionary is followed to its stream', () async {
      final stream =
          Pdf3DStream.fromArtwork(artwork('U3D'), Pdf3DStream.subtypeU3D);
      final reference = Pdf3DReference.to(stream);
      final shared =
          Pdf3DAnnotation.forReference(Rectangle(0, 0, 50, 50), reference);
      expect(await shared.getArtworkReference(), isNotNull);
      expect(
          (await (await shared.getArtworkStream())!.getSubtype())!.getValue(),
          'U3D');

      final own = Pdf3DAnnotation.forStream(Rectangle(0, 0, 50, 50), stream);
      expect(await own.getArtworkReference(), isNull);
      expect(await own.getArtworkStream(), isNotNull);
    });

    test('A 3D annotation survives a round trip', () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final page = await document.appendBlankPage();

      final view = Pdf3DView.named('Isometric', internalName: 'iso')
        ..setCameraToWorldMatrix([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, -250])
        ..setCentreOfOrbit(250)
        ..setProjection(Pdf3DProjection.perspective(fieldOfView: 45))
        ..setBackground(Pdf3DBackground.solid([1, 1, 1]))
        ..setRenderMode(Pdf3DRenderMode.ofStyle('SolidWireframe'))
        ..setLightingScheme(Pdf3DLightingScheme.ofScheme('CAD'))
        ..setCrossSections([])
        ..setNodes([], restoreFirst: true);

      final stream = Pdf3DStream.fromArtwork(
          artwork('U3D-payload'), Pdf3DStream.subtypeU3D)
        ..setViews([view])
        ..setDefaultViewName('iso')
        ..setAnimationStyle(
            Pdf3DAnimationStyle.ofStyle(Pdf3DAnimationStyle.styleLinear)
              ..setPlayCount(3)
              ..setTimeMultiplier(1.5))
        ..attachToDocument(document);

      final reference = Pdf3DReference.to(stream)..attachToDocument(document);

      final annotation =
          Pdf3DAnnotation.forReference(Rectangle(0, 0, 400, 300), reference)
            ..setInteractive(false)
            ..setViewBox([-180, -130, 180, 130])
            ..setActivationDictionary(Pdf3DActivation.create()
              ..setActivation(Pdf3DActivation.activationPageOpen)
              ..setDeactivation(Pdf3DActivation.deactivationPageClose)
              ..setActivationState(Pdf3DActivation.stateInstantiated)
              ..setDeactivationState(Pdf3DActivation.stateUninstantiated)
              ..setShowToolbar(false)
              ..setShowModelTree(true));
      annotation.pdfRepresentation().attachToDocument(document);
      page.pdfRepresentation().put(PdfName('Annots'),
          PdfArray.fromList([annotation.pdfRepresentation()]));
      await document.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(bytes.takeBytes()));
      addTearDown(reopened.close);

      final annots = await (await reopened.pageAt(1))!
          .pdfRepresentation()
          .arrayEntry(PdfName('Annots'));
      final stored = Pdf3DAnnotation((await annots!.dictionaryEntry(0))!);
      expect(stored.getSubtype().getValue(), '3D');
      expect(await stored.isInteractive(), isFalse);
      expect(await stored.getViewBox(), [-180.0, -130.0, 180.0, 130.0]);

      expect(await stored.getArtworkReference(), isNotNull);
      final storedStream = (await stored.getArtworkStream())!;
      expect((await storedStream.getSubtype())!.getValue(), 'U3D');
      expect(await storedStream.getArtwork(), artwork('U3D-payload'));

      final storedAnimation = (await storedStream.getAnimationStyle())!;
      expect((await storedAnimation.getStyle()).getValue(), 'Linear');
      expect(await storedAnimation.getPlayCount(), 3);
      expect(await storedAnimation.getTimeMultiplier(), 1.5);

      final storedView = (await stored.resolveDefaultView())!;
      expect(await storedView.getExternalName(), 'Isometric');
      expect(await storedView.getInternalName(), 'iso');
      expect((await storedView.getMatrixSource())!.getValue(), 'M');
      expect((await storedView.getCameraToWorldMatrix())!.last, -250);
      expect(await storedView.getCentreOfOrbit(), 250);
      expect(await (await storedView.getProjection())!.getFieldOfView(), 45);
      expect(await (await storedView.getBackground())!.getColour(),
          [1.0, 1.0, 1.0]);
      expect((await (await storedView.getRenderMode())!.getStyle())!.getValue(),
          'SolidWireframe');
      expect(
          (await (await storedView.getLightingScheme())!.getScheme())
              .getValue(),
          'CAD');
      expect((await storedView.getCrossSections())!.size(), 0,
          reason: 'an empty /SA means no cross sections are displayed');
      expect(await storedView.isRestoreNodes(), isTrue);

      final storedActivation = (await stored.getActivationDictionary())!;
      expect((await storedActivation.getActivation()).getValue(), 'PO');
      expect((await storedActivation.getDeactivation()).getValue(), 'PC');
      expect((await storedActivation.getActivationState()).getValue(), 'I');
      expect((await storedActivation.getDeactivationState()).getValue(), 'U');
      expect(await storedActivation.isShowToolbar(), isFalse);
      expect(await storedActivation.isShowModelTree(), isTrue);
    });
  });
}
