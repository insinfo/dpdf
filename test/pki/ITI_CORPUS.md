# Testes com os arquivos oficiais do ITI

Fontes fornecidas pelo usuário:

- [Instruções e senha pública do JKS](https://www.gov.br/iti/pt-br/assuntos/navegadores/java/versao-windows).
- [ZIP do keystore](https://www.gov.br/iti/pt-br/assuntos/navegadores/java/keystore_icp_brasil-jks.zip).
- [Repositório das ACs](https://www.gov.br/iti/pt-br/assuntos/repositorio/certificados-das-acs-da-icp-brasil-arquivo-unico-compactado).
- [Cadeia completa, incluindo expirados](https://acraiz.icpbrasil.gov.br/credenciadas/CertificadosAC-ICP-Brasil/ACcompactadox.zip).
- [SHA-512 publicado para a cadeia completa](https://acraiz.icpbrasil.gov.br/credenciadas/CertificadosAC-ICP-Brasil/hashsha512x.txt).

Snapshot obtido em 2026-09-06: um JKS com 175 entradas e um ZIP com 340 arquivos
de certificados. O SHA-512 do segundo ZIP foi comparado com o resumo oficial.
`iti_corpus_manifest.json` fixa hashes e tamanhos dos dois ZIPs e de cada membro.
Também registra os 175 fingerprints obtidos separadamente pelo OpenJDK keytool;
os testes não precisam de Java instalado para confrontá-los.

## Execução no Windows/PowerShell

```powershell
./tool/fetch_iti_test_assets.ps1
dart test test/pki/iti_official_corpus_test.dart
```

O script usa HTTPS com validação de certificado, verifica os hashes antes da
extração e escreve somente em `.dart_tool/iti_assets`. Não instala certificados
no sistema. Os testes seguintes funcionam offline. Se o cache não existir, o
grupo informa explicitamente que foi ignorado e mostra o comando de preparação.
Não trata ausência de arquivos como teste aprovado.

Uma mudança no conteúdo remoto causa falha de hash: uma nova versão requer
revisão e atualização explícita do manifesto. Um cache já verificado pode ser
reutilizado mesmo que os endereços passem a fornecer outra versão.

## Origem e limites

As páginas do ITI exibem a licença CC BY-ND 3.0 Não Adaptada. Os arquivos externos
permanecem no cache ignorado pelo Git e excluído do pacote; não são incorporados
sob MIT. O repositório contém os testes próprios e metadados de procedência.

Leitura e integridade do contêiner não conferem confiança aos certificados. O
pacote inclui certificados expirados por definição. Os testes não exigem validade
na data atual, não instalam âncoras e não afirmam validação de cadeia/revogação
ICP-Brasil. Os conjuntos JKS e ZIP podem corresponder a datas e seleções diferentes.

Resultado observado: quatro testes de corpus aprovados; 175 certificados JKS
coincidem com o oráculo keytool, 340 arquivos CRT contêm 335 certificados únicos,
e a interseção entre JKS e ZIP contém 174 certificados. Nenhuma alteração no
parser X.509 foi necessária para ler esses arquivos.
