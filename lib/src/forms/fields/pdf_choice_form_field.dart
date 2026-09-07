import '../../kernel/pdf/pdf_array.dart';
import '../../kernel/pdf/pdf_number.dart';
import '../../kernel/pdf/pdf_name.dart';
import '../../kernel/pdf/pdf_object.dart';
import '../../kernel/pdf/pdf_string.dart';
import '../../commons/dpdf_log_manager.dart';
import 'pdf_form_field.dart';

class PdfChoiceFormField extends PdfFormField {
  static const int ffCombo = 1 << 17; // Bit 18
  static const int ffEdit = 1 << 18; // Bit 19
  static const int ffSort = 1 << 19; // Bit 20
  static const int ffMultiSelect = 1 << 21; // Bit 22
  static const int ffDoNotSpellCheck = 1 << 22; // Bit 23
  static const int ffCommitOnSelChange = 1 << 26; // Bit 27

  static final _logger = LogManager.getLoggerByName('PdfChoiceFormField');

  PdfChoiceFormField(super.pdfObject);

  @override
  Future<PdfName?> getFormType() async {
    return PdfName.ch;
  }

  void setTopIndex(int index) {
    put(PdfName.ti, PdfNumber(index.toDouble()));
    regenerateField();
  }

  Future<PdfNumber?> getTopIndex() async {
    return pdfRepresentation().numberEntry(PdfName.ti);
  }

  void setIndices(PdfArray indices) {
    put(PdfName.i, indices);
  }

  Future<PdfArray?> getIndices() async {
    return pdfRepresentation().arrayEntry(PdfName.i);
  }

  Future<bool> isCombo() async {
    return getFieldFlag(ffCombo);
  }

  void setCombo(bool combo) {
    setFieldFlag(ffCombo, combo);
  }

  Future<bool> isEdit() async {
    return getFieldFlag(ffEdit);
  }

  void setEdit(bool edit) {
    setFieldFlag(ffEdit, edit);
  }

  Future<bool> isSort() async {
    return getFieldFlag(ffSort);
  }

  void setSort(bool sort) {
    setFieldFlag(ffSort, sort);
  }

  Future<bool> isMultiSelect() async {
    return getFieldFlag(ffMultiSelect);
  }

  void setMultiSelect(bool multiSelect) {
    setFieldFlag(ffMultiSelect, multiSelect);
  }

  Future<bool> isSpellCheck() async {
    return !(await getFieldFlag(ffDoNotSpellCheck));
  }

  void setSpellCheck(bool spellCheck) {
    setFieldFlag(ffDoNotSpellCheck, !spellCheck);
  }

  Future<bool> isCommitOnSelChange() async {
    return getFieldFlag(ffCommitOnSelChange);
  }

  void setCommitOnSelChange(bool commitOnSelChange) {
    setFieldFlag(ffCommitOnSelChange, commitOnSelChange);
  }

  Future<PdfArray> getOptions() async {
    PdfArray? options = await pdfRepresentation().arrayEntry(PdfName.opt);
    if (options == null) {
      options = PdfArray();
      put(PdfName.opt, options);
    }
    return options;
  }

  Future<void> setListSelected(List<String> optionValues,
      {bool generateAppearance = true}) async {
    if (optionValues.length > 1 && !(await isMultiSelect())) {
      _logger.logWarning(
          "This field permits one selection, but several values were supplied.");
    }
    PdfArray options = await getOptions();
    PdfArray indices = PdfArray();
    PdfArray values = PdfArray();
    List<String?> optionsNames = await _optionsToUnicodeNames();

    for (String element in optionValues) {
      int index = -1;
      // Prefer exported values; display labels remain accepted for compatibility.
      for (var candidate = 0; candidate < options.size(); candidate++) {
        final option = await options.get(candidate);
        final exported = option is PdfArray ? await option.get(0) : option;
        if (exported is PdfString && exported.decodeMappingText() == element) {
          index = candidate;
          break;
        }
      }
      if (index == -1) index = optionsNames.indexOf(element);
      if (index != -1) {
        indices.add(PdfNumber(index.toDouble()));
        PdfObject? optByIndex = await options.get(index);
        if (optByIndex is PdfString) {
          values.add(optByIndex);
        } else if (optByIndex is PdfArray) {
          PdfObject? val = await optByIndex.get(0);
          if (val != null) {
            values.add(val);
          }
        }
      } else {
        bool combo = await isCombo();
        bool edit = await isEdit();
        if (!(combo && edit)) {
          _logger.logWarning(
              "The supplied value does not match any configured option.");
        }
        values.add(PdfString(element));
      }
    }

    if (indices.size() > 0) {
      setIndices(indices);
    } else {
      pdfRepresentation().remove(PdfName.i);
    }

    if (values.size() == 1) {
      put(PdfName.v, await values.get(0) ?? PdfString(''));
    } else {
      put(PdfName.v, values);
    }

    if (generateAppearance) {
      regenerateField();
    }
  }

  Future<List<String?>> _optionsToUnicodeNames() async {
    PdfArray options = await getOptions();
    List<String?> names = [];
    for (int i = 0; i < options.size(); i++) {
      PdfObject? obj = await options.get(i);
      if (obj is PdfString) {
        names.add(obj.decodeMappingText());
      } else if (obj is PdfArray && obj.size() > 1) {
        PdfObject? val = await obj.get(1);
        if (val is PdfString) {
          names.add(val.decodeMappingText());
        } else {
          names.add(null);
        }
      } else {
        names.add(null);
      }
    }
    return names;
  }
}
