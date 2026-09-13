# Fixtures distribuídas

Hashes e fontes: `manifest.json`. As nove fixtures próprias estão cobertas
por `LICENSE.generated.txt`; ABeeZee-Regular.ttf mantém `OFL.txt` integral;
pdf20-offset-start.pdf é da PDF Association e mantém CC BY-SA 4.0.
Os avisos de licença usam finais de linha LF, conforme `.gitattributes`, para
que os hashes também confiram após checkout em outras plataformas.
Os termos também estão reunidos em `../../THIRD_PARTY_NOTICES.md`.

As imagens próprias são padrões geométricos sintéticos, apesar dos nomes
históricos Desert.jpg, bulb.gif e WP_20140410_001.bmp. test.pdf contém uma
página sintética com dois retângulos. image.jb2 exercita região genérica MMR,
sem representar cobertura completa do formato JBIG2.

pdf20-offset-start.pdf é cópia inalterada de `PDF 2.0 with offset start.pdf`
do repositório pdf20examples da PDF Association, renomeada apenas para tirar os
espaços do caminho. É o exemplo oficial da ISO 32000-2, 7.5.2: o `%PDF-` começa
no byte 656, depois de 656 bytes de comentário em texto puro, e os
deslocamentos do xref são contados a partir do sinal de porcentagem, não do
início do arquivo. A atribuição exigida pela CC BY-SA 4.0 está em
`../../THIRD_PARTY_NOTICES.md`.

rootRsa.cer é um certificado RSA-2048 autoassinado de teste, de nome
DPDF Synthetic Test CA e serial 1491571158. Não contém chave privada.
Foi gerado para a fixture; não representa confiança pública ou ICP-Brasil.

Os campos source do manifesto registram o gerador usado originalmente,
`tool/generate_test_assets.py`, que não está mais presente nesta árvore.
Não são instruções de recriação. Os hashes permitem verificar os bytes
preservados. Os geradores antigos dos dados embutidos também não são
necessários para consumir os recursos existentes.
