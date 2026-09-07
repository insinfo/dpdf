# Exemplos

| Arquivo | O que demonstra |
| --- | --- |
| [`dpdf_example.dart`](dpdf_example.dart) | Passeio principal: HTML para PDF, inspeção de integridade, conformidade PDF/A e redação por área. |
| [`text_editing.dart`](text_editing.dart) | Edição e substituição de texto no subconjunto estrito, sem refluxo. |
| [`keystore_smoke.dart`](keystore_smoke.dart) | Leitura de repositórios de chaves JKS e BKS a partir de bytes. |
| [`platform_smoke.dart`](platform_smoke.dart) | Criação, extração, mesclagem, assinatura RSA/CMS e codecs, usado para validar VM, `dart2js` e `dart2wasm`. |

Execute qualquer um a partir da raiz do pacote:

```bash
dart run example/dpdf_example.dart
```

O exemplo principal aceita um diretório opcional e grava os PDFs gerados nele:

```bash
dart run example/dpdf_example.dart build/exemplos
```

## O caso mais comum

```dart
import 'package:dpdf/dpdf.dart';

final pdf = await CraftHtmlConverter.convertToBytes('<h1>Olá</h1>');

final integridade = await PdfIntegrityChecker.inspect(pdf);
print(integridade.isDamaged);        // false

final conformidade = await PdfAVerifier.verify(
  pdf,
  level: PdfAConformanceLevel.a2b,
);
print(conformidade.violations);      // o que falta para ser PDF/A-2b
```
