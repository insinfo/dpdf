# Procedência dos dados de fontes

Estes recursos possuem permissões próprias de redistribuição; não são dependências de pacotes em execução. Os avisos acompanham os arquivos e devem ser preservados na distribuição.

## AdobeGlyphList.txt

Dados Adobe Glyph List, com licença permissiva de três cláusulas no cabeçalho restaurado. Referência verificada:
https://github.com/adobe-type-tools/agl-aglfn/blob/4036a9ca80a62f64f9de4f7321a9a045ad0ecfd6/glyphlist.txt

A comparação encontrou os mesmos 4281 nomes. O arquivo local preserva entradas duplicadas e três aliases anteriores diferentes do upstream: Delta→U+0394, Omega→U+03A9 e mu→U+03BC. Essas modificações estão identificadas no cabeçalho. Nenhum glifo foi removido nesta regularização de avisos.

## afm/Helvetica.afm

Métricas AFM, não o programa proprietário da fonte Helvetica. A cópia local é idêntica, desconsiderando linhas vazias, ao recurso distribuído pelo Apache PDFBox:
https://github.com/apache/pdfbox/blob/21661b79f0e2c90ad53e322b80be3a3bf777b1c5/pdfbox/src/main/resources/org/apache/pdfbox/resources/afm/Helvetica.afm

A autorização específica da Adobe permite uso, cópia e distribuição, inclusive com modificações, preservando os avisos. Texto integral pertinente em `afm/LICENSE-Adobe.txt`, extraído de:
https://github.com/apache/pdfbox/blob/21661b79f0e2c90ad53e322b80be3a3bf777b1c5/LICENSE.txt

SHA-256 da cópia local de métricas: `db772f2830fb6d000907791d8d26a12524d96943a9a739e520ee855c6b25c96f`.

Esta verificação de recursos não resolve a procedência das implementações Dart da biblioteca.
