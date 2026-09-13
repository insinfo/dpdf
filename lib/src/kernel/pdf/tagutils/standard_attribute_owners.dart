/// The owners ISO 32000-1:2008 defines for attribute objects
/// (14.8.5.2, Table 341).
///
/// The /O entry of an attribute object names the product that owns the
/// attributes it carries, and thereby fixes how they are interpreted. An
/// attribute object owned by an export format overrides the corresponding
/// attribute owned by [layout], [list], [printField] or [table], but only
/// while exporting to that format.
class StandardAttributeOwners {
  StandardAttributeOwners._();

  /// Attributes governing the layout of content (14.8.5.4).
  static const String layout = 'Layout';

  /// Attributes governing the numbering of lists (14.8.5.5).
  static const String list = 'List';

  /// Attributes governing Form structure elements for non-interactive form
  /// fields (14.8.5.6).
  static const String printField = 'PrintField';

  /// Attributes governing the organization of cells in tables (14.8.5.7).
  static const String table = 'Table';

  /// Attributes governing translation to XML, version 1.00.
  static const String xml100 = 'XML-1.00';

  /// Attributes governing translation to HTML, version 3.20.
  static const String html320 = 'HTML-3.20';

  /// Attributes governing translation to HTML, version 4.01.
  static const String html401 = 'HTML-4.01';

  /// Attributes governing translation to OEB, version 1.0.
  static const String oeb100 = 'OEB-1.00';

  /// Attributes governing translation to Rich Text Format, version 1.05.
  static const String rtf105 = 'RTF-1.05';

  /// Attributes governing translation to a format using CSS, version 1.00.
  static const String css100 = 'CSS-1.00';

  /// Attributes governing translation to a format using CSS, version 2.00.
  static const String css200 = 'CSS-2.00';

  /// The owner of user properties attribute objects (14.7.5.4).
  static const String userProperties = 'UserProperties';

  /// Every owner name the specification standardizes.
  static const Set<String> all = {
    layout,
    list,
    printField,
    table,
    xml100,
    html320,
    html401,
    oeb100,
    rtf105,
    css100,
    css200,
    userProperties,
  };

  /// The owners whose attributes apply regardless of the export format
  /// (the four listed first in Table 341).
  static const Set<String> standard = {layout, list, printField, table};

  /// Whether [owner] is one of the names Table 341 defines.
  static bool isStandard(String owner) => all.contains(owner);
}
