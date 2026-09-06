import '../../kernel/pdf/pdf_dictionary.dart';
import '../../kernel/pdf/pdf_array.dart';
import '../../kernel/pdf/pdf_number.dart';
import '../../kernel/pdf/pdf_name.dart';
import '../../kernel/pdf/pdf_object.dart';
import '../../kernel/pdf/pdf_string.dart';
import '../../commons/pdfcraft_log_manager.dart';
import 'pdf_form_field.dart';

class CraftPdfChoiceFormField extends CraftPdfFormField {
  static const int ffCombo = 1 << 17; // Bit 18
  static const int ffEdit = 1 << 18; // Bit 19
  static const int ffSort = 1 << 19; // Bit 20
  static const int ffMultiSelect = 1 << 21; // Bit 22
  static const int ffDoNotSpellCheck = 1 << 22; // Bit 23
  static const int ffCommitOnSelChange = 1 << 26; // Bit 27

  static final _logger = LogManager.getLoggerByName('PdfChoiceFormField');

  CraftPdfChoiceFormField(CraftPdfDictionary pdfObject) : super(pdfObject);

  @override
  Future<CraftPdfName?> getFormType() async {
    return CraftPdfName.ch;
  }

  void setTopIndex(int index) {
    put(CraftPdfName.ti, CraftPdfNumber(index.toDouble()));
    regenerateField();
  }

  Future<CraftPdfNumber?> getTopIndex() async {
    return pdfRepresentation().numberEntry(CraftPdfName.ti);
  }

  void setIndices(CraftPdfArray indices) {
    put(CraftPdfName.i, indices);
  }

  Future<CraftPdfArray?> getIndices() async {
    return pdfRepresentation().arrayEntry(CraftPdfName.i);
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

  Future<CraftPdfArray> getOptions() async {
    CraftPdfArray? options =
        await pdfRepresentation().arrayEntry(CraftPdfName.opt);
    if (options == null) {
      options = CraftPdfArray();
      put(CraftPdfName.opt, options);
    }
    return options;
  }

  Future<void> setListSelected(List<String> optionValues,
      {bool generateAppearance = true}) async {
    if (optionValues.length > 1 && !(await isMultiSelect())) {
      _logger.logWarning(
          "This field permits one selection, but several values were supplied.");
    }
    CraftPdfArray options = await getOptions();
    CraftPdfArray indices = CraftPdfArray();
    CraftPdfArray values = CraftPdfArray();
    List<String?> optionsNames = await _optionsToUnicodeNames();

    for (String element in optionValues) {
      int index = -1;
      // Prefer exported values; display labels remain accepted for compatibility.
      for (var candidate = 0; candidate < options.size(); candidate++) {
        final option = await options.get(candidate);
        final exported = option is CraftPdfArray ? await option.get(0) : option;
        if (exported is CraftPdfString &&
            exported.decodeMappingText() == element) {
          index = candidate;
          break;
        }
      }
      if (index == -1) index = optionsNames.indexOf(element);
      if (index != -1) {
        indices.add(CraftPdfNumber(index.toDouble()));
        CraftPdfObject? optByIndex = await options.get(index);
        if (optByIndex is CraftPdfString) {
          values.add(optByIndex);
        } else if (optByIndex is CraftPdfArray) {
          CraftPdfObject? val = await optByIndex.get(0);
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
        values.add(CraftPdfString(element));
      }
    }

    if (indices.size() > 0) {
      setIndices(indices);
    } else {
      pdfRepresentation().remove(CraftPdfName.i);
    }

    if (values.size() == 1) {
      put(CraftPdfName.v, await values.get(0) ?? CraftPdfString(''));
    } else {
      put(CraftPdfName.v, values);
    }

    if (generateAppearance) {
      regenerateField();
    }
  }

  Future<List<String?>> _optionsToUnicodeNames() async {
    CraftPdfArray options = await getOptions();
    List<String?> names = [];
    for (int i = 0; i < options.size(); i++) {
      CraftPdfObject? obj = await options.get(i);
      if (obj is CraftPdfString) {
        names.add(obj.decodeMappingText());
      } else if (obj is CraftPdfArray && obj.size() > 1) {
        CraftPdfObject? val = await obj.get(1);
        if (val is CraftPdfString) {
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
