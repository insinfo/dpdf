# Fixtures distribuídas

Hashes e fontes: `manifest.json`. As nove fixtures próprias estão cobertas
por `LICENSE.generated.txt`; ABeeZee-Regular.ttf mantém `OFL.txt` integral.
Os avisos de licença usam finais de linha LF, conforme `.gitattributes`, para
que os hashes também confiram após checkout em outras plataformas.
Os termos também estão reunidos em `../../THIRD_PARTY_NOTICES.md`.

As imagens próprias são padrões geométricos sintéticos, apesar dos nomes
históricos Desert.jpg, bulb.gif e WP_20140410_001.bmp. test.pdf contém uma
página sintética com dois retângulos. image.jb2 exercita região genérica MMR,
sem representar cobertura completa do formato JBIG2.

rootRsa.cer é um certificado RSA-2048 autoassinado de teste, de nome
PDFCraft Synthetic Test CA e serial 1491571158. Não contém chave privada.
Foi gerado para a fixture; não representa confiança pública ou ICP-Brasil.

Os campos source do manifesto registram o gerador usado originalmente,
`tool/generate_test_assets.py`, que não está mais presente nesta árvore.
Não são instruções de recriação. Os hashes permitem verificar os bytes
preservados. Os geradores antigos dos dados embutidos também não são
necessários para consumir os recursos existentes.
