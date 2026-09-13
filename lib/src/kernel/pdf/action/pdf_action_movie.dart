import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'package:dpdf/src/kernel/pdf/annot/pdf_media_annotations.dart';
import 'pdf_action.dart';

/// Movie action, controlling the playing of a movie annotation.
///
/// See ISO 32000-1:2008, 12.6.4.9, Table 209.
class PdfActionMovie extends PdfAction {
  /// `/Operation` value: start playing the movie.
  static final PdfName operationPlay = PdfName.intern('Play');

  /// `/Operation` value: stop playing the movie.
  static final PdfName operationStop = PdfName.intern('Stop');

  /// `/Operation` value: pause a playing movie.
  static final PdfName operationPause = PdfName.intern('Pause');

  /// `/Operation` value: resume a paused movie.
  static final PdfName operationResume = PdfName.intern('Resume');

  static final Set<String> _operations = {
    operationPlay.getValue(),
    operationStop.getValue(),
    operationPause.getValue(),
    operationResume.getValue(),
  };

  PdfActionMovie(super.pdfObject);

  /// Creates a `/Movie` action targeting a movie annotation dictionary.
  /// Table 209 allows either `/Annotation` or `/T`, but not both.
  PdfActionMovie.byAnnotation(PdfDictionary annotation, {PdfName? operation})
      : super.ofType(PdfName.intern('Movie')) {
    pdfRepresentation().put(PdfName.intern('Annotation'), annotation);
    if (operation != null) setOperation(operation);
  }

  /// Creates a `/Movie` action targeting the movie annotation whose `/T`
  /// title is [title].
  PdfActionMovie.byTitle(String title, {PdfName? operation})
      : super.ofType(PdfName.intern('Movie')) {
    pdfRepresentation().put(PdfName.t, PdfString(title));
    if (operation != null) setOperation(operation);
  }

  /// Sets `/Operation`.
  PdfActionMovie setOperation(PdfName operation) {
    if (!_operations.contains(operation.getValue())) {
      throw ArgumentError.value(operation, 'operation',
          'Movie /Operation shall be /Play, /Stop, /Pause or /Resume');
    }
    pdfRepresentation().put(PdfName.intern('Operation'), operation);
    return this;
  }

  /// Gets `/Operation`; the default is [operationPlay] per Table 209.
  Future<PdfName> getOperation() async =>
      await pdfRepresentation().nameEntry(PdfName.intern('Operation')) ??
      operationPlay;

  /// Gets `/Annotation`.
  Future<PdfDictionary?> getAnnotation() async =>
      await pdfRepresentation().dictionaryEntry(PdfName.intern('Annotation'));

  /// Gets `/T`, the movie annotation title.
  Future<String?> getMovieTitle() async =>
      (await pdfRepresentation().stringEntry(PdfName.t))?.getValue();

  /// Creates a `/Movie` action targeting [annotation]. Table 209 allows
  /// either `/Annotation` or `/T`, but not both.
  factory PdfActionMovie.forAnnotation(PdfMovieAnnotation annotation,
          {PdfName? operation}) =>
      PdfActionMovie.byAnnotation(annotation.pdfRepresentation(),
          operation: operation);

  /// Gets `/Annotation` as a movie annotation.
  Future<PdfMovieAnnotation?> getMovieAnnotation() async {
    final dictionary = await getAnnotation();
    return dictionary == null ? null : PdfMovieAnnotation(dictionary);
  }
}
