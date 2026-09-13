import 'package:dpdf/src/kernel/pdf/pdf_boolean.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/pdf/multimedia/pdf_sound.dart';
import 'pdf_action.dart';

/// Sound action, playing a sound through the computer's speakers.
///
/// See ISO 32000-1:2008, 12.6.4.8, Table 208.
class PdfActionSound extends PdfAction {
  PdfActionSound(super.pdfObject);

  /// Creates a `/Sound` action. `/Sound` is required by Table 208.
  PdfActionSound.create(PdfStream sound,
      {double? volume, bool? synchronous, bool? repeat, bool? mix})
      : super.ofType(PdfName.sound) {
    setSound(sound);
    if (volume != null) setVolume(volume);
    if (synchronous != null) setSynchronous(synchronous);
    if (repeat != null) setRepeat(repeat);
    if (mix != null) setMix(mix);
  }

  /// Sets `/Sound`, the sound object to play.
  PdfActionSound setSound(PdfStream sound) {
    pdfRepresentation().put(PdfName.sound, sound);
    return this;
  }

  /// Gets `/Sound`.
  Future<PdfStream?> getSound() async =>
      await pdfRepresentation().streamEntry(PdfName.sound);

  /// Sets `/Volume`, in the range -1.0 to 1.0.
  PdfActionSound setVolume(double volume) {
    if (volume < -1 || volume > 1) {
      throw ArgumentError.value(
          volume, 'volume', 'Sound action /Volume shall lie in [-1, 1]');
    }
    pdfRepresentation().put(PdfName.intern('Volume'), PdfNumber(volume));
    return this;
  }

  /// Gets `/Volume`; the default is 1.0 per Table 208.
  Future<double> getVolume() async =>
      (await pdfRepresentation().numberEntry(PdfName.intern('Volume')))
          ?.getValue() ??
      1.0;

  /// Sets `/Synchronous`.
  PdfActionSound setSynchronous(bool synchronous) {
    pdfRepresentation()
        .put(PdfName.intern('Synchronous'), PdfBoolean(synchronous));
    return this;
  }

  /// Gets `/Synchronous`; the default is false per Table 208.
  Future<bool> isSynchronous() async =>
      (await pdfRepresentation().booleanEntry(PdfName.intern('Synchronous')))
          ?.getValue() ??
      false;

  /// Sets `/Repeat`. When present, `/Synchronous` is ignored (Table 208).
  PdfActionSound setRepeat(bool repeat) {
    pdfRepresentation().put(PdfName.intern('Repeat'), PdfBoolean(repeat));
    return this;
  }

  /// Gets `/Repeat`; the default is false per Table 208.
  Future<bool> isRepeat() async =>
      (await pdfRepresentation().booleanEntry(PdfName.intern('Repeat')))
          ?.getValue() ??
      false;

  /// Sets `/Mix`.
  PdfActionSound setMix(bool mix) {
    pdfRepresentation().put(PdfName.intern('Mix'), PdfBoolean(mix));
    return this;
  }

  /// Gets `/Mix`; the default is false per Table 208.
  Future<bool> isMix() async =>
      (await pdfRepresentation().booleanEntry(PdfName.intern('Mix')))
          ?.getValue() ??
      false;

  /// Creates a `/Sound` action playing the sound object of 13.3, Table 294.
  factory PdfActionSound.forSound(PdfSound sound,
          {double? volume, bool? synchronous, bool? repeat, bool? mix}) =>
      PdfActionSound.create(sound.pdfRepresentation(),
          volume: volume, synchronous: synchronous, repeat: repeat, mix: mix);

  /// Gets `/Sound` as the sound object of 13.3, Table 294.
  Future<PdfSound?> getSoundObject() async => PdfSound.read(await getSound());
}
