import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object_wrapper.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';

import 'pdf_action_form.dart';
import 'pdf_action_goto.dart';
import 'pdf_action_goto_3d_view.dart';
import 'pdf_action_goto_embedded.dart';
import 'pdf_action_goto_remote.dart';
import 'pdf_action_hide.dart';
import 'pdf_action_javascript.dart';
import 'pdf_action_launch.dart';
import 'pdf_action_movie.dart';
import 'pdf_action_named.dart';
import 'pdf_action_rendition.dart';
import 'pdf_action_set_ocg_state.dart';
import 'pdf_action_sound.dart';
import 'pdf_action_thread.dart';
import 'pdf_action_transition.dart';
import 'pdf_action_uri.dart';

/// Represents a PDF Action.
///
/// See ISO 32000-1:2008, 12.6.2 "Action Dictionaries", Table 193.
class PdfAction extends PdfObjectWrapper<PdfDictionary> {
  PdfAction(super.pdfObject);

  /// Creates an action dictionary carrying `/Type /Action` and the given
  /// `/S` action type (Table 193).
  PdfAction.ofType(PdfName actionType) : super(PdfDictionary()) {
    pdfRepresentation().put(PdfName.type, PdfName.action);
    pdfRepresentation().put(PdfName.s, actionType);
  }

  @override
  bool requiresIndirectStorage() => true;

  /// Gets `/S`, the action type.
  Future<PdfName?> getActionType() async =>
      await pdfRepresentation().nameEntry(PdfName.s);

  /// Appends [next] to `/Next`, the action or sequence of actions performed
  /// after this one (Table 193). Repeated calls build the array form.
  Future<PdfAction> addNextAction(PdfAction next) async {
    final existing = await pdfRepresentation().get(PdfName.next, true);
    if (existing == null) {
      pdfRepresentation().put(PdfName.next, next.pdfRepresentation());
    } else if (existing is PdfArray) {
      existing.add(next.pdfRepresentation());
    } else {
      pdfRepresentation().put(PdfName.next,
          PdfArray.fromList([existing, next.pdfRepresentation()]));
    }
    markChanged();
    return this;
  }

  /// Gets `/Next` as a list, flattening the single-dictionary form.
  Future<List<PdfDictionary>> getNextActions() async {
    final next = await pdfRepresentation().get(PdfName.next, true);
    if (next == null) return const [];
    if (next is PdfArray) {
      final result = <PdfDictionary>[];
      for (var i = 0; i < next.size(); i++) {
        final entry = await next.get(i);
        if (entry is PdfDictionary) result.add(entry);
      }
      return result;
    }
    if (next is PdfDictionary) return [next];
    return const [];
  }

  /// Sets an additional action to the annotation/field.
  static Future<void> setAdditionalAction(
      PdfObjectWrapper<PdfDictionary> wrapper,
      PdfName key,
      PdfAction action) async {
    PdfDictionary? aa = await wrapper
        .pdfRepresentation()
        .dictionaryEntry(PdfName.aa); // AA = Additional Actions
    if (aa == null) {
      aa = PdfDictionary();
      wrapper.pdfRepresentation().put(PdfName.aa, aa);
    }
    aa.put(key, action.pdfRepresentation());
    action.markChanged();
    wrapper.markChanged();
  }

  /// Factory method to create a PdfAction from a dictionary.
  ///
  /// Dispatch follows the `/S` values of Table 198 plus the form actions of
  /// 12.7.5.
  static Future<PdfAction> makeAction(PdfDictionary dictionary) async {
    final s = await dictionary.nameEntry(PdfName.s);
    switch (s?.getValue()) {
      case 'GoTo':
        return PdfActionGoTo(dictionary);
      case 'GoToR':
        return PdfActionGoToRemote(dictionary);
      case 'GoToE':
        return PdfActionGoToEmbedded(dictionary);
      case 'Launch':
        return PdfActionLaunch(dictionary);
      case 'Thread':
        return PdfActionThread(dictionary);
      case 'URI':
        return PdfActionURI(dictionary);
      case 'Sound':
        return PdfActionSound(dictionary);
      case 'Movie':
        return PdfActionMovie(dictionary);
      case 'Hide':
        return PdfActionHide(dictionary);
      case 'Named':
        return PdfActionNamed(dictionary);
      case 'SubmitForm':
        return PdfActionSubmitForm(dictionary);
      case 'ResetForm':
        return PdfActionResetForm(dictionary);
      case 'ImportData':
        return PdfActionImportData(dictionary);
      case 'JavaScript':
        return PdfActionJavaScript(dictionary);
      case 'SetOCGState':
        return PdfActionSetOcgState(dictionary);
      case 'Rendition':
        return PdfActionRendition(dictionary);
      case 'Trans':
        return PdfActionTransition(dictionary);
      case 'GoTo3DView':
        return PdfActionGoTo3DView(dictionary);
    }
    return PdfAction(dictionary);
  }
}

/// Trigger event names of ISO 32000-1:2008, 12.6.3, Tables 194 to 197.
abstract final class PdfAdditionalActionTrigger {
  // Table 194: annotation triggers.
  static final PdfName cursorEnter = PdfName.intern('E');
  static final PdfName cursorExit = PdfName.intern('X');
  static final PdfName mouseDown = PdfName.intern('D');
  static final PdfName mouseUp = PdfName.intern('U');
  static final PdfName focus = PdfName.intern('Fo');
  static final PdfName blur = PdfName.intern('Bl');
  static final PdfName pageOpened = PdfName.intern('PO');
  static final PdfName pageClosed = PdfName.intern('PC');
  static final PdfName pageVisible = PdfName.intern('PV');
  static final PdfName pageInvisible = PdfName.intern('PI');

  // Table 195: page object triggers.
  static final PdfName open = PdfName.intern('O');
  static final PdfName close = PdfName.intern('C');

  // Table 196: form field triggers.
  static final PdfName keystroke = PdfName.intern('K');
  static final PdfName format = PdfName.intern('F');
  static final PdfName validate = PdfName.intern('V');
  static final PdfName calculate = PdfName.intern('C');

  // Table 197: document catalog triggers.
  static final PdfName willClose = PdfName.intern('WC');
  static final PdfName willSave = PdfName.intern('WS');
  static final PdfName didSave = PdfName.intern('DS');
  static final PdfName willPrint = PdfName.intern('WP');
  static final PdfName didPrint = PdfName.intern('DP');
}
