import 'dart:typed_data';

import '../pdf_name.dart';
import '../pdf_number.dart';
import '../pdf_object.dart';
import '../pdf_object_wrapper.dart';
import '../pdf_stream.dart';
import '../filespec/pdf_file_spec.dart';

/// Sound object.
///
/// See ISO 32000-1:2008, 13.3 "Sounds", Table 294. A sound object is a stream
/// whose sample data is stored most significant bits first, with the samples
/// of a stereophonic sound interleaved left channel first.
class PdfSound extends PdfObjectWrapper<PdfStream> {
  /// `/Type /Sound`.
  static final PdfName typeValue = PdfName.sound;

  /// `/E /Raw`: unspecified or unsigned values in the range 0 to 2^B - 1.
  static final PdfName encodingRaw = PdfName.intern('Raw');

  /// `/E /Signed`: twos-complement values.
  static final PdfName encodingSigned = PdfName.intern('Signed');

  /// `/E /muLaw`: mu-law encoded samples.
  static final PdfName encodingMuLaw = PdfName.intern('muLaw');

  /// `/E /ALaw`: A-law encoded samples.
  static final PdfName encodingALaw = PdfName.intern('ALaw');

  static final Set<String> _encodings = {
    encodingRaw.getValue(),
    encodingSigned.getValue(),
    encodingMuLaw.getValue(),
    encodingALaw.getValue(),
  };

  static final PdfName _co = PdfName.intern('CO');
  static final PdfName _cp = PdfName.intern('CP');

  PdfSound(super.pdfObject);

  /// Creates a sound object holding [samples].
  ///
  /// `/R`, the sampling rate, is the only required entry of Table 294;
  /// `/C`, `/B` and `/E` default to 1 channel, 8 bits and `/Raw`.
  PdfSound.fromSamples(Uint8List samples, double samplingRate,
      {int? channels,
      int? bitsPerSample,
      PdfName? encoding,
      int compressionLevel = 0})
      : super(PdfStream.withBytes(samples, compressionLevel)) {
    _initialise(samplingRate, channels, bitsPerSample, encoding);
  }

  /// Creates a sound object whose samples live in the external, self-describing
  /// file [file]. 13.3 says such a file needs no further description in the
  /// PDF, so `/C`, `/B` and `/E` are optional here too.
  PdfSound.fromFile(PdfFileSpec file, double samplingRate,
      {int? channels, int? bitsPerSample, PdfName? encoding})
      : super(PdfStream()) {
    pdfRepresentation().put(PdfName.f, file.pdfRepresentation());
    _initialise(samplingRate, channels, bitsPerSample, encoding);
  }

  void _initialise(double samplingRate, int? channels, int? bitsPerSample,
      PdfName? encoding) {
    pdfRepresentation().put(PdfName.type, typeValue);
    setSamplingRate(samplingRate);
    if (channels != null) setChannels(channels);
    if (bitsPerSample != null) setBitsPerSample(bitsPerSample);
    if (encoding != null) setEncoding(encoding);
  }

  /// Sound objects are referenced from annotations and actions, so they are
  /// stored indirectly.
  @override
  bool requiresIndirectStorage() => true;

  /// Sets `/R`, the sampling rate in samples per second.
  PdfSound setSamplingRate(double samplingRate) {
    if (samplingRate.isNaN || samplingRate <= 0) {
      throw ArgumentError.value(samplingRate, 'samplingRate',
          'Sound /R shall be a positive sampling rate (Table 294)');
    }
    pdfRepresentation().put(PdfName.r, PdfNumber(samplingRate));
    return this;
  }

  /// Gets `/R`.
  Future<double?> getSamplingRate() async =>
      (await pdfRepresentation().numberEntry(PdfName.r))?.getValue();

  /// Sets `/C`, the number of sound channels.
  PdfSound setChannels(int channels) {
    if (channels < 1) {
      throw ArgumentError.value(channels, 'channels',
          'Sound /C shall be at least one channel (Table 294)');
    }
    pdfRepresentation().put(PdfName.c, PdfNumber.fromInt(channels));
    return this;
  }

