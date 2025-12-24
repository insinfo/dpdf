# Roteiro: Portando iText para Dart

## Visão Geral

Este documento descreve o plano detalhado para portar a biblioteca **iText for .NET** para **Dart**. O iText é uma biblioteca robusta para criação e manipulação de PDFs. A portabilidade segue a estrutura modular do projeto original.

o ideal é ir portando e implementando testes para ir validando a implementação
e ir otimizando a implementação
va colocando comentario // TODO onde não esta completo ou onde merece otimizar atraves de benchmark (onde se cria duas ou mais implementações e testa para ver qual é melhor)

IMPORTANTE nada no codigo ou nos testes podem depender do diretorio referencias C:\MyDartProjects\itext\referencias pois ele sera removido no futuro o que 
for necessario tera que ser copiado para um diretorios apropriado

alto desempenho e não bloqueante é imporante para usar esta lib com servidores web
algumas micro otimizações podem ser necessarias

os testes não podem depender de arquivos externos copie o que for necessario para a pasta C:\MyDartProjects\itext\test\assets

**Fonte de Referência:** `C:\MyDartProjects\itext\referencias\itext-dotnet-develop`

**Destino Dart:** `C:\MyDartProjects\itext\lib\src`

---

## Índice

1. [Arquitetura do iText](#arquitetura-do-itext)
2. [Módulos e Dependências](#módulos-e-dependências)
3. [Fases da Portabilidade](#fases-da-portabilidade)
4. [Fase 1: Fundação (commons + io)](#fase-1-fundação-commons--io)
5. [Fase 2: Kernel (Núcleo PDF)](#fase-2-kernel-núcleo-pdf)
6. [Fase 3: Layout e Alto Nível](#fase-3-layout-e-alto-nível)
7. [Fase 4: Módulos Adicionais](#fase-4-módulos-adicionais)
8. [Considerações de Portabilidade C# → Dart](#considerações-de-portabilidade-c--dart)
9. [Progresso Atual](#progresso-atual)
10. [Próximos Passos](#próximos-passos)

---

## Arquitetura do iText

O iText 7 possui uma arquitetura modular:

```
┌─────────────────────────────────────────────────────────────┐
│                    itext.layout                              │
│              (Alto nível: Document, Paragraph, Table)        │
├─────────────────────────────────────────────────────────────┤
│                    itext.kernel                              │
│     (Núcleo PDF: PdfDocument, PdfPage, PdfObject, etc.)     │
├──────────────────────┬──────────────────────────────────────┤
│      itext.io        │            itext.commons             │
│   (I/O, Fontes,      │      (Utils, Exceções, Logs)         │
│    Codecs, Images)   │                                      │
└──────────────────────┴──────────────────────────────────────┘
```

### Módulos Opcionais:
- `itext.forms` - Formulários PDF (AcroForms)
- `itext.sign` - Assinaturas digitais
- `itext.barcodes` - Códigos de barras
- `itext.pdfa` - Conformidade PDF/A
- `itext.pdfua` - Conformidade PDF/UA
- `itext.svg` - Suporte SVG
- `itext.styledxmlparser` - Parser XML/CSS

---

## Módulos e Dependências

### Ordem de Portabilidade (baseada em dependências):

1. **itext.commons** - Sem dependências internas
2. **itext.io** - Depende de commons
3. **itext.kernel** - Depende de commons + io
4. **itext.layout** - Depende de kernel
5. **itext.forms** - Depende de kernel
6. **itext.sign** - Depende de kernel + forms
7. **itext.barcodes** - Depende de kernel
8. **itext.pdfa** / **itext.pdfua** - Depende de kernel
9. **itext.styledxmlparser** - Depende de io + commons
10. **itext.svg** - Depende de styledxmlparser + kernel

---

## Fases da Portabilidade

### Resumo das Fases:

| Fase | Módulos | Estimativa | Status |
|------|---------|------------|--------|
| 1 | commons, io | 2-3 semanas | 🔴 Não iniciado |
| 2 | kernel | 3-4 semanas | 🔴 Não iniciado |
| 3 | layout | 2-3 semanas | 🔴 Não iniciado |
| 4 | forms, sign, barcodes, etc. | 3-4 semanas | 🔴 Não iniciado |

---

## Fase 1: Fundação (commons + io)

### 1.1 itext.commons

**Diretório fonte:** `referencias/itext-dotnet-develop/itext/itext.commons/itext/commons/`

**Estrutura a portar:**

```
commons/
├── CommonsExtension.cs      → Funções de extensão (integrar em utils)
├── ITextLogManager.cs       → Sistema de logging
├── actions/                 → Ações e eventos
├── bouncycastle/            → Interface para criptografia (adaptar)
├── datastructures/          → Estruturas de dados customizadas
├── digest/                  → Algoritmos de digest
├── exceptions/              → Classes de exceção
├── json/                    → Serialização JSON
├── logs/                    → Constantes de log
└── utils/                   → Utilitários gerais
```

**Tarefas:**

- [x] **1.1.1** Criar estrutura de diretórios `lib/src/commons/`
- [x] **1.1.2** Portar `exceptions/` - Exceções base
  - ✅ ITextException
  - PdfException
  - IoException (portado em io/exceptions)
- [x] **1.1.3** Portar `utils/` - Utilitários
  - ✅ JavaUtil (adaptar para Dart)
  - ✅ MessageFormatUtil
  - ✅ DateTimeUtil
  - ✅ EncodingUtil
  - ✅ StringUtil
  - ✅ MathematicUtil
  - ✅ JavaCollectionsUtil
- [x] **1.1.4** Portar `datastructures/`
  - ✅ ISimpleList
  - ✅ NullUnlimitedList
  - ✅ SimpleArrayList
  - ✅ BiMap
  - ✅ Tuple2, Tuple3
- [x] **1.1.5** Portar `logs/` - Constantes de mensagens
  - ✅ CommonsLogMessageConstant
- [x] **1.1.6** Portar `actions/` - Sistema de eventos
  - ✅ EventManager, IEvent, IEventHandler
  - ✅ ProductNameConstant, NamespaceConstant
- [ ] **1.1.7** Adaptar sistema de logging para Dart
- [ ] **1.1.8** Interface para criptografia (via `pointycastle` package)

### 1.2 itext.io

**Diretório fonte:** `referencias/itext-dotnet-develop/itext/itext.io/itext/io/`

**Estrutura a portar:**

```
io/
├── IOExtensions.cs          → Extensões de I/O
├── codec/                   → Codecs (zlib, lzw, etc.)
├── colors/                  → Definições de cores
├── exceptions/              → Exceções específicas de I/O
├── font/                    → Subsistema de fontes
│   ├── Type1Font
│   ├── TrueTypeFont
│   ├── CFFFont
│   └── FontProgram
├── image/                   → Leitura de imagens
│   ├── PngImageHelper
│   ├── JpegImageParser
│   └── ImageData
├── logs/                    → Mensagens de log I/O
├── resolver/                → Resolução de recursos
├── source/                  → Leitura de dados PDF
│   ├── IRandomAccessSource
│   ├── RandomAccessFileOrArray
│   ├── PdfTokenizer         ⭐ Crítico
│   ├── ByteBuffer
│   └── ByteUtils
└── util/                    → Utilitários de I/O
```

**Tarefas:**

- [x] **1.2.1** Criar estrutura de diretórios `lib/src/io/`
- [ ] **1.2.2** Portar `source/` - **PRIORIDADE ALTA** ⭐
  - [x] `IRandomAccessSource` → Interface de acesso aleatório
  - [x] `ArrayRandomAccessSource` → Fonte baseada em array
  - [x] `ByteBuffer` → Buffer de bytes
  - [x] `ByteUtils` → Utilitários de bytes
  - [x] `RandomAccessFileOrArray` → Acesso a arquivos
  - [x] `PdfTokenizer` → Tokenizador PDF ⭐ (987 linhas) ✅
- [x] **1.2.3** Portar `codec/` - Compressão/Descompressão
  - ✅ Zlib (usa dart:io nativo)
  - ✅ LZWCompressor (TIFF/GIF)
  - ✅ LZWStringTable
  - ✅ TIFFLZWDecoder
  - ✅ BitFile (bit-level output)
  - ✅ PngWriter
- [ ] **1.2.4** Portar `font/` - Sistema de fontes
  - [x] FontProgram (base)
  - [x] Type1Font (Parcial - Fontes Standard e parsing AFM básico)
  - [ ] TrueTypeFont
  - [ ] OpenTypeFont
  - [ ] FontCache
- [x] **1.2.5** Portar `image/` - Leitura de imagens (Parcial)
  - ✅ ImageData base
  - ✅ PngImageHelper
  - ✅ JpegImageHelper
  - [ ] BmpImageHelper
  - [ ] TiffImageHelper
- [x] **1.2.6** Portar `colors/` - Definições de cores
  - ✅ IccProfile
- [x] **1.2.7** Portar `exceptions/` e `logs/`
  - ✅ IoLogMessageConstant
  - ✅ IoException, IoExceptionMessageConstant

---

## Fase 2: Kernel (Núcleo PDF)

**Diretório fonte:** `referencias/itext-dotnet-develop/itext/itext.kernel/itext/kernel/`

### 2.1 Objetos PDF Base

```
kernel/pdf/
├── PdfObject.cs             → Classe base para todos objetos PDF
├── PdfBoolean.cs            → Boolean
├── PdfNumber.cs             → Número
├── PdfString.cs             → String
├── PdfName.cs               → Nome (93KB! - muitas constantes)
├── PdfNull.cs               → Null
├── PdfArray.cs              → Array
├── PdfDictionary.cs         → Dicionário
├── PdfStream.cs             → Stream
├── PdfIndirectReference.cs  → Referência indireta
└── PdfLiteral.cs            → Literal
```

**Tarefas:**

- [x] **2.1.1** Portar `PdfObject` - Classe base
- [x] **2.1.2** Portar tipos primitivos
  - [x] PdfBoolean
  - [x] PdfNumber
  - [x] PdfString
  - [x] PdfNull
  - [x] PdfLiteral
- [x] **2.1.3** Portar `PdfName` (inclui constantes extensivas)
- [x] **2.1.4** Portar tipos compostos
  - [x] PdfArray
  - [x] PdfDictionary
- [x] **2.1.5** Portar `PdfStream`
- [x] **2.1.6** Portar `PdfIndirectReference`

### 2.2 Documento e Páginas

```
kernel/pdf/
├── PdfDocument.cs           → Documento PDF principal (125KB!)
├── PdfPage.cs               → Página PDF (86KB)
├── PdfPages.cs              → Árvore de páginas
├── PdfPagesTree.cs          → Gerenciamento da árvore
├── PdfCatalog.cs            → Catálogo do documento
├── PdfResources.cs          → Recursos (fontes, imagens, etc.)
└── PdfVersion.cs            → Versão do PDF
```

**Tarefas:**

- [x] **2.2.1** Portar `PdfVersion`
- [x] **2.2.2** Portar `PdfCatalog`
- [x] **2.2.3** Portar `PdfResources`
- [x] **2.2.4** Portar `PdfPages` e `PdfPagesTree`
- [x] **2.2.5** Portar `PdfPage`
- [x] **2.2.6** Portar `PdfDocument`

### 2.3 Leitura e Escrita

```
kernel/pdf/
├── PdfReader.cs             → Leitor PDF (82KB) ⭐
├── PdfWriter.cs             → Escritor PDF (24KB)
├── PdfOutputStream.cs       → Stream de saída
├── PdfXrefTable.cs          → Tabela de referências cruzadas
├── ReaderProperties.cs      → Configurações de leitura
├── WriterProperties.cs      → Configurações de escrita
└── DocumentProperties.cs    → Propriedades do documento
```

**Tarefas:**

- [x] **2.3.1** Portar `PdfXrefTable`
- [x] **2.3.2** Portar `PdfOutputStream`
- [x] **2.3.3** Portar `ReaderProperties` e `WriterProperties`
- [x] **2.3.4** Portar `PdfReader` ⭐
- [x] **2.3.5** Portar `PdfWriter`

### 2.4 Canvas e Desenho

```
kernel/pdf/canvas/
├── PdfCanvas.cs             → Canvas para desenho
├── parser/                  → Parser de conteúdo
└── wmf/                     → Suporte WMF
```

**Tarefas:**

- [ ] **2.4.1** Portar `PdfCanvas`
- [ ] **2.4.2** Portar parser de conteúdo

### 2.5 Subpastas do Kernel

```
kernel/
├── actions/       → Ações PDF
├── annot/         → Anotações
├── colors/        → Espaços de cor
├── crypto/        → Criptografia
├── exceptions/    → Exceções
├── font/          → Fontes no kernel
├── geom/          → Geometria (Rectangle, Matrix, etc.)
├── numbering/     → Numeração
├── utils/         → Utilitários
└── xmp/           → Metadados XMP
```

---

## Fase 3: Layout e Alto Nível

**Diretório fonte:** `referencias/itext-dotnet-develop/itext/itext.layout/`

### 3.1 Elementos de Layout

```
layout/
├── Document.cs              → Documento de alto nível
├── Canvas.cs                → Canvas de layout
├── element/                 → Elementos
│   ├── Paragraph.cs
│   ├── Text.cs
│   ├── Image.cs
│   ├── Table.cs
│   ├── Cell.cs
│   ├── List.cs
│   └── ListItem.cs
├── layout/                  → Sistema de layout
├── property/                → Propriedades
├── renderer/                → Renderizadores
└── style/                   → Estilos
```

**Tarefas:**

- [ ] **3.1.1** Portar propriedades e estilos
- [ ] **3.1.2** Portar elementos básicos (Text, Paragraph)
- [ ] **3.1.3** Portar elementos complexos (Table, List)
- [ ] **3.1.4** Portar sistema de renderização
- [ ] **3.1.5** Portar Document e Canvas de alto nível

---

## Fase 4: Módulos Adicionais

### 4.1 itext.forms

- [ ] AcroForm
- [ ] PdfFormField
- [ ] TextFormField
- [ ] CheckBoxFormField
- [ ] etc.

### 4.2 itext.sign

- [ ] Assinaturas digitais
- [ ] Integração com certificados

### 4.3 itext.barcodes

- [ ] Code128
- [ ] QRCode
- [ ] EAN
- [ ] etc.

### 4.4 Outros

- [ ] itext.pdfa
- [ ] itext.pdfua
- [ ] itext.svg
- [ ] itext.styledxmlparser

---

## Considerações de Portabilidade C# → Dart

### Equivalências de Tipos

| C# | Dart |
|----|------|
| `byte[]` | `Uint8List` |
| `int` | `int` |
| `long` | `int` (64-bit em Dart) |
| `float` | `double` |
| `double` | `double` |
| `string` | `String` |
| `Stream` | `List<int>` / `Uint8List` / `RandomAccessFile` |
| `Dictionary<K,V>` | `Map<K,V>` |
| `List<T>` | `List<T>` |
| `IDisposable` | Não existe (usar `try/finally`) |
| `async/await` | `async/await` (Future) |

### Padrões de Conversão

#### 1. Properties → Getters/Setters
```csharp
// C#
public int Count { get; set; }

// Dart
int _count;
int get count => _count;
set count(int value) => _count = value;
```

#### 2. Extension Methods → Funções Globais ou Extensões Dart
```csharp
// C#
public static string JSubstring(this string str, int begin, int end)

// Dart
extension StringExtensions on String {
  String jSubstring(int begin, int end) => substring(begin, end);
}
```

#### 3. Dispose Pattern → try/finally
```csharp
// C#
using (var doc = new PdfDocument(...)) { }

// Dart
final doc = PdfDocument(...);
try {
  // uso
} finally {
  doc.close();
}
```

#### 4. Nullable Types
```csharp
// C#
string? name;

// Dart
String? name;
```

#### 5. Internal Classes → Prefixo underscore
```csharp
// C#
internal class Helper { }

// Dart (em arquivo separado ou prefixo _)
class _Helper { }
```

### Dependências Dart Recomendadas se necessario

```yaml
dependencies:
  pointycastle: ^3.7.0      # Criptografia (substitui BouncyCastle)
  archive: ^3.4.0            # Compressão (zlib, gzip)
  xml: ^6.3.0                # Parsing XML
  collection: ^1.18.0        # Coleções avançadas
  crypto: ^3.0.3             # Hashing
  convert: ^3.1.1            # Codificação/Decodificação
  path: ^1.8.3               # Manipulação de caminhos
  typed_data: ^1.3.2         # Dados tipados (Uint8List, etc.)
```

---

## Progresso Atual

### Status por Módulo

| Módulo | Arquivos Portados | Total Estimado | Progresso |
|--------|-------------------|----------------|-----------|
| commons | 16 | ~30 | 55% |
| io | 36 | ~50 | 72% |
| kernel | 37 | ~150 | 25% |
| layout | 31 | ~80 | 39% |
| forms | 0 | ~40 | 0% |
| sign | 0 | ~30 | 0% |

### Arquivos Portados

#### commons/exceptions/
- ✅ `itext_exception.dart` - Classe base de exceção

#### commons/utils/
- ✅ `java_util.dart` - Utilitários Java-like
- ✅ `message_format_util.dart` - Formatação de strings com placeholders
- ✅ `date_time_util.dart` - Utilitários de data/hora
- ✅ `encoding_util.dart` - Codificação de strings (UTF-8, Latin-1, UTF-16)
- ✅ `string_util.dart` - Utilitários de string e regex
- ✅ `mathematic_util.dart` - Arredondamento "away from zero"
- ✅ `java_collections_util.dart` - Utilitários de coleções Java-like

#### commons/datastructures/
- ✅ `i_simple_list.dart` - Interface de lista simples
- ✅ `null_unlimited_list.dart` - Lista esparsa com suporte a null
- ✅ `simple_array_list.dart` - ArrayList portável
- ✅ `bi_map.dart` - Mapa bidirecional
- ✅ `tuple.dart` - Tuple2 e Tuple3

#### commons/logs/
- ✅ `commons_log_message_constant.dart` - Constantes de mensagens de log

#### commons/actions/
- ✅ `event_manager.dart` - Sistema de eventos (IEvent, IEventHandler, EventManager)

#### io/exceptions/
- ✅ `io_exception.dart` - Exceção de I/O
- ✅ `io_exception_message_constant.dart` - Constantes de mensagens

#### io/logs/
- ✅ `io_log_message_constant.dart` - Constantes de log para I/O

#### io/colors/
- ✅ `icc_profile.dart` - Perfis ICC para gerenciamento de cores

#### io/source/
- ✅ `i_random_access_source.dart` - Interface de acesso aleatório
- ✅ `array_random_access_source.dart` - Fonte baseada em array
- ✅ `independent_random_access_source.dart` - Wrapper independente
- ✅ `thread_safe_random_access_source.dart` - Wrapper thread-safe
- ✅ `byte_buffer.dart` - Buffer de bytes
- ✅ `byte_utils.dart` - Utilitários de bytes
- ✅ `random_access_file_or_array.dart` - Leitor unificado
- ✅ `pdf_tokenizer.dart` - Tokenizador PDF ⭐

#### io/image/
- ✅ `image_data.dart` - Classe base de dados de imagem
- ✅ `raw_image_data.dart` - Dados de imagem raw com CCITT
- ✅ `bmp_image_data.dart` - Dados de imagem BMP
- ✅ `tiff_image_data.dart` - Dados de imagem TIFF multi-página
- ✅ `gif_image_data.dart` - Dados de imagem GIF multi-frame
- ✅ `png_image_data.dart` - Dados de imagem PNG
- ✅ `jpeg_image_data.dart` - Dados de imagem JPEG
- ✅ `image_type_detector.dart` - Detecção de tipo por magic bytes
- ✅ `jpeg_image_helper.dart` - Helper para JPEG
- ✅ `png_image_helper.dart` - Helper para PNG

#### io/codec/
- ✅ `bit_file.dart` - Escritor de bits para LZW
- ✅ `lzw_string_table.dart` - Tabela de strings LZW
- ✅ `lzw_compressor.dart` - Compressor LZW (TIFF/GIF)
- ✅ `tiff_lzw_decoder.dart` - Decodificador LZW TIFF
- ✅ `png_writer.dart` - Escritor de imagens PNG
- ✅ `tiff_constants.dart` - Constantes TIFF (tags, compressão, fotométrica)
- ✅ `tiff_writer.dart` - Escritor de imagens TIFF com IFD

#### kernel/pdf/
- ✅ `pdf_object.dart` - Classe base e PdfIndirectReference (Async)
- ✅ `pdf_boolean.dart` - Valores booleanos
- ✅ `pdf_null.dart` - Valor null
- ✅ `pdf_number.dart` - Valores numéricos
- ✅ `pdf_string.dart` - Strings PDF
- ✅ `pdf_name.dart` - Nomes PDF com constantes
- ✅ `pdf_array.dart` - Arrays PDF (Async elements)
- ✅ `pdf_dictionary.dart` - Dicionários PDF (Async elements)
- ✅ `pdf_stream.dart` - Streams PDF (Async)
- ✅ `pdf_primitive_object.dart` - Classe base para objetos primitivos
- ✅ `pdf_literal.dart` - Literais PDF
- ✅ `pdf_xref_table.dart` - Tabela de referências cruzadas (xref)
- ✅ `pdf_reader.dart` - Leitor de documentos PDF (Async) ⭐
- ✅ `pdf_writer.dart` - Escritor de documentos PDF (Async)
- ✅ `pdf_document.dart` - Documento PDF principal (Async)
- ✅ `pdf_page.dart` - Página PDF (Async)
- ✅ `pdf_pages.dart` - Árvore de páginas (Async)
- ✅ `pdf_pages_tree.dart` - Gerenciamento da árvore de páginas (Async)
- ✅ `pdf_catalog.dart` - Catálogo do documento (Async)
- ✅ `pdf_resources.dart` - Recursos PDF (Async)
- ✅ `pdf_version.dart` - Versão do PDF
- ✅ `pdf_object_wrapper.dart` - Wrapper para objetos PDF
- ✅ `writer_properties.dart` - Propriedades de escrita PDF
- ✅ `reader_properties.dart` - Propriedades de leitura PDF

#### kernel/geom/
- ✅ `rectangle.dart` - Geometria de retângulo
- ✅ `page_size.dart` - Tamanhos de página padrão

#### kernel/exceptions/
- ✅ `kernel_exception_message_constant.dart` - Constantes de mensagens de erro
- ✅ `pdf_exception.dart` - Exceções PDF

#### kernel/utils/
- ✅ `filter_handlers.dart` - Decodificadores de filtros (FlateDecode, LZW, ASCII85, etc.)

#### kernel/logs/
- ✅ `kernel_log_message_constant.dart` - Constantes de log para kernel

#### kernel/geom/
- ✅ `rectangle.dart` - Geometria de retângulo
- ✅ `page_size.dart` - Tamanhos de página padrão
- ✅ `matrix.dart` - Matriz de transformação 3x3

#### kernel/colors/
- ✅ `color.dart` - Classe base de cor
- ✅ `device_gray.dart` - Cor DeviceGray
- ✅ `device_rgb.dart` - Cor DeviceRgb
- ✅ `device_cmyk.dart` - Cor DeviceCmyk

#### kernel/pdf/colorspace/
- ✅ `pdf_color_space.dart` - Espaços de cor PDF (Async factory)
- ✅ `pdf_device_cs.dart` - Espaços de cor de dispositivo

#### kernel/pdf/extgstate/
- ✅ `pdf_ext_g_state.dart` - Estado gráfico estendido (Async getters)

#### kernel/pdf/canvas/
- ✅ `pdf_canvas_constants.dart` - Constantes de canvas
- ✅ `canvas_graphics_state.dart` - Estado gráfico do canvas
- ✅ `pdf_canvas.dart` - Canvas de desenho (Parcial)

#### kernel/font/
- ✅ `pdf_font.dart` - Stub base para fontes

### Fase 3: Layout (Em andamento)

#### layout/properties/
- ✅ `property.dart` - Constantes de propriedades
- ✅ `unit_value.dart` - Valores com unidade (Point, Percent)
- ✅ `style.dart` - Contêiner de estilos

#### layout/element/
- ✅ `i_element.dart` - Interface base de elementos
- ✅ `element_property_container.dart` - Implementação base de propriedades
- ✅ `i_abstract_element.dart` - Interface de elemento abstrato
- ✅ `abstract_element.dart` - Elemento abstrato base
- ✅ `i_block_element.dart` - Interface de elemento de bloco
- ✅ `block_element.dart` - Elemento de bloco base
- ✅ `i_leaf_element.dart` - Interface de elemento folha
- ✅ `text.dart` - Elemento de texto
- ✅ `paragraph.dart` - Elemento de parágrafo
- ✅ `div.dart` - Elemento Div (Bloco genérico)
- ✅ `table.dart` - Elemento Tabela
- ✅ `cell.dart` - Elemento Célula
- ✅ `list.dart` - Elemento Lista
- ✅ `list_item.dart` - Elemento Item de Lista

#### layout/renderer/
- ✅ `i_renderer.dart` - Interface de renderização
- ✅ `abstract_renderer.dart` - Renderizador base
- ✅ `block_renderer.dart` - Renderizador de bloco
- ✅ `text_renderer.dart` - Renderizador de texto
- ✅ `paragraph_renderer.dart` - Renderizador de parágrafo
- ✅ `root_renderer.dart` - Renderizador raiz
- ✅ `document_renderer.dart` - Renderizador de documento
- ✅ `table_renderer.dart` - Renderizador de tabela (Parcial)
- ✅ `cell_renderer.dart` - Renderizador de célula
- ✅ `list_renderer.dart` - Renderizador de lista
- ✅ `list_item_renderer.dart` - Renderizador de item de lista
- ✅ `line_renderer.dart` - Renderizador de linha (Simplificado)

#### layout/
- ✅ `root_element.dart` - Elemento raiz
- ✅ `document.dart` - Documento de alto nível
- ✅ `i_property_container.dart` - Interface de contêiner de propriedades

#### layout/tagging/
- ✅ `i_accessible_element.dart` - Interface de acessibilidade (Tagging)

---

## Próximos Passos

### Imediato 

1. ✅ Criar roteiro detalhado (este documento)
2. ✅ Configurar estrutura de diretórios
3. ⬜ Adicionar dependências ao `pubspec.yaml` so se for extremamente necessario
4. ✅ Iniciar com `commons/exceptions/`
5. ✅ Portar `ByteBuffer` e `ByteUtils`
6. ✅ Portar `PdfTokenizer` ⭐
7. ✅ Portar objetos PDF básicos (`PdfObject`, `PdfName`, etc.)

### Curto Prazo 

1. ✅ Portar `PdfArray` e `PdfDictionary`
2. ✅ Portar `PdfStream` e `FilterHandlers`
3. ✅ Criar testes unitários para tokenizer e objetos PDF (72 testes)
4. ✅ Portar `PdfReader` (leitura básica de PDF) ⭐
5. ✅ Portar `PdfXrefTable` (tabela de referências cruzadas)
6. ✅ Adicionar benchmarks para FilterHandlers

### Médio Prazo 

1. ✅ Completar kernel básico e transição assíncrona
2. ✅ Implementar leitura de PDF simples (xref table, trailer, objetos)
3. ✅ Implementar escrita de PDF simples
4. ✅ Portar `PdfCanvas` para desenho de conteúdo (Base implementada com otimização)
5. ✅ Implementar suporte básico a fontes (Standard Type 1)
6. ⬜ Implementar processamento de streams de conteúdo (Content Streams)
7. ✅ Otimizar escrita do `PdfCanvas` usando `BytesBuilder` para evitar cópias de array.
8. ✅ Implementar suporte a imagens PNG (Decoding, Interlacing, Masks, PLTE)
9. ✅ Implementar Subsetting de Fontes TrueType

#### kernel/pdf/
- ✅ `pdf_output_stream.dart` - Stream de saída otimizado

#### io/font/
- ✅ `font_program.dart` - Base para fontes
- ✅ `open_type_parser.dart` - Parser de tabelas OTF/TTF (tables: head, hhea, os/2, post, cmap, glyf, loca, maxp, kern, name)
- ✅ `true_type_font.dart` - Fonte TrueType (leitura de tabelas, mapeamento de glifos, kerning)
- ✅ `font_names.dart` - Metadados de nomes de fonte
- ✅ `true_type_font_subsetter.dart` - Subsetting de glifos TTF
- ✅ `abstract_true_type_font_modifier.dart` - Modificação de tabelas TTF

#### kernel/font/
- ✅ `pdf_font.dart` - Base para fontes PDF
- ✅ `pdf_simple_font.dart` - Fontes simples (Type1, TrueType)
- ✅ `pdf_type1_font.dart` - Fontes Type 1 Standard
- ✅ `pdf_true_type_font.dart` - Integração de TTF no PDF (Embedding, Encoding, Subsetting)

#### layout/layout/
- ✅ `layout_area.dart` - Área de layout
- ✅ `layout_context.dart` - Contexto de layout
- ✅ `layout_result.dart` - Resultado de layout

#### layout/renderer/
- ✅ `draw_context.dart` - Contexto de desenho
- ✅ `area_break_renderer.dart` - Renderizador de quebra de área


---

## Notas e Decisões de Design

### Decisão 1: Nomenclatura
- Manter nomes de classes e metodos similares ao original para facilitar comparação
- Usar convenções Dart para métodos (camelCase)

### Decisão 2: Arquitetura de Arquivos
- Um arquivo por classe principal
- Classes auxiliares pequenas podem ficar no mesmo arquivo

### Decisão 3: Async vs Sync
- IMPORTANTE Manter operações de I/O async para poder usar esta lib junto com um servidor web dart onde é necessario não bloquear


### Decisão 4: Testes
- Criar testes unitários para cada componente portado
- Usar arquivos PDF de referência dos testes originais

---

## Referências

- [iText Community for .NET](https://github.com/itext/itext-dotnet)
- [PDF Reference 1.7](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf)
- [Dart Language Tour](https://dart.dev/guides/language/language-tour)
- [Effective Dart](https://dart.dev/guides/language/effective-dart)

---

_Última atualização: 2025-12-24_