import 'package:dpdf/src/svg/renderers/svg_node_renderer.dart';
import 'package:dpdf/src/svg/svg_constants.dart';
import 'package:dpdf/src/svg/utils/svg_css_utils.dart';

/// Avalia os atributos de processamento condicional da SVG 1.1, capítulo 5.8:
/// `requiredFeatures`, `requiredExtensions` e `systemLanguage`.
///
/// Os três valem para qualquer elemento desenhável (§5.8.1) e não só para os
/// filhos diretos de `<switch>`: quando o teste falha, o elemento e a sua
/// subárvore não são renderizados.
class SvgConditionalProcessing {
  SvgConditionalProcessing._();

  /// Idioma assumido para o usuário quando nenhum outro é informado.
  ///
  /// A especificação deixa a lista de idiomas a cargo do agente de usuário
  /// (§5.8.5); uma conversão em lote não tem sessão nem preferências, então a
  /// escolha precisa ser fixa para o resultado ser reprodutível.
  static const String defaultUserLanguage = 'en';

  static String _userLanguage = defaultUserLanguage;

  /// Idioma usado por `systemLanguage`.
  static String getUserLanguage() => _userLanguage;

  /// Troca o idioma consultado por `systemLanguage`.
  ///
  /// Passar `null` restaura [defaultUserLanguage].
  static void setUserLanguage(String? language) {
    final normalized = language?.trim();
    _userLanguage = (normalized == null || normalized.isEmpty)
        ? defaultUserLanguage
        : normalized;
  }

  /// Cadeias de característica da SVG 1.1 que este conversor implementa.
  ///
  /// A lista é deliberadamente conservadora: declarar suporte a algo que não
  /// é emitido faria um `<switch>` escolher o ramo errado, que é exatamente o
  /// erro silencioso que o elemento existe para evitar.
  static const Set<String> supportedFeatures = {
    'SVG-static',
    'CoreAttribute',
    'Structure',
    'BasicStructure',
    'ContainerAttribute',
    'ConditionalProcessing',
    'Image',
    'Style',
    'ViewportAttribute',
    'Shape',
    'Text',
    'BasicText',
    'PaintAttribute',
    'BasicPaintAttribute',
    'OpacityAttribute',
    'GraphicsAttribute',
    'BasicGraphicsAttribute',
    'Marker',
    'Gradient',
    'Pattern',
    'Clip',
    'BasicClip',
    'Mask',
    'Hyperlinking',
    'XlinkAttribute',
    'ExternalResourcesRequired',
  };

  /// Se [renderer] passa nos três testes condicionais.
  static bool isRendered(SvgNodeRenderer renderer) =>
      _features(renderer.getAttribute(SvgAttributes.REQUIRED_FEATURES)) &&
      _extensions(renderer.getAttribute(SvgAttributes.REQUIRED_EXTENSIONS)) &&
      _language(renderer.getAttribute(SvgAttributes.SYSTEM_LANGUAGE));

  /// §5.8.3: ausente é verdadeiro; a cadeia vazia é falsa; caso contrário
  /// todas as características listadas precisam ser suportadas.
  static bool _features(String? value) {
    if (value == null) return true;
    if (value.trim().isEmpty) return false;
    for (final feature in SvgCssUtils.splitValueList(value)) {
      if (!feature.startsWith(SvgValues.FEATURE_STRING_PREFIX)) return false;
      final name = feature.substring(SvgValues.FEATURE_STRING_PREFIX.length);
      if (!supportedFeatures.contains(name)) return false;
    }
    return true;
  }

  /// §5.8.4: nenhuma extensão é suportada, então só a ausência do atributo
  /// deixa o elemento ser desenhado.
  static bool _extensions(String? value) {
    if (value == null) return true;
    return false;
  }

  /// §5.8.5: verdadeiro quando algum idioma do usuário é igual a uma das
  /// etiquetas da lista, ou é um prefixo dela seguido de `-`.
  ///
  /// Como um agente de usuário real, `pt-BR` também conta como `pt`: sem essa
  /// expansão, `systemLanguage="pt"` seria recusado para quem lê português do
  /// Brasil, que não é o que a lista de preferências de um navegador produz.
  static bool _language(String? value) {
    if (value == null) return true;
    final preferences = _userPreferences();
    for (final raw in value.split(',')) {
      final tag = raw.trim().toLowerCase();
      if (tag.isEmpty) continue;
      for (final preference in preferences) {
        if (preference == tag || tag.startsWith('$preference-')) return true;
      }
    }
    return false;
  }

  static List<String> _userPreferences() {
    final language = _userLanguage.toLowerCase();
    final preferences = <String>[language];
    var separator = language.lastIndexOf('-');
    while (separator > 0) {
      preferences.add(language.substring(0, separator));
      separator = language.lastIndexOf('-', separator - 1);
    }
    return preferences;
  }
}
