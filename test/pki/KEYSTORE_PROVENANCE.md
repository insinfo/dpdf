# Leitores de contêineres de chaves

Implementação própria em Dart, usando somente o SDK e o SHA-1 local. A solicitação
de migração veio de `insinfo_dart_pdf`. O arquivo `bks_reader.dart` dessa biblioteca
foi consultado para identificar API e comportamento, mas não foi transplantado:
ele depende de PointyCastle e não recupera as chaves seladas. Não foi encontrado
um leitor JKS no código pesquisado da referência.

- `BksKeyStore`: leitura e escrita BKS v2, HMAC-SHA1 obrigatório, certificados,
  cadeias, chaves explícitas e payloads opacos; recuperação de chaves seladas
  por PKCS12/SHA1/Triple DES CBC com senha da entrada independente da senha do arquivo.
- `JksKeyStore`: leitura JKS v1/v2, integridade obrigatória, certificados,
  cadeias e recuperação autenticada do PKCS8 protegido pelo esquema JKS.
- PKCS12 KDF segue o apêndice B de [RFC 7292](https://www.rfc-editor.org/rfc/rfc7292).
  BKS seleciona a convenção de senha vazia com zero bytes.
- Triple DES usa as tabelas normativas de
  [FIPS 46-3](https://csrc.nist.gov/pubs/fips/46-3/final), com implementação própria.
- Estruturas BKS foram conferidas na documentação
  [PyJKS](https://pyjks.readthedocs.io/en/latest/bks.html) e no produtor do formato
  [Bouncy Castle](https://github.com/bcgit/bc-java/blob/main/prov/src/main/java/org/bouncycastle/jcajce/provider/keystore/bc/BcKeyStoreSpi.java).
  As constantes e campos necessários à interoperabilidade não foram substituídos
  por nomes incompatíveis no formato binário.

Testes usam `crypto` e `pointycastle` somente como oráculos de desenvolvimento.
As fixtures são sintéticas; certificados ASN.1 mínimos verificam transporte dos
bytes, sem simular validação de cadeia. A fixture JKS gerada por OpenJDK contém
somente chave/certificado de teste, não credenciais de usuário.

A leitura local de `assets/truststore/icp_brasil/cadeiasicpbrasil.bks` da referência,
com sua senha de teste, encontrou 157 registros/certificados e passou por uma
regravação com nova senha seguida de autenticação. Esse arquivo não foi incorporado
ao repositório nem transformado em âncora de confiança automática.

BKS v1, UBER, JCEKS e variantes históricas de PBE incorreto não estão implementados.
JKS não possui escritor nesta etapa. Estes leitores não verificam confiança,
revogação, uso de chave ou validade X.509; recuperam as estruturas e bytes.
SHA-1 e Triple DES estão presentes para leitura/interoperabilidade desses formatos.

Validação de 2026-09-06: 34 testes novos de PKI aprovados; suíte completa com
961 testes aprovados; análise estática sem problemas. A leitura BKS também
foi testada com senha vazia, alias Unicode/NUL, truncamentos, adulteração e
limites de trabalho do KDF.

O teste integrado, incluindo leitura JKS e recuperação/regravação BKS, executou
em VM/JIT, AOT, JavaScript e WebAssembly (web executada no Node). A superfície
de 454 bibliotecas compilou para dart2js e dart2wasm.
