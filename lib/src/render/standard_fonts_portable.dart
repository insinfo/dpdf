import 'glyph_source.dart';

/// Sem substitutas embutidas fora do VM.
///
/// Os programas URW pesam cerca de um megabyte comprimido. Embuti-los no
/// caminho web faria todo mundo que compila para `dart2js` ou `dart2wasm`
/// baixá-los, inclusive quem nunca renderiza uma página. Um cliente web que
/// queira o texto das catorze padrão desenhado busca os arquivos por HTTP e os
/// entrega em `PdfRenderOptions.fontFallback`, que continua sendo o gancho
/// oficial.
PdfFontFallback? standardFontFallback() => null;

/// Nenhuma face embutida para nomear fora do VM.
String? standardFaceName(PdfFontRequest request) => null;
