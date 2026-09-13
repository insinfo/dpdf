import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

/// Round-trip helper following the repository convention: build a document,
/// close it, reopen it from the produced bytes.
Future<PdfDocument> reopen(Uint8List bytes) async =>
    PdfDocument.open(PdfReader.fromBytes(bytes));

Future<PdfDictionary?> namedRendition(PdfDocument document, String name) async {
  final names =
      await document.rootCatalog().pdfRepresentation().dictionaryEntry(
            PdfName('Names'),
          );
  final tree = await names!.dictionaryEntry(PdfName('Renditions'));
  final entries = await tree!.arrayEntry(PdfName('Names'));
  for (var i = 0; i < entries!.size(); i += 2) {
    final key = await entries.stringEntry(i);
    if (key?.getValue() == name) return await entries.dictionaryEntry(i + 1);
  }
  return null;
}

void main() {
  group('13.2.6.3 timespan dictionary (Table 289)', () {
    test('A simple timespan writes /Type, /S and /V', () async {
      final timespan = PdfTimespan.ofSeconds(12.5);
      expect((await timespan.getSubtype())!.getValue(), 'S');
      expect(await timespan.getSeconds(), 12.5);
      expect(
          (await timespan.pdfRepresentation().nameEntry(PdfName('Type')))!
              .getValue(),
          'Timespan');
      expect(await timespan.isViable(), isTrue);
    });

    test('PDF 1.5 forbids a negative timespan', () {
      expect(() => PdfTimespan.ofSeconds(-1), throwsArgumentError);
    });

    test('An unrecognised /S makes the timespan non-viable', () async {
      final dictionary = PdfDictionary()
        ..put(PdfName('S'), PdfName('X'))
        ..put(PdfName('V'), PdfNumber(1));
      expect(await PdfTimespan(dictionary).isViable(), isFalse);
    });
  });

  group('13.2.6.2 media offset dictionaries (Tables 285 to 288)', () {
    test('A time offset carries a timespan in /T', () async {
      final offset = PdfMediaOffset.seconds(30);
      expect((await offset.getSubtype())!.getValue(), 'T');
      expect(await (await offset.getTimespan())!.getSeconds(), 30);
    });

    test('A frame offset carries /F and rejects negative frames', () async {
      final offset = PdfMediaOffset.frame(20);
      expect((await offset.getSubtype())!.getValue(), 'F');
      expect(await offset.getFrame(), 20);
      expect(() => PdfMediaOffset.frame(-1), throwsArgumentError);
    });

    test('A marker offset carries /M', () async {
      final offset = PdfMediaOffset.marker('Chapter One');
      expect((await offset.getSubtype())!.getValue(), 'M');
      expect(await offset.getMarker(), 'Chapter One');
    });
  });

  group('13.2.5 media duration dictionary (Table 281)', () {
    test('Intrinsic, infinite and explicit durations resolve', () async {
      expect(await PdfMediaDuration.intrinsic().getSeconds(), isNull);
      expect(await PdfMediaDuration.infinity().getSeconds(), double.infinity);
      expect(await PdfMediaDuration.ofSeconds(7.5).getSeconds(), 7.5);
      expect(
          (await PdfMediaDuration.ofSeconds(1).getSubtype())!.getValue(), 'T');
    });
  });

  group('13.2.7.4 software identifier (Table 292)', () {
    test('A software name becomes a vnd.adobe.swname URI', () async {
      final software = PdfSoftwareIdentifier.forSoftwareName('ADBE_Acrobat');
      expect(await software.getUri(), 'vnd.adobe.swname:ADBE_Acrobat');
      expect(await software.getSoftwareName(), 'ADBE_Acrobat');
    });

    test('The scheme is case-insensitive and the name is escaped once',
        () async {
      final escaped = PdfSoftwareIdentifier.forSoftwareName('My Player/2');
      expect(await escaped.getUri(), 'vnd.adobe.swname:My%20Player%2F2');
      expect(await escaped.getSoftwareName(), 'My Player/2');
      final upper =
          PdfSoftwareIdentifier.forUri('VND.ADOBE.SWNAME:ADBE_Acrobat');
      expect(await upper.getSoftwareName(), 'ADBE_Acrobat');
    });

    test('Version arrays compare per 13.2.7.4.3', () {
      expect(compareVersions([5, 1], [5]), greaterThan(0));
      expect(compareVersions([5], [5, 0, 0]), 0);
      expect(compareVersions([5], []), lessThan(0));
      expect(compareVersions([], []), 0);
      expect(compareVersions([4, 9], [5]), lessThan(0));
    });

    test('Negative subversion numbers are rejected', () {
      final software = PdfSoftwareIdentifier.forSoftwareName('P');
      expect(() => software.setLowVersion([1, -1]), throwsArgumentError);
    });

    test('The software identifier algorithm honours bounds and /OS', () async {
      final software = PdfSoftwareIdentifier.forSoftwareName('ADBE_Acrobat')
        ..setLowVersion([5])
        ..setHighVersion([7])
        ..setOperatingSystems(['Windows']);
      expect(
          await software.matches('ADBE_Acrobat', [6],
              operatingSystem: 'Windows'),
          isTrue);
      expect(
          await software.matches('ADBE_Acrobat', [5],
              operatingSystem: 'Windows'),
          isTrue,
          reason: '/LI defaults to true, so the lower bound is inclusive');
      expect(
          await software.matches('ADBE_Acrobat', [8],
              operatingSystem: 'Windows'),
          isFalse);
      expect(
          await software.matches('ADBE_Acrobat', [6], operatingSystem: 'Mac'),
          isFalse);
      expect(await software.matches('Other', [6], operatingSystem: 'Windows'),
          isFalse);
      software.setLowInclusive(false);
      expect(
          await software.matches('ADBE_Acrobat', [5],
              operatingSystem: 'Windows'),
          isFalse);
    });

    test('/OS rejects duplicate identifiers', () {
      final software = PdfSoftwareIdentifier.forSoftwareName('P');
      expect(() => software.setOperatingSystems(['Windows', 'Windows']),
          throwsArgumentError);
    });
  });

  group('13.2.7.2 media players dictionary (Table 290)', () {
    PdfMediaPlayerInfo info(String name, List<int> low, List<int> high) =>
        PdfMediaPlayerInfo.forPlayer(PdfSoftwareIdentifier.forSoftwareName(name)
          ..setLowVersion(low)
          ..setHighVersion(high));

    test('A player in /NU may never be used', () async {
      final players = PdfMediaPlayers.create()
        ..setAllowed([
          info('A', [1], [9])
        ])
        ..setNeverUse([
          info('A', [1], [9])
        ]);
      expect(await players.mayUsePlayer('A', [2]), isFalse);
    });

    test('A non-empty /MU in either dictionary constrains the choice',
        () async {
      final clipPlayers = PdfMediaPlayers.create()
        ..setMustUse([
          info('A', [1], [10])
        ]);
      final playPlayers = PdfMediaPlayers.create()
        ..setMustUse([
          info('A', [3], [5])
        ]);
      expect(
          await clipPlayers.mayUsePlayer('A', [4], other: playPlayers), isTrue);
      expect(
          await clipPlayers.mayUsePlayer('A', [8], other: playPlayers), isFalse,
          reason: 'the player shall be found in both non-empty /MU arrays');
      expect(await clipPlayers.mayUsePlayer('B', [4], other: playPlayers),
          isFalse);
    });

    test(
        'Without /MU and without a known content type the player shall be in /A',
        () async {
      final players = PdfMediaPlayers.create()
        ..setAllowed([
          info('A', [1], [9])
        ]);
      expect(await players.mayUsePlayer('A', [2]), isTrue);
      expect(await players.mayUsePlayer('B', [2]), isFalse);
    });

    test('A player that does not support a known content type is rejected',
        () async {
      final players = PdfMediaPlayers.create()
        ..setAllowed([
          info('A', [1], [9])
        ]);
      expect(
          await players.mayUsePlayer('A', [2],
              contentTypeKnown: true, playerSupportsContentType: false),
          isFalse);
    });
  });

  group('13.2.4 media clip objects (Tables 273 to 278)', () {
    test('Media clip data references a file specification with /Type',
        () async {
      final clip = PdfMediaClipData.forFileSpec(
          PdfFileSpec.url('https://example.org/clip.mp4'),
          contentType: 'video/mp4')
        ..setName('intro');
      expect((await clip.getSubtype())!.getValue(), 'MCD');
      expect(await clip.getContentType(), 'video/mp4');
      expect(await clip.getName(), 'intro');
      expect(await clip.isDataViable(), isTrue,
          reason: '/D shall carry a recognised /Type entry');
    });

    test('/CT is not allowed for a form XObject', () {
      final clip = PdfMediaClipData.forFormXObject(
          PdfStream.withBytes(Uint8List.fromList([0x20]), 0));
      expect(() => clip.setContentType('video/mp4'), throwsStateError);
    });

    test('Media permissions default to (TEMPNEVER) and reject bad values',
        () async {
      expect(
          await PdfMediaPermissions(PdfDictionary()).getTemporaryFilePolicy(),
          'TEMPNEVER');
      expect(
          await PdfMediaPermissions.create(PdfMediaPermissions.temporaryAlways)
              .getTemporaryFilePolicy(),
          'TEMPALWAYS');
      expect(() => PdfMediaPermissions.create('TEMPSOMETIMES'),
          throwsArgumentError);
    });

    test('A media clip section chain terminates in media clip data', () async {
      final data = PdfMediaClipData.forFileSpec(
          PdfFileSpec.url('https://example.org/movie.mp4'));
      final outer = PdfMediaClipSection.of(PdfMediaClipSection.of(data))
        ..setMustHonourBegin(PdfMediaOffset.seconds(60))
        ..setBestEffortEnd(PdfMediaOffset.seconds(900));
      expect((await outer.getSubtype())!.getValue(), 'MCS');
      expect(
          await (await outer.getBegin())!
              .getTimespan()
              .then((t) => t!.getSeconds()),
          60);
      expect(
          await (await outer.getEnd())!
              .getTimespan()
              .then((t) => t!.getSeconds()),
          900);
      final resolved = await outer.resolveClipData();
      expect(resolved, isNotNull);
      expect(resolved!.pdfRepresentation(), same(data.pdfRepresentation()));
    });

    test('/MH takes precedence over /BE for the base URL', () async {
      final clip = PdfMediaClipData.forFileSpec(
          PdfFileSpec.url('https://example.org/clip.mp4'))
        ..setBestEffortBaseUrl('https://fallback.example.org/')
        ..setMustHonourBaseUrl('https://example.org/');
      expect(await clip.getBaseUrl(), 'https://example.org/');
    });

    test('/Alt shall hold language/text pairs', () {
      final clip = PdfMediaClipData.forFileSpec(
          PdfFileSpec.url('https://example.org/clip.mp4'));
      expect(
          () => clip.setAlternateDescriptions(['en-us']), throwsArgumentError);
    });
  });

  group('13.2.5 media play parameters (Tables 279 and 280)', () {
    test('Defaults match Table 280', () async {
      final params = PdfMediaPlayParams.create();
      expect(await params.getVolume(), 100);
      expect(await params.isShowController(), isFalse);
      expect(await params.getFitMode(), PdfMediaFitMode.playerDefault);
      expect(await params.isAutoPlay(), isTrue);
      expect(await params.getRepeatCount(), 1.0);
    });

    test('Negative volume and repeat counts are rejected', () {
      final params = PdfMediaPlayParams.create();
      expect(() => params.setVolume(-1), throwsArgumentError);
      expect(() => params.setRepeatCount(-0.5), throwsArgumentError);
      expect(() => params.setFitMode(6), throwsArgumentError);
    });

    test('A zero repeat count means repeat forever', () async {
      final params = PdfMediaPlayParams.create()..setRepeatCount(0);
      expect(await params.isRepeatForever(), isTrue);
    });

    test('An unrecognised /F in /MH makes the object non-viable', () async {
      final params = PdfMediaPlayParams.create();
      params.mustHonour().put(PdfName('F'), PdfNumber(9));
      expect(await params.isFitModeViable(), isFalse);
      expect(await params.getFitMode(), PdfMediaFitMode.playerDefault);
      final bestEffortOnly = PdfMediaPlayParams.create();
      bestEffortOnly.bestEffort().put(PdfName('F'), PdfNumber(9));
      expect(await bestEffortOnly.isFitModeViable(), isTrue,
          reason: 'an unrecognised /BE value is treated as the default');
    });

    test('/MH takes precedence over /BE', () async {
      final params = PdfMediaPlayParams.create()
        ..setVolume(50)
        ..setVolume(80, bestEffortOnly: false);
      expect(await params.getVolume(), 80);
    });
  });

  group('13.2.6 media screen parameters (Tables 282 to 284)', () {
    test('Defaults match Table 283', () async {
      final params = PdfMediaScreenParams.create();
      expect(await params.getWindowType(), PdfMediaWindowType.annotation);
      expect(await params.getOpacity(), 1.0);
      expect(await params.getMonitor(), PdfMonitorSpecifier.documentMonitor);
      expect(await params.isViable(), isTrue);
    });

    test('A floating window requires floating window parameters', () async {
      final params = PdfMediaScreenParams.create()
        ..setWindowType(PdfMediaWindowType.floating);
      expect(await params.isViable(), isFalse);
      params.setFloatingWindow(PdfFloatingWindowParams.ofSize(320, 240)
        ..setPosition(PdfFloatingWindowPosition.upperRight)
        ..setResizeBehaviour(PdfFloatingWindowResize.keepAspectRatio));
      expect(await params.isViable(), isTrue);
      final window = (await params.getFloatingWindow())!;
      expect(await window.getSize(), [320, 240]);
      expect(await window.getPosition(), PdfFloatingWindowPosition.upperRight);
      expect(await window.getRelativeTo(),
          PdfFloatingWindowRelativeTo.documentWindow);
      expect(await window.hasTitleBar(), isTrue);
      expect(await window.getOffscreenBehaviour(),
          PdfFloatingWindowOffscreen.moveOnScreen);
    });

    test('Out-of-range values are rejected', () {
      final params = PdfMediaScreenParams.create();
      expect(() => params.setWindowType(4), throwsArgumentError);
      expect(() => params.setOpacity(1.5), throwsArgumentError);
      expect(() => params.setBackgroundColour([0, 0]), throwsArgumentError);
      expect(() => params.setBackgroundColour([0, 0, 2]), throwsArgumentError);
      expect(() => params.setMonitor(7), throwsArgumentError);
      final window = PdfFloatingWindowParams.ofSize(10, 10);
      expect(() => window.setPosition(9), throwsArgumentError);
      expect(() => window.setRelativeTo(4), throwsArgumentError);
      expect(() => window.setResizeBehaviour(3), throwsArgumentError);
      expect(() => window.setOffscreenBehaviour(3), throwsArgumentError);
    });
  });

  group('13.2.3 renditions (Tables 266 to 272)', () {
    test('A media rendition without /C requires players in /P', () async {
      final empty = PdfMediaPlayParams.create();
      await expectLater(
          PdfMediaRendition.withoutClip(empty), throwsArgumentError);
      final withPlayers = PdfMediaPlayParams.create()
        ..setPlayers(PdfMediaPlayers.create()
          ..setAllowed([
            PdfMediaPlayerInfo.forPlayer(
                PdfSoftwareIdentifier.forSoftwareName('ADBE_Acrobat'))
          ]));
      final rendition = await PdfMediaRendition.withoutClip(withPlayers);
      expect(await rendition.isStructurallyViable(), isTrue);
      expect(await rendition.getClip(), isNull);
    });

    test('A media rendition with neither /C nor /P is not viable', () async {
      final rendition = PdfMediaRendition(PdfDictionary()
        ..put(PdfName('Type'), PdfName('Rendition'))
        ..put(PdfName('S'), PdfName('MR')));
      expect(await rendition.isStructurallyViable(), isFalse);
    });

    test('A selector rendition finds the first viable media rendition',
        () async {
      final clip = PdfMediaClipData.forFileSpec(
          PdfFileSpec.url('https://example.org/small.mp4'));
      final large = PdfMediaRendition.forClip(clip)..setName('large');
      final small = PdfMediaRendition.forClip(clip)..setName('small');
      final nestedSelector = PdfSelectorRendition.of([small]);
      final root = PdfSelectorRendition.of([large, nestedSelector]);
      expect((await root.getRenditions()).length, 2);

      final chosen = await root.firstViableMediaRendition(
          (rendition) async => await rendition.getName() != 'large');
      expect(await chosen!.getName(), 'small');

      final pruned = await root.firstViableMediaRendition((rendition) async =>
          rendition is! PdfSelectorRendition ||
          identical(rendition.pdfRepresentation(), root.pdfRepresentation()));
      expect(await pruned!.getName(), 'large');
    });

    test('Rendition survives a save and reopen through /Renditions', () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      await document.appendBlankPage();

      final clip = PdfMediaClipData.forFileSpec(
          PdfFileSpec.url('https://example.org/clip.mp4'),
          contentType: 'video/mp4')
        ..setName('clip')
        ..setPermissions(
            PdfMediaPermissions.create(PdfMediaPermissions.temporaryExtract))
        ..attachToDocument(document);

      final playParams = PdfMediaPlayParams.create()
        ..setVolume(70)
        ..setShowController(true)
        ..setFitMode(PdfMediaFitMode.meet)
        ..setAutoPlay(false)
        ..setRepeatCount(2)
        ..setDuration(PdfMediaDuration.ofSeconds(45));

      final screenParams = PdfMediaScreenParams.create()
        ..setBackgroundColour([0.25, 0.5, 0.75])
        ..setOpacity(0.5)
        ..setMonitor(PdfMonitorSpecifier.primary)
        ..setFloatingWindow(PdfFloatingWindowParams.ofSize(640, 480));

      final rendition = PdfMediaRendition.forClip(clip)
        ..setName('promo')
        ..setPlayParams(playParams)
        ..setScreenParams(screenParams)
        ..setMustHonourCriteria(PdfMediaCriteria.create()
          ..setTextCaptions(true)
          ..setMinimumBandwidth(256000)
          ..setMinimumBitDepth(PdfMinimumBitDepth.create(16))
          ..setMinimumScreenSize(PdfMinimumScreenSize.create(800, 600))
          ..setLanguages(['en-us'])
          ..setPdfVersionRange('1.5', '1.7'));
      await rendition.registerIn(document);
      await document.close();

      final reopened = await reopen(bytes.takeBytes());
      addTearDown(reopened.close);
      final stored = await namedRendition(reopened, 'promo');
      expect(stored, isNotNull);
      final read = (await PdfRendition.read(stored!)) as PdfMediaRendition;
      expect(await read.getName(), 'promo');
      expect((await read.getSubtype())!.getValue(), 'MR');

      final readClip = (await read.getClip()) as PdfMediaClipData;
      expect(await readClip.getContentType(), 'video/mp4');
      expect(await readClip.getName(), 'clip');
      expect(await (await readClip.getPermissions())!.getTemporaryFilePolicy(),
          'TEMPEXTRACT');
      expect(await (await readClip.getFileSpec())!.getFileName(),
          'https://example.org/clip.mp4');

      final readPlay = (await read.getPlayParams())!;
      expect(await readPlay.getVolume(), 70);
      expect(await readPlay.isShowController(), isTrue);
      expect(await readPlay.getFitMode(), PdfMediaFitMode.meet);
      expect(await readPlay.isAutoPlay(), isFalse);
      expect(await readPlay.getRepeatCount(), 2.0);
      expect(await (await readPlay.getDuration())!.getSeconds(), 45);

      final readScreen = (await read.getScreenParams())!;
      expect(await readScreen.getWindowType(), PdfMediaWindowType.floating);
      expect(await readScreen.getBackgroundColour(), [0.25, 0.5, 0.75]);
      expect(await readScreen.getOpacity(), 0.5);
      expect(await readScreen.getMonitor(), PdfMonitorSpecifier.primary);
      expect(
          await (await readScreen.getFloatingWindow())!.getSize(), [640, 480]);

      final criteria = (await read.getMustHonourCriteria())!;
      expect(await criteria.getTextCaptions(), isTrue);
      expect(await criteria.getMinimumBandwidth(), 256000);
      expect(await (await criteria.getMinimumBitDepth())!.getDepth(), 16);
      expect(
          await (await criteria.getMinimumScreenSize())!.getSize(), [800, 600]);
      expect(await criteria.getLanguages(), ['en-us']);
      expect(await criteria.getPdfVersionRange(), ['1.5', '1.7']);
    });

    test('A rendition without /N cannot be registered in the name tree',
        () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      await document.appendBlankPage();
      final rendition = PdfMediaRendition.forClip(
          PdfMediaClipData.forFileSpec(PdfFileSpec.url('https://e.org/a.mp4')));
      await expectLater(rendition.registerIn(document), throwsStateError);
      await document.close();
    });

    test('An unrecognised rendition /S reads back as null', () async {
      final dictionary = PdfDictionary()
        ..put(PdfName('Type'), PdfName('Rendition'))
        ..put(PdfName('S'), PdfName('XX'));
      expect(await PdfRendition.read(dictionary), isNull);
    });

    test('An unrecognised media clip /S reads back as null', () async {
      final dictionary = PdfDictionary()
        ..put(PdfName('Type'), PdfName('MediaClip'))
        ..put(PdfName('S'), PdfName('XX'));
      expect(await PdfMediaClip.read(dictionary), isNull);
    });
  });

  group('13.2.1 rendition actions and 13.2.2 screen annotations', () {
    test('A rendition action requires /AN, and /R for operations 0 and 4', () {
      final rendition = PdfMediaRendition.forClip(
          PdfMediaClipData.forFileSpec(PdfFileSpec.url('https://e.org/a.mp4')));
      final screen = PdfScreenAnnotation.fromRect(Rectangle(0, 0, 10, 10));
      expect(
          () => PdfActionRendition.forRendition(
              PdfActionRendition.operationPlayNew,
              screenAnnotation: screen.pdfRepresentation()),
          throwsArgumentError,
          reason: '/R is required when /OP is 0');
      expect(
          () => PdfActionRendition.forRendition(
              PdfActionRendition.operationStop,
              rendition: rendition),
          throwsArgumentError,
          reason: '/AN is required for operations 0 to 4');
      expect(
          () => PdfActionRendition.forRendition(5,
              rendition: rendition,
              screenAnnotation: screen.pdfRepresentation()),
          throwsArgumentError);
      final stop = PdfActionRendition.forRendition(
          PdfActionRendition.operationStop,
          screenAnnotation: screen.pdfRepresentation());
      expect(stop.pdfRepresentation(), isNotNull);
    });

    test('A screen annotation drives a rendition and survives a round trip',
        () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final page = await document.appendBlankPage();

      final clip = PdfMediaClipData.forFileSpec(
          PdfFileSpec.url('https://example.org/spot.mp4'),
          contentType: 'video/mp4')
        ..attachToDocument(document);
      final rendition = PdfMediaRendition.forClip(clip)
        ..setName('spot')
        ..attachToDocument(document);

      final screen = PdfScreenAnnotation.fromRect(Rectangle(0, 0, 320, 240))
        ..setScreenTitle(PdfString('player'));
      screen.pdfRepresentation().attachToDocument(document);
      screen.setRenditionAction(rendition);
      page.pdfRepresentation().put(
          PdfName('Annots'), PdfArray.fromList([screen.pdfRepresentation()]));
      await document.close();

      final reopened = await reopen(bytes.takeBytes());
      addTearDown(reopened.close);
      final annots = await (await reopened.pageAt(1))!
          .pdfRepresentation()
          .arrayEntry(PdfName('Annots'));
      final stored = PdfScreenAnnotation((await annots!.dictionaryEntry(0))!);
      expect(stored.getSubtype().getValue(), 'Screen');
      expect((await stored.getScreenTitle())!.getValue(), 'player');

      final action = PdfActionRendition((await stored.getAction())!);
      expect(await action.getOperation(), PdfActionRendition.operationPlayNew);
      expect(await action.getScreenAnnotation(), isNotNull);

      final played = (await stored.getRendition()) as PdfMediaRendition;
      expect(await played.getName(), 'spot');
      expect(
          await ((await played.getClip()) as PdfMediaClipData).getContentType(),
          'video/mp4');
    });

    test('A screen annotation whose /A is not a rendition action reads null',
        () async {
      final screen = PdfScreenAnnotation.fromRect(Rectangle(0, 0, 10, 10));
      expect(await screen.getRendition(), isNull);
      screen.pdfRepresentation().put(
          PdfName('A'),
          PdfDictionary()
            ..put(PdfName('S'), PdfName('URI'))
            ..put(PdfName('URI'), PdfString('https://example.org/')));
      expect(await screen.getRendition(), isNull);
    });
  });
}
