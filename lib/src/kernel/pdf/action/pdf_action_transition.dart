import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'pdf_action.dart';

/// Transition action, updating the display using a transition dictionary.
///
/// See ISO 32000-1:2008, 12.6.4.14, Table 215.
class PdfActionTransition extends PdfAction {
  PdfActionTransition(super.pdfObject);

  /// Creates a `/Trans` action. `/Trans` is required by Table 215.
  PdfActionTransition.create(PdfDictionary transition)
      : super.ofType(PdfName.intern('Trans')) {
    setTransition(transition);
  }

  /// Sets `/Trans`, the transition dictionary (Table 162).
  PdfActionTransition setTransition(PdfDictionary transition) {
    transition.put(PdfName.type, PdfName.intern('Trans'));
    pdfRepresentation().put(PdfName.intern('Trans'), transition);
    return this;
  }

  /// Gets `/Trans`.
  Future<PdfDictionary?> getTransition() async =>
      await pdfRepresentation().dictionaryEntry(PdfName.intern('Trans'));
}

/// Transition styles of ISO 32000-1:2008, 12.4.4.1, Table 162.
abstract final class PdfTransitionStyle {
  static final PdfName split = PdfName.intern('Split');
  static final PdfName blinds = PdfName.intern('Blinds');
  static final PdfName box = PdfName.intern('Box');
  static final PdfName wipe = PdfName.intern('Wipe');
  static final PdfName dissolve = PdfName.intern('Dissolve');
  static final PdfName glitter = PdfName.intern('Glitter');
  static final PdfName replace = PdfName.intern('R');
  static final PdfName fly = PdfName.intern('Fly');
  static final PdfName push = PdfName.intern('Push');
  static final PdfName cover = PdfName.intern('Cover');
  static final PdfName uncover = PdfName.intern('Uncover');
  static final PdfName fade = PdfName.intern('Fade');

  /// Builds a transition dictionary with `/Type /Trans` and `/S` set to
  /// [style], optionally carrying `/D` (duration in seconds), `/Dm`, `/M`
  /// and `/Di` (Table 162).
  static PdfDictionary build(PdfName style,
      {double? duration, PdfName? dimension, PdfName? motion, int? direction}) {
    final dictionary = PdfDictionary();
    dictionary.put(PdfName.type, PdfName.intern('Trans'));
    dictionary.put(PdfName.s, style);
    if (duration != null) {
      dictionary.put(PdfName.d, PdfNumber(duration));
    }
    if (dimension != null) {
      dictionary.put(PdfName.intern('Dm'), dimension);
    }
    if (motion != null) {
      dictionary.put(PdfName.m, motion);
    }
    if (direction != null) {
      dictionary.put(PdfName.intern('Di'), PdfNumber.fromInt(direction));
    }
    return dictionary;
  }
}
