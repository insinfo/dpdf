import 'dart:typed_data';

/// Represents an abstract source that bytes can be read from.
///
/// This class forms the foundation for all byte input in iText.
/// Implementations do not keep track of a current 'position', but rather
/// provide absolute get methods. Tracking position should be handled in
/// classes that use RandomAccessSource internally (via composition).
abstract class IRandomAccessSource {
  /// Gets a byte at the specified position.
  ///
  /// [position] byte position
  /// Returns the byte, or -1 if EOF is reached.
  int get(int position);

  /// Read an array of bytes of specified length from the specified position
  /// of source to the buffer applying the offset.
  ///
  /// If the number of bytes requested cannot be read, all the possible bytes
  /// will be read to the buffer, and the number of actually read bytes will
  /// be returned.
  ///
  /// [position] the position in the RandomAccessSource to read from
  /// [bytes] output buffer
  /// [off] offset into the output buffer where results will be placed
  /// [len] the number of bytes to read
  /// Returns the number of bytes actually read, or -1 if the file is at EOF.
  int getRange(int position, Uint8List bytes, int off, int len);

  /// Gets the length of the source.
  ///
  /// Returns the length of this source.
  int length();

  /// Closes this source.
  ///
  /// The underlying data structure or source (if any) will also be closed.
  void close();
}
