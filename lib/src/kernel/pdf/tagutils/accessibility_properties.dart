import '../pdf_string.dart';
import '../pdf_name.dart';
import '../tagging/pdf_namespace.dart';
import '../tagging/pdf_struct_elem.dart';
import 'pdf_structure_attributes.dart';

/// What a layout element wants its structure element to say.
///
/// This is the accessibility half of Table 323 plus the attribute objects of
/// 14.7.5: a role, the natural language of the text, the alternate
/// description, the expanded form of an abbreviation, the replacement text,
/// a title, an element identifier and any number of attribute objects.
/// [applyTo] writes all of it onto a [PdfStructElem].
class AccessibilityProperties {
  String? _role;
  String? _language;
  String? _alternateDescription;
  String? _expansion;
  String? _actualText;
  String? _title;
  String? _structureElementId;
  PdfNamespace? _namespace;
  final List<PdfStructureAttributes> _attributes = [];
  final List<String> _attributeClasses = [];

  AccessibilityProperties();

  /// The structure type the element should carry in /S.
  String? getRole() => _role;

  void setRole(String? role) {
    _role = role;
  }

  /// The /Lang entry: the natural language of the text in the element.
  String? getLanguage() => _language;

  void setLanguage(String? language) {
    _language = language;
  }

  /// The /Alt entry: a description of the element for readers that cannot
  /// render its content.
  String? getAlternateDescription() => _alternateDescription;

  void setAlternateDescription(String? description) {
    _alternateDescription = description;
  }

  /// The /E entry: the expanded form of an abbreviation.
  String? getExpansion() => _expansion;

  void setExpansion(String? expansion) {
    _expansion = expansion;
  }

  /// The /ActualText entry: an exact textual replacement for the content.
  String? getActualText() => _actualText;

  void setActualText(String? actualText) {
    _actualText = actualText;
  }

  /// The /T entry: a human-readable title for this element.
  String? getTitle() => _title;

  void setTitle(String? title) {
    _title = title;
  }

  /// The /ID entry: an identifier unique across the structure hierarchy.
  String? getStructureElementId() => _structureElementId;

  void setStructureElementId(String? id) {
    _structureElementId = id;
  }

  /// The namespace the role belongs to (PDF 2.0 /NS).
  PdfNamespace? getNamespace() => _namespace;

  void setNamespace(PdfNamespace? namespace) {
    _namespace = namespace;
  }

  /// The attribute objects to attach through /A (14.7.5.1).
  List<PdfStructureAttributes> getAttributesList() =>
      List.unmodifiable(_attributes);

  void addAttributes(PdfStructureAttributes attributes) {
    _attributes.add(attributes);
  }

  void clearAttributes() {
    _attributes.clear();
  }

  /// The attribute class names to attach through /C (14.7.5.2).
  List<String> getAttributeClasses() => List.unmodifiable(_attributeClasses);

  void addAttributeClass(String className) {
    _attributeClasses.add(className);
  }

  /// Writes everything that was set onto [element]; entries left null are not
  /// touched, so an element can be described in several passes.
  Future<void> applyTo(PdfStructElem element) async {
    final role = _role;
    if (role != null) element.setRole(PdfName(role));
    final namespace = _namespace;
    if (namespace != null) element.setNamespace(namespace);
    final language = _language;
    if (language != null) element.setLang(PdfString(language));
    final alternate = _alternateDescription;
    if (alternate != null) element.setAlt(PdfString(alternate));
    final expansion = _expansion;
    if (expansion != null) element.setE(PdfString(expansion));
    final actualText = _actualText;
    if (actualText != null) element.setActualText(PdfString(actualText));
    final title = _title;
    if (title != null) element.setTitle(PdfString(title));
    final id = _structureElementId;
    if (id != null) await element.setStructureElementId(PdfString(id));
    for (final attributes in _attributes) {
      await element.addAttribute(attributes.pdfRepresentation());
    }
    for (final className in _attributeClasses) {
      await element.addAttributeClass(PdfName(className));
    }
  }
}
