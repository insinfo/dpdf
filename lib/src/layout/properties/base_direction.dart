/// A specialized enum holding the possible values for a text element's base direction.
///
/// Used as the value for the BASE_DIRECTION property.
enum BaseDirection {
  /// No bidirectional algorithm applied.
  noBidi,

  /// Default bidirectional behavior.
  defaultBidi,

  /// Left-to-right text direction.
  leftToRight,

  /// Right-to-left text direction.
  rightToLeft,
}