  /// Gets `/C`; the default is 1 per Table 294.
  Future<int> getChannels() async =>
      await pdfRepresentation().integerEntry(PdfName.c) ?? 1;

  /// Sets `/B`, the number of bits per sample value per channel.
  PdfSound setBitsPerSample(int bits) {
    if (bits < 1) {
      throw ArgumentError.value(bits, 'bits',
          'Sound /B shall be at least one bit per sample (Table 294)');
    }
    pdfRepresentation().put(PdfName.b, PdfNumber.fromInt(bits));
    return this;
  }

  /// Gets `/B`; the default is 8 per Table 294.
  Future<int> getBitsPerSample() async =>
      await pdfRepresentation().integerEntry(PdfName.b) ?? 8;

  /// Sets `/E`, the encoding format of the sample data.
  PdfSound setEncoding(PdfName encoding) {
    if (!_encodings.contains(encoding.getValue())) {
      throw ArgumentError.value(encoding, 'encoding',
          'Sound /E shall be /Raw, /Signed, /muLaw or /ALaw (Table 294)');
    }
    pdfRepresentation().put(PdfName.intern('E'), encoding);
    return this;
  }

  /// Gets `/E`; the default is `/Raw` per Table 294.
  Future<PdfName> getEncoding() async =>
      await pdfRepresentation().nameEntry(PdfName.intern('E')) ?? encodingRaw;

  /// Sets `/CO`, the sound compression format, and optionally `/CP`, its
  /// parameters. Table 294 defines no standard values for either entry.
  PdfSound setCompression(PdfName format, {PdfObject? parameters}) {
    pdfRepresentation().put(_co, format);
    if (parameters != null) pdfRepresentation().put(_cp, parameters);
    return this;
  }

  /// Gets `/CO`; when absent, the sample data is uncompressed waveform data.
  Future<PdfName?> getCompression() async =>
      await pdfRepresentation().nameEntry(_co);

  /// Gets `/CP` as written.
  Future<PdfObject?> getCompressionParameters() async =>
      await pdfRepresentation().get(_cp, true);

  /// Gets `/F`, the external sound file, when the samples are not embedded.
  Future<PdfFileSpec?> getFile() async {
    final dictionary = await pdfRepresentation().dictionaryEntry(PdfName.f);
    return dictionary == null ? null : PdfFileSpec(dictionary);
  }

  /// Gets the decoded sample bytes of an embedded sound.
  Future<Uint8List?> getSamples() async => await pdfRepresentation().getBytes();

  /// Reports whether the sound uses one of the formats 13.3 asks conforming
  /// readers to support: `/R` of 8000, 11025 or 22050, `/C` of 1 or 2, `/B`
  /// of 8 or 16 and `/E` of `/Raw`, `/Signed` or `/muLaw`, with the extra
  /// restriction that `/muLaw` implies 8000 Hz, one channel and 8 bits, while
  /// `/Raw` and `/Signed` imply 11025 or 22050 Hz.
  Future<bool> isPortable() async {
    final rate = await getSamplingRate();
    final channels = await getChannels();
    final bits = await getBitsPerSample();
    final encoding = (await getEncoding()).getValue();
    if (rate == null) return false;
    if (channels != 1 && channels != 2) return false;
    if (bits != 8 && bits != 16) return false;
    if (encoding == encodingMuLaw.getValue()) {
      return rate == 8000 && channels == 1 && bits == 8;
    }
    if (encoding == encodingRaw.getValue() ||
        encoding == encodingSigned.getValue()) {
      return rate == 11025 || rate == 22050;
    }
    return false;
  }

  /// The number of bytes one sample frame occupies, that is one sample for
  /// every channel, rounded up to whole bytes as 13.3 describes for samples
  /// packed across byte boundaries.
  Future<int> bytesPerFrame() async {
    final bits = (await getBitsPerSample()) * (await getChannels());
    return (bits + 7) ~/ 8;
  }

  /// Reads a sound object out of [object], accepting the stream form of
  /// Table 294 and rejecting anything else.
  static PdfSound? read(PdfObject? object) {
    if (object is PdfStream) return PdfSound(object);
    if (object is PdfIndirectReference) {
      return read(object.targetObjectSync());
    }
    return null;
  }
}
