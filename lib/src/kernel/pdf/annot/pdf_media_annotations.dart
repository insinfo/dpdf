import '../pdf_boolean.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_object.dart';
import '../pdf_stream.dart';
import '../pdf_string.dart';

import '../action/pdf_action.dart';
import 'pdf_annotation.dart';
import 'pdf_markup_annotation.dart';

/// Sound annotation.
///
/// See ISO 32000-1:2008, 12.5.6.16, Table 185.
class PdfSoundAnnotation extends PdfMarkupAnnotation {
  /// Standard icon names required by Table 185.
  static final PdfName iconSpeaker = PdfName.intern('Speaker');
  static final PdfName iconMic = PdfName.intern('Mic');

  PdfSoundAnnotation(super.pdfObject);

  /// Creates a sound annotation. `/Sound` is required by Table 185.
  PdfSoundAnnotation.fromRect(super.rect, PdfStream sound) : super.fromRect() {
    put(PdfName.subtype, PdfName.sound);
    setSound(sound);
  }

  @override
  PdfName getSubtype() => PdfName.sound;

  /// Sets `/Sound`, the sound object played when the annotation is activated.
  PdfSoundAnnotation setSound(PdfStream sound) {
    put(PdfName.sound, sound);
    return this;
  }

  /// Gets `/Sound`.
  Future<PdfStream?> getSound() async =>
      await pdfRepresentation().streamEntry(PdfName.sound);

  /// Sets `/Name`, the icon shown for the sound.
  PdfSoundAnnotation setIconName(PdfName name) {
    put(PdfName.name, name);
    return this;
  }

  /// Gets `/Name`; the default is `/Speaker` per Table 185.
  Future<PdfName> getIconName() async =>
      await pdfRepresentation().nameEntry(PdfName.name) ?? iconSpeaker;
}

/// Movie annotation.
///
/// See ISO 32000-1:2008, 12.5.6.17, Table 186. A movie annotation is not a
/// markup annotation (Table 169).
class PdfMovieAnnotation extends PdfAnnotation {
  PdfMovieAnnotation(super.pdfObject);

  /// Creates a movie annotation. `/Movie` is required by Table 186.
  PdfMovieAnnotation.fromRect(super.rect, PdfDictionary movie)
      : super.fromRect() {
    put(PdfName.subtype, PdfName.intern('Movie'));
    setMovie(movie);
  }

  @override
  PdfName getSubtype() => PdfName.intern('Movie');

  /// Sets `/T`, the title used by movie actions to reference the annotation.
  PdfMovieAnnotation setMovieTitle(PdfString title) {
    put(PdfName.t, title);
    return this;
  }

  /// Gets `/T`.
  Future<PdfString?> getMovieTitle() async =>
      await pdfRepresentation().stringEntry(PdfName.t);

  /// Sets `/Movie`, the movie dictionary.
  PdfMovieAnnotation setMovie(PdfDictionary movie) {
    put(PdfName.intern('Movie'), movie);
    return this;
  }

  /// Gets `/Movie`.
  Future<PdfDictionary?> getMovie() async =>
      await pdfRepresentation().dictionaryEntry(PdfName.intern('Movie'));

  /// Sets `/A` to the boolean form of Table 186: true plays the movie with
  /// default activation parameters, false suppresses playback.
  PdfMovieAnnotation setPlayOnActivation(bool play) {
    put(PdfName.a, PdfBoolean(play));
    return this;
  }

  /// Sets `/A` to a movie activation dictionary.
  PdfMovieAnnotation setActivation(PdfDictionary activation) {
    put(PdfName.a, activation);
    return this;
  }

  /// Gets `/A` as written; the value is either a boolean or a dictionary.
  Future<PdfObject?> getActivation() async =>
      await pdfRepresentation().get(PdfName.a, true);
}

/// Screen annotation, a region on which media clips may be played.
///
/// See ISO 32000-1:2008, 12.5.6.18, Table 187.
class PdfScreenAnnotation extends PdfAnnotation {
  PdfScreenAnnotation(super.pdfObject);

  PdfScreenAnnotation.fromRect(super.rect) : super.fromRect() {
    put(PdfName.subtype, PdfName.screen);
  }

  @override
  PdfName getSubtype() => PdfName.screen;

  /// Sets `/T`, the title of the screen annotation.
  PdfScreenAnnotation setScreenTitle(PdfString title) {
    put(PdfName.t, title);
    return this;
  }

  /// Gets `/T`.
  Future<PdfString?> getScreenTitle() async =>
      await pdfRepresentation().stringEntry(PdfName.t);

  /// Sets `/MK`, the appearance characteristics dictionary (Table 189).
  PdfScreenAnnotation setAppearanceCharacteristics(PdfDictionary mk) {
    put(PdfName.mk, mk);
    return this;
  }

  /// Gets `/MK`.
  Future<PdfDictionary?> getAppearanceCharacteristics() async =>
      await pdfRepresentation().dictionaryEntry(PdfName.mk);

  /// Sets `/A`, the action performed when the annotation is activated.
  PdfScreenAnnotation setAction(PdfAction action) {
    put(PdfName.a, action.pdfRepresentation());
    return this;
  }

  /// Gets `/A`.
  Future<PdfDictionary?> getAction() async =>
      await pdfRepresentation().dictionaryEntry(PdfName.a);

  /// Sets an entry of `/AA`, the additional-actions dictionary (Table 194).
  Future<PdfScreenAnnotation> setAdditionalAction(
      PdfName trigger, PdfAction action) async {
    await PdfAction.setAdditionalAction(this, trigger, action);
    return this;
  }

  /// Gets `/AA`.
  Future<PdfDictionary?> getAdditionalActions() async =>
      await pdfRepresentation().dictionaryEntry(PdfName.aa);
}
