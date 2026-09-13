import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_boolean.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'pdf_action.dart';

/// Set-OCG-state action, setting the state of optional content groups.
///
/// See ISO 32000-1:2008, 12.6.4.12, Table 213.
class PdfActionSetOcgState extends PdfAction {
  /// Sets the state of subsequent groups to ON.
  static final PdfName on = PdfName.intern('ON');

  /// Sets the state of subsequent groups to OFF.
  static final PdfName off = PdfName.intern('OFF');

  /// Reverses the state of subsequent groups.
  static final PdfName toggle = PdfName.intern('Toggle');

  PdfActionSetOcgState(super.pdfObject);

  /// Creates a `/SetOCGState` action with an empty `/State` array.
  PdfActionSetOcgState.create({bool? preserveRadioButtons})
      : super.ofType(PdfName.intern('SetOCGState')) {
    pdfRepresentation().put(PdfName.intern('State'), PdfArray());
    if (preserveRadioButtons != null) {
      setPreserveRadioButtons(preserveRadioButtons);
    }
  }

  /// Appends a `name groups...` sequence to `/State`. The array is processed
  /// from left to right, each name applying to the groups that follow it.
  Future<PdfActionSetOcgState> addStateSequence(
      PdfName state, List<PdfDictionary> groups) async {
    if (state != on && state != off && state != toggle) {
      throw ArgumentError.value(state, 'state',
          'SetOCGState sequences start with /ON, /OFF or /Toggle');
    }
    if (groups.isEmpty) {
      throw ArgumentError.value(groups, 'groups',
          'Each /State sequence shall be followed by at least one group');
    }
    var array = await pdfRepresentation().arrayEntry(PdfName.intern('State'));
    if (array == null) {
      array = PdfArray();
      pdfRepresentation().put(PdfName.intern('State'), array);
    }
    array.add(state);
    for (final group in groups) {
      array.add(group);
    }
    markChanged();
    return this;
  }

  /// Gets `/State` as written.
  Future<PdfArray?> getState() async =>
      await pdfRepresentation().arrayEntry(PdfName.intern('State'));

  /// Sets `/PreserveRB`.
  PdfActionSetOcgState setPreserveRadioButtons(bool preserve) {
    pdfRepresentation().put(PdfName.intern('PreserveRB'), PdfBoolean(preserve));
    return this;
  }

  /// Gets `/PreserveRB`; the default is true per Table 213.
  Future<bool> getPreserveRadioButtons() async =>
      (await pdfRepresentation().booleanEntry(PdfName.intern('PreserveRB')))
          ?.getValue() ??
      true;
}
