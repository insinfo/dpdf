import 'dart:typed_data';

import 'package:dpdf/dpdf.dart';
import 'package:test/test.dart';

Uint8List samples(int length) =>
    Uint8List.fromList(List<int>.generate(length, (i) => i & 0xFF));

Future<PdfArray> annotationsOfFirstPage(PdfDocument document) async =>
    (await (await document.pageAt(1))!
        .pdfRepresentation()
        .arrayEntry(PdfName('Annots')))!;

void main() {
  group('13.3 sound objects (Table 294)', () {
    test('A sound object writes /Type, /R and defaults the rest', () async {
      final sound = PdfSound.fromSamples(samples(16), 11025);
      expect(
          (await sound.pdfRepresentation().nameEntry(PdfName('Type')))!
              .getValue(),
          'Sound');
      expect(await sound.getSamplingRate(), 11025);
      expect(await sound.getChannels(), 1, reason: '/C defaults to 1');
      expect(await sound.getBitsPerSample(), 8, reason: '/B defaults to 8');
      expect((await sound.getEncoding()).getValue(), 'Raw',
          reason: '/E defaults to /Raw');
      expect(await sound.getCompression(), isNull);
      expect(await sound.bytesPerFrame(), 1);
    });

    test('Invalid /R, /C, /B and /E are rejected', () {
      expect(() => PdfSound.fromSamples(samples(4), 0), throwsArgumentError);
      final sound = PdfSound.fromSamples(samples(4), 8000);
      expect(() => sound.setChannels(0), throwsArgumentError);
      expect(() => sound.setBitsPerSample(0), throwsArgumentError);
      expect(() => sound.setEncoding(PdfName('MP3')), throwsArgumentError);
    });

    test('The portable formats of 13.3 are recognised', () async {
      expect(
          await PdfSound.fromSamples(samples(4), 22050,
                  channels: 2,
                  bitsPerSample: 16,
                  encoding: PdfSound.encodingSigned)
              .isPortable(),
          isTrue);
      expect(
          await PdfSound.fromSamples(samples(4), 8000,
                  encoding: PdfSound.encodingMuLaw)
              .isPortable(),
          isTrue);
      expect(
          await PdfSound.fromSamples(samples(4), 22050,
                  encoding: PdfSound.encodingMuLaw)
              .isPortable(),
          isFalse,
          reason: 'muLaw shall be 8000 Hz, one channel and 8 bits');
      expect(
          await PdfSound.fromSamples(samples(4), 8000,
                  encoding: PdfSound.encodingRaw)
              .isPortable(),
          isFalse,
          reason: 'Raw shall be 11025 or 22050 samples per channel');
      expect(
          await PdfSound.fromSamples(samples(4), 22050,
                  encoding: PdfSound.encodingALaw)
              .isPortable(),
          isFalse);
    });

    test('A stereo 16-bit frame occupies four bytes', () async {
      final sound = PdfSound.fromSamples(samples(8), 22050,
          channels: 2, bitsPerSample: 16);
      expect(await sound.bytesPerFrame(), 4);
    });

    test('A 4-bit mono sample packs into a single byte frame', () async {
      final sound = PdfSound.fromSamples(samples(4), 11025, bitsPerSample: 4);
      expect(await sound.bytesPerFrame(), 1);
    });

    test('An external sound references /F instead of carrying samples',
        () async {
      final sound =
          PdfSound.fromFile(PdfFileSpec.external('speech.wav'), 22050);
      expect(await (await sound.getFile())!.getFileName(), 'speech.wav');
    });

    test('A sound annotation and a sound action survive a round trip',
        () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final page = await document.appendBlankPage();

      final sound = PdfSound.fromSamples(samples(32), 22050,
          channels: 2, bitsPerSample: 16, encoding: PdfSound.encodingSigned)
        ..setCompression(PdfName('MyCodec'), parameters: PdfNumber(3))
        ..attachToDocument(document);

      final annotation =
          PdfSoundAnnotation.forSound(Rectangle(10, 20, 70, 70), sound)
            ..setIconName(PdfSoundAnnotation.iconMic);
      annotation.pdfRepresentation().attachToDocument(document);
      page.pdfRepresentation().put(PdfName('Annots'),
          PdfArray.fromList([annotation.pdfRepresentation()]));

      final action =
          PdfActionSound.forSound(sound, volume: 0.5, repeat: true, mix: true);
      document
          .rootCatalog()
          .put(PdfName('OpenAction'), action.pdfRepresentation());
      await document.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(bytes.takeBytes()));
      addTearDown(reopened.close);

      final annots = await annotationsOfFirstPage(reopened);
      final storedAnnotation =
          PdfSoundAnnotation((await annots.dictionaryEntry(0))!);
      expect(storedAnnotation.getSubtype().getValue(), 'Sound');
      expect((await storedAnnotation.getIconName()).getValue(), 'Mic');
      final storedSound = (await storedAnnotation.getSoundObject())!;
      expect(await storedSound.getSamplingRate(), 22050);
      expect(await storedSound.getChannels(), 2);
      expect(await storedSound.getBitsPerSample(), 16);
      expect((await storedSound.getEncoding()).getValue(), 'Signed');
      expect((await storedSound.getCompression())!.getValue(), 'MyCodec');
      expect((await storedSound.getSamples())!.length, 32);

      final storedAction = PdfActionSound((await reopened
          .rootCatalog()
          .pdfRepresentation()
          .dictionaryEntry(PdfName('OpenAction')))!);
      expect(await storedAction.getVolume(), 0.5);
      expect(await storedAction.isRepeat(), isTrue);
      expect(await storedAction.isMix(), isTrue);
      expect(await (await storedAction.getSoundObject())!.getSamplingRate(),
          22050);
    });
  });

  group('13.4 movies (Tables 295 and 296)', () {
    test('A movie dictionary requires /F and validates /Rotate', () async {
      final movie = PdfMovie.forFile(PdfFileSpec.external('clip.mov'))
        ..setAspect(320, 240)
        ..setRotation(270);
      expect(await (await movie.getFile())!.getFileName(), 'clip.mov');
      expect(await movie.getAspect(), [320, 240]);
      expect(await movie.getRotation(), 270);
      expect(() => movie.setRotation(45), throwsArgumentError);
      expect(() => movie.setAspect(-1, 10), throwsArgumentError);
    });

    test('/Rotate and /Poster take their Table 295 defaults', () async {
      final movie = PdfMovie.forFile(PdfFileSpec.external('clip.mov'));
      expect(await movie.getRotation(), 0);
      expect(await movie.hasPoster(), isFalse);
      movie.setPosterFromMovie(true);
      expect(await movie.hasPoster(), isTrue);
      movie.setPosterImage(PdfStream.withBytes(samples(4), 0));
      expect(await movie.hasPoster(), isTrue);
      expect(await movie.getPoster(), isA<PdfStream>());
    });

    test('Movie activation defaults match Table 296', () async {
      final activation = PdfMovieActivation.create();
      expect(await activation.getRate(), 1.0);
      expect(await activation.getVolume(), 1.0);
      expect(await activation.isShowControls(), isFalse);
      expect((await activation.getMode()).getValue(), 'Once');
      expect(await activation.isSynchronous(), isFalse);
      expect(await activation.getFloatingWindowPosition(), [0.5, 0.5]);
      expect(activation.isFloatingWindow(), isFalse);
      expect(await activation.getStart(), isNull);
      expect(await activation.getDuration(), isNull);
    });

    test('Movie activation rejects values outside Table 296', () {
      final activation = PdfMovieActivation.create();
      expect(() => activation.setVolume(1.5), throwsArgumentError);
      expect(() => activation.setMode(PdfName('Loop')), throwsArgumentError);
      expect(() => activation.setStart(-1), throwsArgumentError);
      expect(
          () => activation.setFloatingWindowScale(0, 1), throwsArgumentError);
      expect(() => activation.setFloatingWindowPosition(1.5, 0.5),
          throwsArgumentError);
      expect(() => activation.setStartBytes(Uint8List(4)), throwsArgumentError);
      expect(() => activation.setStartInTimeScale(10, 0), throwsArgumentError);
    });

    test('/Start accepts the integer, byte string and time scale forms',
        () async {
      final integerForm = PdfMovieActivation.create()..setStart(600);
      expect(await integerForm.getStartTime(), 600);
      expect(await integerForm.getStartTimeScale(), isNull);

      final scaledForm = PdfMovieActivation.create()
        ..setStartInTimeScale(1200, 600);
      expect(await scaledForm.getStartTime(), 1200);
      expect(await scaledForm.getStartTimeScale(), 600);

      final byteForm = PdfMovieActivation.create()
        ..setStartBytes(Uint8List.fromList([0, 0, 0, 0, 0, 0, 1, 0]));
      expect(await byteForm.getStartTime(), 256,
          reason: 'the string is a 64-bit integer, most significant byte '
              'first');
    });

    test('The floating window size is (numerator/denominator) x Aspect',
        () async {
      final movie = PdfMovie.forFile(PdfFileSpec.external('clip.mov'))
        ..setAspect(320, 240);
      final activation = PdfMovieActivation.create()
        ..setFloatingWindowScale(3, 2);
      expect(activation.isFloatingWindow(), isTrue);
      expect(await activation.floatingWindowSize(movie), [480.0, 360.0]);
      expect(
          await PdfMovieActivation.create().floatingWindowSize(movie), isNull);
    });

    test('A movie annotation and a movie action survive a round trip',
        () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final page = await document.appendBlankPage();

      final movie = PdfMovie.forFile(PdfFileSpec.external('trailer.mov'))
        ..setAspect(640, 480)
        ..setRotation(90)
        ..setPosterFromMovie(true)
        ..attachToDocument(document);

      final activation = PdfMovieActivation.create()
        ..setStartInTimeScale(3000, 600)
        ..setDuration(9000)
        ..setRate(-1.5)
        ..setVolume(-0.25)
        ..setShowControls(true)
        ..setMode(PdfMovieActivation.modePalindrome)
        ..setSynchronous(true)
        ..setFloatingWindowScale(1, 2)
        ..setFloatingWindowPosition(0.25, 0.75);

      final annotation =
          PdfMovieAnnotation.forMovie(Rectangle(0, 0, 200, 150), movie)
            ..setMovieTitle(PdfString('trailer'))
            ..setActivationParameters(activation);
      annotation.pdfRepresentation().attachToDocument(document);
      page.pdfRepresentation().put(PdfName('Annots'),
          PdfArray.fromList([annotation.pdfRepresentation()]));

      final action = PdfActionMovie.forAnnotation(annotation,
          operation: PdfActionMovie.operationResume);
      document
          .rootCatalog()
          .put(PdfName('OpenAction'), action.pdfRepresentation());
      await document.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(bytes.takeBytes()));
      addTearDown(reopened.close);

      final annots = await annotationsOfFirstPage(reopened);
      final stored = PdfMovieAnnotation((await annots.dictionaryEntry(0))!);
      expect(stored.getSubtype().getValue(), 'Movie');
      expect((await stored.getMovieTitle())!.getValue(), 'trailer');

      final storedMovie = (await stored.getMovieObject())!;
      expect(await (await storedMovie.getFile())!.getFileName(), 'trailer.mov');
      expect(await storedMovie.getAspect(), [640, 480]);
      expect(await storedMovie.getRotation(), 90);
      expect(await storedMovie.hasPoster(), isTrue);

      final storedActivation = (await stored.getActivationParameters())!;
      expect(await storedActivation.getStartTime(), 3000);
      expect(await storedActivation.getStartTimeScale(), 600);
      expect(await storedActivation.getDurationTime(), 9000);
      expect(await storedActivation.getRate(), -1.5);
      expect(await storedActivation.getVolume(), -0.25);
      expect(await storedActivation.isShowControls(), isTrue);
      expect((await storedActivation.getMode()).getValue(), 'Palindrome');
      expect(await storedActivation.isSynchronous(), isTrue);
      expect(await storedActivation.getFloatingWindowScale(), [1, 2]);
      expect(await storedActivation.getFloatingWindowPosition(), [0.25, 0.75]);
      expect(await storedActivation.floatingWindowSize(storedMovie),
          [320.0, 240.0]);
      expect(await stored.isPlayOnActivation(), isTrue,
          reason: 'an activation dictionary implies playback');

      final storedAction = PdfActionMovie((await reopened
          .rootCatalog()
          .pdfRepresentation()
          .dictionaryEntry(PdfName('OpenAction')))!);
      expect((await storedAction.getOperation()).getValue(), 'Resume');
      expect(
          (await (await storedAction.getMovieAnnotation())!.getMovieTitle())!
              .getValue(),
          'trailer');
    });

    test('The boolean form of the movie annotation /A is honoured', () async {
      final movie = PdfMovie.forFile(PdfFileSpec.external('clip.mov'));
      final annotation =
          PdfMovieAnnotation.forMovie(Rectangle(0, 0, 10, 10), movie)
            ..setPlayOnActivation(false);
      expect(await annotation.isPlayOnActivation(), isFalse);
      expect(await annotation.getActivationParameters(), isNull);
    });
  });
}
