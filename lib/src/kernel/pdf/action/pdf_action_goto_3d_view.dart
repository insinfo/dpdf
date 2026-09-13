import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'pdf_action.dart';

/// Go-to-3D-view action, setting the view of a 3D annotation.
///
/// See ISO 32000-1:2008, 12.6.4.15, Table 216.
class PdfActionGoTo3DView extends PdfAction {
  /// `/V` name: the first entry of the `/VA` array.
  static final PdfName viewFirst = PdfName.intern('F');

  /// `/V` name: the last entry of the `/VA` array.
  static final PdfName viewLast = PdfName.intern('L');

  /// `/V` name: the next entry of the `/VA` array.
  static final PdfName viewNext = PdfName.intern('N');

  /// `/V` name: the previous entry of the `/VA` array.
  static final PdfName viewPrevious = PdfName.intern('P');

  /// `/V` name: the default entry of the `/VA` array.
  static final PdfName viewDefault = PdfName.intern('D');

  static final Set<String> _viewNames = {
    viewFirst.getValue(),
    viewLast.getValue(),
    viewNext.getValue(),
    viewPrevious.getValue(),
    viewDefault.getValue(),
  };

  PdfActionGoTo3DView(super.pdfObject);

  /// Creates a `/GoTo3DView` action selecting a 3D view dictionary.
  PdfActionGoTo3DView.withViewDictionary(
      PdfDictionary targetAnnotation, PdfDictionary view)
      : super.ofType(PdfName.intern('GoTo3DView')) {
    _setTarget(targetAnnotation);
    pdfRepresentation().put(PdfName.v, view);
  }

  /// Creates a `/GoTo3DView` action selecting the view at [index] of the
  /// `/VA` array in the 3D stream.
  PdfActionGoTo3DView.withViewIndex(PdfDictionary targetAnnotation, int index)
      : super.ofType(PdfName.intern('GoTo3DView')) {
    _setTarget(targetAnnotation);
    pdfRepresentation().put(PdfName.v, PdfNumber.fromInt(index));
  }

  /// Creates a `/GoTo3DView` action selecting the view whose `/IN` entry
  /// matches [name].
  PdfActionGoTo3DView.withViewName(PdfDictionary targetAnnotation, String name)
      : super.ofType(PdfName.intern('GoTo3DView')) {
    _setTarget(targetAnnotation);
    pdfRepresentation().put(PdfName.v, PdfString(name));
  }

  /// Creates a `/GoTo3DView` action selecting one of the predefined view
  /// names of Table 216 ([viewFirst], [viewLast], [viewNext], [viewPrevious]
  /// or [viewDefault]).
  PdfActionGoTo3DView.withPredefinedView(
      PdfDictionary targetAnnotation, PdfName view)
      : super.ofType(PdfName.intern('GoTo3DView')) {
    if (!_viewNames.contains(view.getValue())) {
      throw ArgumentError.value(
          view, 'view', 'GoTo3DView /V names shall be /F, /L, /N, /P or /D');
    }
    _setTarget(targetAnnotation);
    pdfRepresentation().put(PdfName.v, view);
  }

  void _setTarget(PdfDictionary targetAnnotation) {
    pdfRepresentation().put(PdfName.intern('TA'), targetAnnotation);
  }

  /// Gets `/TA`, the target annotation.
  Future<PdfDictionary?> getTargetAnnotation() async =>
      await pdfRepresentation().dictionaryEntry(PdfName.intern('TA'));

  /// Gets `/V` as written.
  Future<PdfObject?> getView() async =>
      await pdfRepresentation().get(PdfName.v, true);
}
