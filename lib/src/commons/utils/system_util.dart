import 'dart:math';

/// Helper class for internal usage only.
class SystemUtil {
  SystemUtil._();

  /// Gets a time-based seed for random number generation.
  static int getTimeBasedSeed() {
    return DateTime.now().millisecondsSinceEpoch;
  }

  /// Gets the amount of free memory (mocked for now).
  static int getFreeMemory() {
    // There is no direct "get free memory" in pure Dart VM that is portable.
    // For the purpose of document ID generation, any varying value is fine.
    return 1024 * 1024 * 1024; // Mock 1GB
  }

  /// Gets a random integer within the exact range shared by all Dart targets.
  static int getRandomLong() {
    final random = Random();
    return random.nextInt(1 << 21) * 4294967296 + random.nextInt(4294967296);
  }
}
