import '../kernel/colors/color.dart';
import '../kernel/colors/device_gray.dart';

/// How the visible layer of a signature field is composed.
///
/// ISO 32000-1 12.7.4.5 leaves the appearance of a signature field to the
/// handler; this enumeration only selects which of the collected values the
/// generated `/AP` `/N` stream shows.
enum SignatureAppearanceMode {
  /// Only the free form description lines are rendered.
  description,

  /// The signer name is rendered above the description lines.
  nameAndDescription,

  /// Nothing is rendered; the field stays invisible even with a non-empty
  /// rectangle.
  empty,
}

/// The visible content of a signature field.
///
/// The instance is purely declarative: [SimpleSignatureAppearance] turns it
/// into the form XObject used as the `/N` appearance of the signature widget.
class SignatureFieldAppearance {
  SignatureAppearanceMode _mode = SignatureAppearanceMode.description;
  String? _signerName;
  final List<String> _lines = [];
  bool _renderSignerProperties = true;
  double _fontSize = 10;
  double _margin = 5;
  Color _backgroundColor = DeviceGray(0.9);
  Color _borderColor = DeviceGray(0.5);
  Color _textColor = DeviceGray(0);
  double _borderWidth = 1;

  /// Creates an appearance that renders the description lines only.
  SignatureFieldAppearance();

  /// The composition mode.
  SignatureAppearanceMode getMode() => _mode;

  /// Selects the composition mode.
  SignatureFieldAppearance setMode(SignatureAppearanceMode mode) {
    _mode = mode;
    return this;
  }

  /// The signer name shown by [SignatureAppearanceMode.nameAndDescription].
  String? getSignerName() => _signerName;

  /// Sets the signer name and switches to the name and description mode.
  SignatureFieldAppearance setSignerName(String? signerName) {
    _signerName = signerName;
    if (signerName != null && signerName.isNotEmpty) {
      _mode = SignatureAppearanceMode.nameAndDescription;
    }
    return this;
  }

  /// The description lines, in rendering order.
  List<String> getContentLines() => List.unmodifiable(_lines);

  /// Replaces the description lines.
  SignatureFieldAppearance setContent(List<String> lines) {
    _lines
      ..clear()
      ..addAll(lines);
    return this;
  }

  /// Appends one description line.
  SignatureFieldAppearance addContentLine(String line) {
    _lines.add(line);
    return this;
  }

  /// Whether reason, location, contact and signing date of the signer
  /// properties are appended to the description lines.
  bool isRenderingSignerProperties() => _renderSignerProperties;

  /// Enables or disables the automatic signer property lines.
  SignatureFieldAppearance setRenderSignerProperties(bool render) {
    _renderSignerProperties = render;
    return this;
  }

  /// Font size of every rendered line.
  double getFontSize() => _fontSize;

  /// Sets the font size; values below one point are rejected.
  SignatureFieldAppearance setFontSize(double fontSize) {
    if (fontSize < 1) {
      throw ArgumentError.value(fontSize, 'fontSize', 'must be at least 1');
    }
    _fontSize = fontSize;
    return this;
  }

  /// Inner margin between the field rectangle and the text.
  double getMargin() => _margin;

  /// Sets the inner margin; negative values are rejected.
  SignatureFieldAppearance setMargin(double margin) {
    if (margin < 0) {
      throw ArgumentError.value(margin, 'margin', 'must not be negative');
    }
    _margin = margin;
    return this;
  }

  /// Fill color of the appearance rectangle, null when it stays transparent.
  Color? getBackgroundColor() => _backgroundColor;

  /// Sets the fill color of the appearance rectangle.
  SignatureFieldAppearance setBackgroundColor(Color color) {
    _backgroundColor = color;
    return this;
  }

  /// Stroke color of the appearance border.
  Color getBorderColor() => _borderColor;

  /// Sets the stroke color of the appearance border.
  SignatureFieldAppearance setBorderColor(Color color) {
    _borderColor = color;
    return this;
  }

  /// Border width in points; zero suppresses the border.
  double getBorderWidth() => _borderWidth;

  /// Sets the border width; negative values are rejected.
  SignatureFieldAppearance setBorderWidth(double width) {
    if (width < 0) {
      throw ArgumentError.value(width, 'width', 'must not be negative');
    }
    _borderWidth = width;
    return this;
  }

  /// Fill color of the rendered text.
  Color getTextColor() => _textColor;

  /// Sets the fill color of the rendered text.
  SignatureFieldAppearance setTextColor(Color color) {
    _textColor = color;
    return this;
  }
}
