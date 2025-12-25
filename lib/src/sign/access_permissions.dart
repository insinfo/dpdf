/// Access permissions value to be set to certification signature as a part
/// of DocMDP configuration.
enum AccessPermissions {
  /// Unspecified access permissions value which makes signature "approval"
  /// rather than "certification".
  unspecified,

  /// Access permissions level 1 which indicates that no changes are permitted
  /// except for DSS and DTS creation.
  noChangesPermitted,

  /// Access permissions level 2 which indicates that permitted changes,
  /// with addition to level 1, are: filling in forms, instantiating page
  /// templates, and signing.
  formFieldsModification,

  /// Access permissions level 3 which indicates that permitted changes,
  /// with addition to level 2, are: annotation creation, deletion and modification.
  annotationModification,
}
