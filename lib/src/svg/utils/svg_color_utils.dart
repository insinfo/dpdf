import 'package:dpdf/src/html/css/css_color.dart';
import 'package:dpdf/src/kernel/colors/color.dart';
import 'package:dpdf/src/kernel/colors/device_rgb.dart';
import 'package:dpdf/src/svg/svg_constants.dart';

/// Resolve os valores de `fill` e `stroke` em cores do kernel.
///
/// A gramática de cores do SVG é a mesma do CSS, e o pacote já mantém um
/// parser determinístico em `html/css/css_color.dart`. Reaproveitá-lo evita
/// duas tabelas de cores nomeadas divergindo com o tempo; aqui só se
/// acrescenta o que é específico do SVG: `none`, `transparent` e a forma
/// percentual de `rgb()`, que o perfil HTML não precisa suportar.
class SvgColorUtils {
  SvgColorUtils._();

  static final RegExp _percentRgb =
      RegExp(r'^rgba?\(([^)]*)\)$', caseSensitive: false);

  /// Devolve `null` quando o valor significa "não pintar" ou é ininteligível,
  /// para o chamador poder distinguir ausência de pintura de preto explícito.
  static Color? parse(String? value) {
    if (value == null) return null;
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty ||
        normalized == SvgValues.NONE ||
        normalized == 'transparent') {
      return null;
    }
    final percent = _parsePercentageRgb(normalized);
    if (percent != null) return percent;
    final parsed = CssColors.parse(normalized);
    if (parsed == null) return null;
    return DeviceRgb(parsed.red, parsed.green, parsed.blue);
  }

  /// `rgb(100%, 0%, 0%)` só aparece em SVG; o parser do perfil HTML rejeita a
  /// forma percentual, então ela é tratada antes de delegar.
  static Color? _parsePercentageRgb(String value) {
    final match = _percentRgb.firstMatch(value);
    if (match == null) return null;
    final parts = match
        .group(1)!
        .split(RegExp(r'[,\s/]+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length < 3 || !parts.take(3).every((p) => p.endsWith('%'))) {
      return null;
    }
    final channels = <double>[];
    for (final part in parts.take(3)) {
      final amount = double.tryParse(part.substring(0, part.length - 1));
      if (amount == null || !amount.isFinite) return null;
      channels.add((amount / 100).clamp(0.0, 1.0));
    }
    return DeviceRgb(channels[0], channels[1], channels[2]);
  }
}
