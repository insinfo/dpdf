import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/src/io/image/jpeg_decoder.dart';
import 'package:test/test.dart';

/// Testes do modo progressivo (ITU-T T.81 §G) do decodificador de JPEG.
///
/// De onde vêm os dados:
///
/// * As fixtures foram geradas com ImageMagick a partir de uma mesma imagem
///   sintética de 24x16 (e uma de 17x9), com
///   `magick fonte.ppm -interlace Plane -quality 80 -sampling-factor F
///   saida.jpg` para o progressivo e `-interlace None` para o sequencial.
///
/// * As referências de pixel foram produzidas por um oráculo independente: um
///   programa Java que decodifica o mesmo arquivo com `javax.imageio.ImageIO`,
///   que lê JPEG progressivo nativamente, e grava um PPM.
///
/// Duas famílias de asserção, com propósitos diferentes:
///
/// 1. Contra o oráculo Java. A tolerância existe porque a IDCT flutuante AAN
///    daqui e a IDCT inteira do libjpeg arredondam diferente; o desvio medido
///    é de no máximo um ou dois níveis por amostra.
///
/// 2. Contra o próprio decodificador sequencial deste pacote. Progressivo e
///    sequencial são só duas codificações de entropia dos *mesmos* coeficientes
///    quantizados — o libjpeg aplica a mesma DCT e a mesma quantização nos dois
///    casos —, então decodificar o par tem de dar bytes idênticos, sem
///    tolerância nenhuma. É a asserção mais forte que existe aqui: qualquer
///    erro de EOBRUN, de aproximação sucessiva ou de grade de blocos quebra a
///    igualdade exata imediatamente.
///
/// A comparação 4:2:0/4:2:2 contra o Java fica fora da família (1) de
/// propósito: o libjpeg faz upsampling triangular de croma e este decodificador
/// faz vizinho mais próximo, o que é uma diferença de reconstrução de croma e
/// não de decodificação progressiva. Esses casos são cobertos exatamente pela
/// família (2).

/// 24x16 4:4:4 progressivo, qualidade 80.
const String _progressive444 =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAYEBQYFBAYGBQYHBwYIChAKCgkJChQODwwQ'
    'FxQYGBcUFhYaHSUfGhsjHBYWICwgIyYnKSopGR8tMC0oMCUoKSj/2wBDAQcHBwoIChMK'
    'ChMoGhYaKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgo'
    'KCgoKCj/wgARCAAQABgDAREAAhEBAxEB/8QAFgABAQEAAAAAAAAAAAAAAAAABAUD/8QA'
    'FwEBAQEBAAAAAAAAAAAAAAAABQQCA//aAAwDAQACEAMQAAABeFrZ7gDB09JdEKM+WH//'
    'xAAaEAADAQADAAAAAAAAAAAAAAACBAUDERMV/9oACAEBAAEFAmqYdSLuY5+nmbDUsuSn'
    'EC6EkyP/xAAaEQACAwEBAAAAAAAAAAAAAAACBQABAwQR/9oACAEDAQE/AWPAePPQxWtM'
    'crKYKtN+v2OnImdBUBiOPJFLIbOzn//EAB0RAAEEAwEBAAAAAAAAAAAAAAIAAQMFBBIh'
    'ERP/2gAIAQIBAT8BbGmzJuKGleLpKxIgj0BVThCG5Kwvxc9AQS/d/SX/xAAYEAEAAwEA'
    'AAAAAAAAAAAAAAABAAIQEf/aAAgBAQAGPwLkbOBjaf/EABoQAAMAAwEAAAAAAAAAAAAA'
    'AAABERAhMVH/2gAIAQEAAT8hnLBfCHqJ3AkuvBrKf//aAAwDAQACAAMAAAAQKaW//8QA'
    'GREAAgMBAAAAAAAAAAAAAAAAAAEQEUFR/9oACAEDAQE/EFt5DG4McZV2eoZQ/8QAGBEA'
    'AwEBAAAAAAAAAAAAAAAAAAERITH/2gAIAQIBAT8QaNSkAr4JbGkHI4H/xAAXEAEBAQEA'
    'AAAAAAAAAAAAAAABEQAh/9oACAEBAAE/ECidGGBZc5AgwbV5MwVFysItu//Z';

/// O mesmo original em 4:4:4 sequencial (SOF0).
const String _sequential444 =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAYEBQYFBAYGBQYHBwYIChAKCgkJChQODwwQ'
    'FxQYGBcUFhYaHSUfGhsjHBYWICwgIyYnKSopGR8tMC0oMCUoKSj/2wBDAQcHBwoIChMK'
    'ChMoGhYaKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgo'
    'KCgoKCj/wAARCAAQABgDAREAAhEBAxEB/8QAFgABAQEAAAAAAAAAAAAAAAAABQQG/8QA'
    'HhAAAQMFAQEAAAAAAAAAAAAAAQIDBAAFBgcRIRL/xAAXAQEBAQEAAAAAAAAAAAAAAAAG'
    'BQME/8QAIBEAAQUAAgMBAQAAAAAAAAAAAwABAgQGBRESE0ExUf/aAAwDAQACEQMRAD8A'
    'eyvZ0AWtDKQn0UFjxlzmLj+PfXa10fAGpcdETfxWYLm9si21yQ4lAPO09p4uVXqZFwZf'
    'NHHVkVAr2fb5mQkJCSAqsdGUoK/pC6PUMrYvct5P8dZ/KNXSQ+20SfOUkykgUg+8rJbt'
    'dmMx4gikJeu5UHHSlBIJTUPQb8cjuEKRA0QqXE9v9ZAYHqSbKnOSF/RHe9qWC096TSJ+'
    'KHk9IKR5Gdf/2Q==';

/// 24x16 4:2:2 progressivo.
const String _progressive422 =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAYEBQYFBAYGBQYHBwYIChAKCgkJChQODwwQ'
    'FxQYGBcUFhYaHSUfGhsjHBYWICwgIyYnKSopGR8tMC0oMCUoKSj/2wBDAQcHBwoIChMK'
    'ChMoGhYaKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgo'
    'KCgoKCj/wgARCAAQABgDASEAAhEBAxEB/8QAFwAAAwEAAAAAAAAAAAAAAAAAAAQFA//E'
    'ABcBAQEBAQAAAAAAAAAAAAAAAAQCAwX/2gAMAwEAAhADEAAAAX9gygZxPY7bp4Nf/8QA'
    'GhAAAwEAAwAAAAAAAAAAAAAAAgQFAxETFf/aAAgBAQABBQJqmHUi7mOfp5mw1LLkpxAu'
    'hJMj/8QAGxEAAgMBAQEAAAAAAAAAAAAAAQIAAwVRBBT/2gAIAQMBAT8BfOf7QOCZ2O9i'
    'sx7K9VX9Vz8Ey9RVoE//xAAdEQABBAIDAAAAAAAAAAAAAAACAAEDBAUREhMx/9oACAEC'
    'AQE/AaGNOw7zGsm8ndoVLkApUhBvXUWpW5Ev/8QAGBABAAMBAAAAAAAAAAAAAAAAAQAC'
    'EBH/2gAIAQEABj8C5GzgY2n/xAAaEAADAAMBAAAAAAAAAAAAAAAAAREQITFR/9oACAEB'
    'AAE/IZywXwh6idwJLrwayn//2gAMAwEAAgADAAAAEBA9/8QAGREBAQEAAwAAAAAAAAAA'
    'AAAAAQBBEVHw/9oACAEDAQE/EAB9lrc7AvBLXat//8QAGREBAAMBAQAAAAAAAAAAAAAA'
    'AQARIRAx/9oACAECAQE/EPK65reAHJQdG1n/xAAXEAEBAQEAAAAAAAAAAAAAAAABEQAh'
    '/9oACAEBAAE/ECidGGBZc5AgwbV5MwVFysItu//Z';

/// O mesmo original em 4:2:2 sequencial.
const String _sequential422 =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAYEBQYFBAYGBQYHBwYIChAKCgkJChQODwwQ'
    'FxQYGBcUFhYaHSUfGhsjHBYWICwgIyYnKSopGR8tMC0oMCUoKSj/2wBDAQcHBwoIChMK'
    'ChMoGhYaKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgo'
    'KCgoKCj/wAARCAAQABgDASEAAhEBAxEB/8QAFwABAQEBAAAAAAAAAAAAAAAABQAEBv/E'
    'AB4QAAEDBQEBAAAAAAAAAAAAAAEAAgQDBQYHESES/8QAGAEBAAMBAAAAAAAAAAAAAAAA'
    'BQIDBAb/xAAlEQABBAIABAcAAAAAAAAAAAADAQIEBgAFERIhQRMUMTJCUcH/2gAMAwEA'
    'AhEDEQA/AHsr2dAFrZRaG+hbMFze2RbbUkVGsB51B6Ctn2D3zTenHIGrpk3TWJ8GfmAv'
    '2fb5mQkNDSA5Sz2Z8nznIJeiIiZRXaceQIpXd3rnP5Rq6SK9OkSfOJCXruVBx0tYSCWr'
    't5dgDpNKILfc7HY9qGbazD9mt4YBgepJsqdUkP8AojveqQ0RWymeKROq4tV7SIcBq/aq'
    'uf/Z';

/// 24x16 4:2:0 progressivo.
const String _progressive420 =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAYEBQYFBAYGBQYHBwYIChAKCgkJChQODwwQ'
    'FxQYGBcUFhYaHSUfGhsjHBYWICwgIyYnKSopGR8tMC0oMCUoKSj/2wBDAQcHBwoIChMK'
    'ChMoGhYaKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgo'
    'KCgoKCj/wgARCAAQABgDASIAAhEBAxEB/8QAFwAAAwEAAAAAAAAAAAAAAAAAAAQFA//E'
    'ABYBAQEBAAAAAAAAAAAAAAAAAAMCBP/aAAwDAQACEAMQAAABf2gMSjBHMyf/xAAaEAAD'
    'AQADAAAAAAAAAAAAAAACBAUDERMV/9oACAEBAAEFAmqYdSLuY5+nmbDUsuSnEC6EkyP/'
    'xAAdEQACAgEFAAAAAAAAAAAAAAABAgAEAwUSEyEx/9oACAEDAQE/AeOk9tiG6QTTaVA4'
    't7H0z//EAB0RAAICAQUAAAAAAAAAAAAAAAIDAAQBERITFCL/2gAIAQIBAT8BVUqVlc9g'
    'vWY9HbLeJaYn/8QAGBABAAMBAAAAAAAAAAAAAAAAAQACEBH/2gAIAQEABj8C5GzgY2n/'
    'xAAaEAADAAMBAAAAAAAAAAAAAAAAAREQITFR/9oACAEBAAE/IZywXwh6idwJLrwayn//'
    '2gAMAwEAAgADAAAAEADv/8QAFxEBAQEBAAAAAAAAAAAAAAAAAQAhMf/aAAgBAwEBPxA5'
    'OCba2b//xAAXEQEBAQEAAAAAAAAAAAAAAAABEQAx/9oACAECAQE/EA9y0MlZwDf/xAAX'
    'EAEBAQEAAAAAAAAAAAAAAAABEQAh/9oACAEBAAE/ECidGGBZc5AgwbV5MwVFysItu//Z';

/// O mesmo original em 4:2:0 sequencial.
const String _sequential420 =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAYEBQYFBAYGBQYHBwYIChAKCgkJChQODwwQ'
    'FxQYGBcUFhYaHSUfGhsjHBYWICwgIyYnKSopGR8tMC0oMCUoKSj/2wBDAQcHBwoIChMK'
    'ChMoGhYaKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgo'
    'KCgoKCj/wAARCAAQABgDASIAAhEBAxEB/8QAFwAAAwEAAAAAAAAAAAAAAAAAAAUGBP/E'
    'AB4QAAEDBQEBAAAAAAAAAAAAAAEAAgQDBQYHESES/8QAFgEBAQEAAAAAAAAAAAAAAAAA'
    'BAMF/8QAHxEAAQQCAgMAAAAAAAAAAAAAAQIDBAUAEQYTISIx/9oADAMBAAIRAxEAPwB9'
    'lezoAtbKLQ30LZgub2yLbakio1gPOqByjV0kV6dIk+cTCXruVBx0tYSCWqcWpqKyIJ9i'
    '5txZ2BiBGpXrd1aXPVlOsYP2fb5mQkNDSA5CkMD1JNlTqkh/0R3vULOnQTbO97bhSn4B'
    'iONUtAuKXnV+VqJz/9k=';

/// 24x16 em escala de cinza, progressivo.
const String _progressiveGray =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAYEBQYFBAYGBQYHBwYIChAKCgkJChQODwwQ'
    'FxQYGBcUFhYaHSUfGhsjHBYWICwgIyYnKSopGR8tMC0oMCUoKSj/wgALCAAQABgBAREA'
    '/8QAFgAAAwAAAAAAAAAAAAAAAAAAAwQF/9oACAEBAAAAAaRFI5lP/8QAGxAAAgMAAwAA'
    'AAAAAAAAAAAAAgMBBAUREhX/2gAIAQEAAQUCfrL6VdJUB6yia/HPmckxTVxTkv/EABYQ'
    'AQEBAAAAAAAAAAAAAAAAABEAEP/aAAgBAQAGPwInDG//xAAYEAEBAQEBAAAAAAAAAAAA'
    'AAABABEhUf/aAAgBAQABPyHP4lSC8myOrklm62//2gAIAQEAAAAQv//EABgQAQEBAQEA'
    'AAAAAAAAAAAAAAEAESEx/9oACAEBAAE/EAgOy3+clkBg3RowAKSLer//2Q==';

/// O mesmo original em cinza sequencial.
const String _sequentialGray =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAYEBQYFBAYGBQYHBwYIChAKCgkJChQODwwQ'
    'FxQYGBcUFhYaHSUfGhsjHBYWICwgIyYnKSopGR8tMC0oMCUoKSj/wAALCAAQABgBAREA'
    '/8QAFwAAAwEAAAAAAAAAAAAAAAAAAwUGBP/EAB8QAAIBBAIDAAAAAAAAAAAAAAECBAAD'
    'BQcGERMhMf/aAAgBAQAAPwClz22sYIK2wE9ij8W2XirEJ7rKnfVKjtvFyMuQAhANR+e0'
    '/M8qW+2rZf1PMi4chWYEilPFdLzr8p7rFvtf/9k=';

/// 24x16 4:2:0 progressivo com DRI = 1, portanto cheio de RSTn.
const String _progressiveRestart =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAYEBQYFBAYGBQYHBwYIChAKCgkJChQODwwQ'
    'FxQYGBcUFhYaHSUfGhsjHBYWICwgIyYnKSopGR8tMC0oMCUoKSj/2wBDAQcHBwoIChMK'
    'ChMoGhYaKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgo'
    'KCgoKCj/wgARCAAQABgDASIAAhEBAxEB/8QAFwAAAwEAAAAAAAAAAAAAAAAAAAMEBf/E'
    'ABYBAQEBAAAAAAAAAAAAAAAAAAQCA//dAAQAAf/aAAwDAQACEAMQAAABvdgUTp//0HGO'
    'ER//xAAaEAADAQADAAAAAAAAAAAAAAACBAUDERMV/9oACAEBAAEFAmqYdX//0EXcxz//'
    '0fTzNj//0mpZc//TKcQL/wD/1EJJkf8A/8QAHREAAgIBBQAAAAAAAAAAAAAAAQIABAMF'
    'EhMhMf/aAAgBAwEBPwHjpPbYhukE/9DTaVA4t7H0z//EAB0RAAICAQUAAAAAAAAAAAAA'
    'AAIDAAQBERITFCL/2gAIAQIBAT8BVUqVlc9gvWZ//9B6O2W8S0xP/8QAFxABAQEBAAAA'
    'AAAAAAAAAAAAAAECEf/aAAgBAQAGPwLj/9C6r//Rf//Skf/Tf//Uun//xAAZEAADAAMA'
    'AAAAAAAAAAAAAAAAAREhMVH/2gAIAQEAAT8hnLD/0F8I/9F4ibP/0gT/05dcP//Uayn/'
    '2gAMAwEAAgADAAAAEAP/0Dv/xAAXEQEBAQEAAAAAAAAAAAAAAAABACEx/9oACAEDAQE/'
    'EDk4L//Qba2b/8QAFxEBAQEBAAAAAAAAAAAAAAAAAREAMf/aAAgBAgEBPxAPctDf/9BK'
    'zgG//8QAFxABAQEBAAAAAAAAAAAAAAAAAREAIf/aAAgBAQABPxAonRv/0BgWXf/RcgQZ'
    '/9IbV5N//9NgqLn/1Kwi27//2Q==';

/// 17x9 4:2:0 progressivo: largura que faz a grade de uma varredura
/// não intercalada divergir da grade preenchida de MCUs.
const String _progressive17x9 =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAYEBQYFBAYGBQYHBwYIChAKCgkJChQODwwQ'
    'FxQYGBcUFhYaHSUfGhsjHBYWICwgIyYnKSopGR8tMC0oMCUoKSj/2wBDAQcHBwoIChMK'
    'ChMoGhYaKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgo'
    'KCgoKCj/wgARCAAJABEDASIAAhEBAxEB/8QAGQAAAgMBAAAAAAAAAAAAAAAAAAcDBAUG'
    '/8QAFgEBAQEAAAAAAAAAAAAAAAAABAMF/9oADAMBAAIQAxAAAAG/MudC2h3IrRY//8QA'
    'HBAAAgICAwAAAAAAAAAAAAAAAwQAAgUTFTE0/9oACAEBAAEFAmsnTUi6Oo+WFGuheaf/'
    'xAAaEQACAgMAAAAAAAAAAAAAAAAAAQIUAwVS/9oACAEDAQE/AZazDea5RTgf/8QAHBEA'
    'AQQDAQAAAAAAAAAAAAAAAgABAwUEEiFR/9oACAECAQE/Aa6qhOF8g+utA8X/xAAYEAAC'
    'AwAAAAAAAAAAAAAAAAABEAACEf/aAAgBAQAGPwLIbFB//8QAGRAAAgMBAAAAAAAAAAAA'
    'AAAAAAEQEXEx/9oACAEBAAE/Ia5aF8IygdMj/9oADAMBAAIAAwAAABAzL//EABkRAAMA'
    'AwAAAAAAAAAAAAAAAAABIRFhkf/aAAgBAwEBPxBqjEeG5n//xAAXEQEAAwAAAAAAAAAA'
    'AAAAAAABEBFB/9oACAECAQE/ELQldif/xAAaEAACAgMAAAAAAAAAAAAAAAAAARARIWGx'
    '/9oACAEBAAE/EFUmSEwLqzceGS//2Q==';

/// O mesmo original de 17x9 em sequencial.
const String _sequential17x9 =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAYEBQYFBAYGBQYHBwYIChAKCgkJChQODwwQ'
    'FxQYGBcUFhYaHSUfGhsjHBYWICwgIyYnKSopGR8tMC0oMCUoKSj/2wBDAQcHBwoIChMK'
    'ChMoGhYaKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgo'
    'KCgoKCj/wAARCAAJABEDASIAAhEBAxEB/8QAGQAAAgMBAAAAAAAAAAAAAAAAAAgEBQYH'
    '/8QAIxAAAQMDAgcAAAAAAAAAAAAAAAECBQMEBgcRFyEzNlFygf/EABYBAQEBAAAAAAAA'
    'AAAAAAAAAAUEBv/EACIRAAAEBQUBAAAAAAAAAAAAAAABAgMEBQYRIRMVQVFSkf/aAAwD'
    'AQACEQMRAD8Avsr1OsEi2UWo3mhMwXN4y1jalxUaxF23F0yjp0vhoIvtt/qWU7SkG9Bq'
    'mL11LM+RoHKYgznik5s2jHwdy4txflgCtAL6DPkD7Mz2Y//Z';

/// 96x64 4:2:0 progressivo com DRI = 3: 166 marcadores RSTn
/// espalhados pelas onze varreduras.
const String _progressiveRestartWide =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAcFBQYFBAcGBgYIBwcICxILCwoKCxYPEA0S'
    'GhYbGhkWGRgcICgiHB4mHhgZIzAkJiorLS4tGyIyNTEsNSgsLSz/2wBDAQcICAsJCxUL'
    'CxUsHRkdLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCws'
    'LCwsLCz/wgARCABAAGADASIAAhEBAxEB/8QAGQAAAwEBAQAAAAAAAAAAAAAAAAMHAQYC'
    '/8QAGQEBAAMBAQAAAAAAAAAAAAAAAwABAgUE/90ABAAD/9oADAMBAAIQAxAAAAHoWLZz'
    '6XNqTNmrDcXX/9DpQObtc2pM29BZnrF1/9Hlt8+imU6Y04bFsWOf/9LlwwbKdMKeUFsW'
    'Of/T6Fi2c6lzWlTZqw3G1//U6UDm7XNqTNnLM9Y2v//V5bfPoplOmNOGxbFjn//W5cMG'
    'ynTGnFBbFjn/xAAeEAACAQQDAQAAAAAAAAAAAAAAQQECAzIzEDFCQ//aAAgBAQABBQK3'
    'gV6//9BKT//RHOX/0hH/07eoua//1Bn/1RVd/wD/1h+v/9eOF//QSrx//9Eb/9IU5//T'
    'jEnr/9RlXX//1RSf/9Yf1//Xt4Fer//QRJ//0Rzl/9IR/9O3qLmv/9R8f//VFV3/AP/W'
    'H6//144X/9BFeP8A/9EZ/9IU7P/TjEk//9RlWP8A/9VKT//WH9f/xAAbEQEBAAMAAwAA'
    'AAAAAAAAAAAAAQMxMgJCkf/aAAgBAwEBPwHHxHvV0//QTdV//9GaRk4r/9JHnr4//9PH'
    'xHvVf//UTdV//9WaRk4r/9ZHnr4//8QAHxEAAQQCAgMAAAAAAAAAAAAAAAEDMWFx8BAR'
    'IUFR/9oACAECAQE/AVnsbjj/0BvclH//0RwST//Ssd3Inw//01kbjj//1LG9yUf/1RwS'
    'T//Wsd9b5EP/xAAZEAADAQEBAAAAAAAAAAAAAAAAARBxAoH/2gAIAQEABj8C5ydYf//Q'
    'v//RnOn/0r//0+cnWH//1L//1Zxp/9a//9eM/9CLUf/Rv//Sixn/07//1J6j/9WI/9aL'
    'Gf/X5ydYf//Qv//RnOn/0r//0+cnWH//1L//1Zxp/9a//9eM/9CLUf/Rv//Sixn/07//'
    '1J6j/9WI/9aLGf/EAB0QAAMAAgMBAQAAAAAAAAAAAAABMREhQWHwcVH/2gAIAQEAAT8h'
    '2+YW3kv7H//QmRBCR//R5wUX+aZ//9JcsgesI//T07kIsE3Y/9SvBR2f/9VTJPok80z/'
    '1n+FFyP/19sdIVyOx//QgmBJ4yj/0a8F+D9H/9JRsg0X40f/09EOMHEf/9SivJz+Mo//'
    '1VpZIOA//9Z3BQ9u8aP/19upBXJb2P/QgiwQkf/RrwX4LfNM/9JRsn0PTSP/09O9BzBJ'
    '2P/UvwV5OMn/1YskE3mmf//WdwX4Lkf/19sdIVbHY//QgiwSeMo//9GvBRzk/9JTJPo0'
    'T40f/9PRBzBOD//UoW3k5vGUf//VmRBwH//W5wUcnjR//9oADAMBAAIAAwAAABDEGD//'
    '0MocP//RIEL/AP/SGMP/AP/Tzbg//9TKPD//1SBC/wD/1hhD/wD/xAAaEQADAQEBAQAA'
    'AAAAAAAAAAAAATGxoXHB/9oACAEDAQE/EOFYYLWUP//QO34iD//RgUzheH//0i2S90j/'
    '0+FYYLWQz//UO34iD//VgUzheH//1i2S90j/xAAhEQEAAQMEAwEBAAAAAAAAAAABABEx'
    'gSFBcbFhwdGRUf/aAAgBAgEBPxB6lz8IUQXNMt/yAOha2C7mf//QqOrzgsSoPJ2r1A2c'
    'Htn/0Vpq852IUALlTLdxCICzpgv+z//Sru5xsSop/Tt8h1o8h7Z//9Nol5y2IUQXtluw'
    'B0LOmC/7P//Uru5fRKg8nZeoGzg9s//VVGre+WxClA8mW7KUGz0fZ//Wru5fRKjyO3yG'
    'rQ8mN2f/xAAgEAEAAQQCAwEBAAAAAAAAAAABABEhMUFRsWGRwXHw/9oACAEBAAE/ELBo'
    '6yXKwRX/AI/TP//QLmzHBthoXk7n/9FKg4J6COqMDn//0lQWFx2y5sR+T//T/T6ZEojL'
    'BY/0M//UbOhC46Itl8nc/9WxrLPZBoXK5//WFUMcGiYNAfk//9exwCXNYIqJ4Z//0C47'
    'Y2NmG1nf/9FsjBPRGQ8D8Z//0lRO4XHbPJnun//T/SQiUJywVR4Z/9RwaIXdCO1yv//V'
    'uVlmjbBSjlfjP//WFQcE0aJ4Ed0//9f8HpEuTwSxf9jP/9AuO2NnZhseTuf/0UojBC46'
    'h1bgc//SVE5YZNwKFlH5P//T/S6ZBQHLBUuDqZ//1NGoLuhFufJ3P//VLuzNG2Gg9uX/'
    '1hUHBPRBkYB+T//XtLQRVTgio3KM/9AybY2RlhsZ3//RbIwQuOiZL5+M/9KxPLPZFhZe'
    '6f/Tse0IKA5YKs4Bn//U0aJcrBHY/FL/1S5sxwbYKI8/Gf/WSoOCegjd+Dun/9k=';

/// O mesmo original de 96x64 em sequencial, sem restart.
const String _sequentialWide =
    '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAcFBQYFBAcGBgYIBwcICxILCwoKCxYPEA0S'
    'GhYbGhkWGRgcICgiHB4mHhgZIzAkJiorLS4tGyIyNTEsNSgsLSz/2wBDAQcICAsJCxUL'
    'CxUsHRkdLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCwsLCws'
    'LCwsLCz/wAARCABAAGADASIAAhEBAxEB/8QAGgAAAwEBAQEAAAAAAAAAAAAAAgQIAQAD'
    'B//EACwQAAIBAgQEBgIDAQAAAAAAAAECAAMiBBExQQUyUbESIVNhssEkJRMjkZL/xAAa'
    'AQEBAQEBAQEAAAAAAAAAAAAEAgAFAwEG/8QAKxEBAAECAwUIAwEAAAAAAAAAAQACMRFx'
    'gQQhMrHBAzNBQmGRstESQ1Ei/9oADAMBAAIRAxEAPwD6Hw+7A4UbCknYRhbnLHQRbh9v'
    'CMN1aknYRgjwoFGpn5+t/wBNTn9E+bP3NGRyi+OP6zFufSfL/DJtFtMtuZSXEh+txCD0'
    'm7GTabnC7CM2YSlC5u1b+0n91WRzZhtp5bmZVGSKg6jvCF1QnYQSfIueo7xQDuLW0Lus'
    'urhZTpGbBBoJ3NU9hMXyQsdTO5afu042I73PQsT2nhXOeKwrHQVT8Hk2KcgzmUlixlVw'
    'aDU1T8Hk2sMyEEfs+Iep8nHlDUcVefQmC2mTuYLWlV3IP1DN1TLYQebEBtgD9RQeUyOr'
    'LqtOp3BeiqIS+bljoIFO3DL1IEMjJAg1My4b3PXwJqeEgscqNRz0MpwW0ydzJjrDOmUH'
    'QynTdUy2EHtIgBcxNW7pKpuzDbTC7mL48fjU0Hq0vmsZFzlthFsWf6A59Wn81hKAagLO'
    '7Qv7yNo7mvJ5SbTc4UaCdzVPZZy2oWOpmctPLczrY+Zz08CXM1qBzoD9GU4pyVnO8mKo'
    'Mv40GpP0ZTzDNgg0EJtWJh/T5P1NRdmC2mTuYvUtx9BdzSqd0jPNUy2EXa7i1JthSqd0'
    'hKDf+J6h1ZHb8JnTzJ3D7sDhui0l7CML5sXOgi3D7eEYXq1JOwjDDJQg1M1alSuerYm2'
    'fuaMjlF8d5cLxbn0n7GTYLaZO5lKcSGfDsQg0FJuxk2c1TLZYzZhKUL21bsn91WRzZht'
    'QLuZlUWqg6jvCFzlthBJtLnqO8WA7izu0L+8uqzKdI8ThRoJwuqE7LMFqFtzO5aeW5nG'
    'x8zm9Ce08K5zxOFc6Cqfg8mxTkrOdTKSxYyrYJBvVPwaTawzYINBHbPiHqfJXlDUcVef'
    'QmC2nnu0Fh4WRRqQfqHzVPZYIuxHiOgB+osPKZHVl1WnUrgp2VRCU5sznQQKduGQbkCG'
    'wyUINTMqOLe+rYmp4SCxyoVHOpBlOC2nnuZMdYZoUGgBlO81TLYQe0iYB6mrdlU3ZhtQ'
    'KNTF8ePx6aD1aXzWMrc5Y6CLYs/jhz6tPL/tYSjBqDweR9yNo7mvJ5SbTc4UaCcLqhOw'
    'nC2mW3Mw208tzOtj5nN6EuZq4c9foynF8lLnUyY6gyNNB1+jKdIzYINBCbVifj/T5P1N'
    'RdmctP3aL1LeIUFGppVO6Rnmqewi58+K0nOgpVO6QlBi4HqaeLI7fhM6eZP/2Q==';

/// RGB de referência de 24x16 produzido por javax.imageio.ImageIO
/// decodificando [_progressive444]. Entrelaçado, 3 bytes por pixel.
const String _reference444 =
    'e/HjvOu99eia++mF3etkq+o3ZuobLegbAuwBC+kIKekaY+g1pelY1eqB6eqm6+2+vvDl'
    'hO7qROz3G+r8A+3qDfDFS+uhkOWQifjFyPSd+/F2/fNg2fVBp/QaZPIGKvILDPQSF/Mf'
    'OPEzdPJRtPJ14PKc8PLA7/LVt/TsfvPtQfHxG/DuCvPWGfeuV/SJm+54m/Go1O9+/u5T'
    '9u8+zvEjmPAGV+4AIO0KDu8lH+83R+9Uhe53xO+d7O/A8u/e6e3uqe7zbe7qMuzhFurR'
    'Du6wJPKFZvFgqu1Qq9KP3dFl/tI96dQpt9YYgdQIRNIOEdEjCdE6INNRUNNzkNSZz9S9'
    '79bc7NXx2tL5lNXzWdXhIdLIDdGtEtKFLtdYctg3s9UnvKdm5qdA+qge2qsVpKsPbqoM'
    'NKgfBag7CKNXJ6hyXKmZn6e62arY863s5a32zaj2g6vpSKzQEqqtCaaJGaZhP6o4gaod'
    'wakTy3g073gU+3kA0XsClnoMYHkULHguAXpREnKANXaccHjBsnXc6Xju+nz34HzwwXfm'
    'd3fPPHmyCneLC3RlJ3NCVHYil3UR03MN00YZ80YC90YAyEYMiUUgVkQwJUVSAEh1GkKh'
    'P0i9fEfdvkLw8EP1+knv2UneskLKa0OmMUaJBUdhDUQ/M0IlZEISpkMK4UIL1CEa8iAH'
    '8iAHwB8kgB08TRxTHx93ACOcHCOyQyjNgCbqwB/28B/09iTlzyTKpB6xYh+GKCNmACU/'
    'CyMlNyIRbCMDriME5iIK7QMA9AkQ4AcirQY6bwlcMgd9EQOeDAm8KATgYQXmowbr1Abs'
    '9wTo+wPTxweqiAyGTAxaJARDBwMoEwgWRggJiQMKxQUa6wst7wYJ8Q0e2Qo0pQlSZA11'
    'KwqVDAi3CgzRLgrqaAnrqQvo1Azg9QrT8wa4vQmOfA1pPAxAGgUsAwYXFQ0LSw4JjwkS'
    'xwgp6w1A8hcd8Bs30BpTlhl1WB2bIxu8CxjYDRzxOxz2dhzwtx3h3B7K8Rux6ReSrxdk'
    'bxpBKxoiEhcTAxgHICAIWiASnBwp0xlK8hxm9zs67z9Wxjx4hzudSkHCHD/bDTvwFUD/'
    'TT34ijzqyD7P5z+s7z6M3jtqojk+YjseIT4QDzsIDD0FL0EPbkInsT5N4Tx2+j6T+WxY'
    '6G92uGyadGu8O3HdF2/rEWzxIW78XWvmnWnV2Wqv7m6F629j0WtFkmokVWsJGHAKDmwL'
    'FWsSPmsmgGxHvWpy6Wqf/Wu886F73qSZpZ+7YZ7XKqXrEKLrFp/jLKHka5/Gq5yv5JyE'
    '86Ba46I8wKApgJ8VRZ4EDqIQDZ8aHJwtTJtKjptvyJuY6Zy89p3T7s+h1NG+mMzaUMrv'
    'HtH5DdHrG8zUNc7Md9Ckt8yL78pg9c0329Agss4ZcswSNswIB8waDswuJ8tQXct1ncua'
    '1M297c7W8szj6uy7z+zWkOfwSOb/Guz/DOzrH+fNPum/gO+Qv+p29eZL9ugj1+sQquoQ'
    'aecRLucNB+clEelAMepqa+uWre273+/V8e7n8e3u';

/// Cinza de referência de 24x16, lido do raster do ImageIO e não de
/// getRGB(), que aplicaria uma conversão de gama que o JPEG não carrega.
const String _referenceGray =
    '1t/m5d3Qv7KnrLTA0eHo5+HWysG7vMTN3eXr6uHVxLevtb7L3Ozx7+XazcXBw8zW2uHm'
    '49rNvrKttcDO4O3w7N/Txb27wMrVxczPysCzppyao7DA0Nvb1ce6rKSkqrbApq2vqJ2R'
    'hn5+iJentr67s6aYiYKDi5eihYuMhHhtZF5hbHuKmJ2XjX9xY11hanaBYWdnXlFIQTxD'
    'TVxqdnlxZlRHOjc9SFVfRkxMQjUsJyMsNkRSXV9WSjQoHBsjLzxGODo4MCUaFRQgKjhE'
    'TEo+MRsQCAoVIzA6Ojs5MSUbFxYjLTpFSkY4KhgOCAwYJjM9SUlFPDAnJCQzPUlRU0w8'
    'Lh8XExooNkNMZmVgVkpCQUJQW2ZsbGJRQzUvLzlIV2Nri4iBdmpkZGd0fomNi4FwYlRR'
    'U2Bxf4qRr6yjlouFh4uXoautqZ6PgXZ0eYiap7C30c3DtamlqK24wsrKxLmqnpiXnq7A'
    'zNTZ6OPYyr67vsTP2N/e1su8sa+vtsfZ5Ozw';

Uint8List _jpeg(String encoded) => base64.decode(encoded);

/// Estatísticas de uma comparação amostra a amostra.
class _Diff {
  final int max;
  final int different;
  final double mean;
  const _Diff(this.max, this.different, this.mean);
}

_Diff _compare(Uint8List actual, Uint8List reference) {
  expect(actual, hasLength(reference.length));
  var max = 0;
  var different = 0;
  var sum = 0;
  for (var i = 0; i < actual.length; i++) {
    final delta = (actual[i] - reference[i]).abs();
    if (delta != 0) different++;
    if (delta > max) max = delta;
    sum += delta;
  }
  return _Diff(max, different, sum / actual.length);
}

void main() {
  group('JPEG progressivo, contra o oráculo Java (ImageIO)', () {
    test('4:4:4 colorido fica dentro de um par de níveis por amostra', () {
      final image = JpegDecoder.decode(_jpeg(_progressive444));
      final reference = base64.decode(_reference444);

      expect(image.width, equals(24));
      expect(image.height, equals(16));
      expect(image.format, equals(JpegPixelFormat.rgb));

      final diff = _compare(image.pixels, reference);
      // Medido: 27 amostras de 1152 diferem, nenhuma por mais de 2.
      expect(diff.max, lessThanOrEqualTo(2));
      expect(diff.different, lessThanOrEqualTo(60));
      expect(diff.mean, lessThan(0.05));
    });

    test('escala de cinza bate com o raster do Java a menos de um nível', () {
      final image = JpegDecoder.decode(_jpeg(_progressiveGray));
      final reference = base64.decode(_referenceGray);

      expect(image.format, equals(JpegPixelFormat.grayscale));

      final diff = _compare(image.pixels, reference);
      // Medido: 1 amostra de 384 difere, por 1 nível.
      expect(diff.max, lessThanOrEqualTo(1));
      expect(diff.different, lessThanOrEqualTo(8));
    });

    test('a imagem tem estrutura, não é um campo chapado', () {
      final pixels = JpegDecoder.decode(_jpeg(_progressive444)).pixels;
      var min = 255;
      var max = 0;
      for (final value in pixels) {
        if (value < min) min = value;
        if (value > max) max = value;
      }
      // Se as varreduras AC fossem descartadas sobrariam só os DC e cada bloco
      // de 8x8 sairia uniforme; a amplitude denuncia isso.
      expect(max - min, greaterThan(200));
    });
  });

  group('JPEG progressivo reproduz o sequencial bit a bit', () {
    void samePixels(String progressive, String sequential) {
      final a = JpegDecoder.decode(_jpeg(progressive));
      final b = JpegDecoder.decode(_jpeg(sequential));
      expect(a.width, equals(b.width));
      expect(a.height, equals(b.height));
      expect(a.format, equals(b.format));
      expect(a.pixels, orderedEquals(b.pixels));
    }

    test('4:4:4', () => samePixels(_progressive444, _sequential444));

    test('4:2:2', () => samePixels(_progressive422, _sequential422));

    test('4:2:0', () => samePixels(_progressive420, _sequential420));

    test(
        'escala de cinza', () => samePixels(_progressiveGray, _sequentialGray));

    test(
        '17x9 em 4:2:0, onde a grade não intercalada é mais estreita que a '
        'grade de MCUs', () {
      // 17 pixels de largura com fator 2 dão ceil(17/8) = 3 blocos de luma por
      // linha numa varredura de um componente só, contra 2*ceil(17/16) = 4 na
      // grade preenchida de MCUs. Usar a segunda contagem cisalha a imagem.
      samePixels(_progressive17x9, _sequential17x9);
    });

    test('com intervalo de restart (DRI) e marcadores RSTn', () {
      // Mesmo original e mesma subamostragem do 4:2:0 acima, só que com
      // DRI = 1: os preditores DC têm de zerar a cada intervalo.
      samePixels(_progressiveRestart, _sequential420);
    });

    test('96x64 com DRI = 3 e 166 marcadores RSTn', () {
      // O caso anterior tem um intervalo por MCU, o que quase não exercita o
      // realinhamento. Aqui há 166 RSTn espalhados por onze varreduras, e a
      // busca do próximo marcador de segmento entre varreduras tem de
      // atravessá-los sem confundi-los com um cabeçalho.
      samePixels(_progressiveRestartWide, _sequentialWide);
    });
  });

  group('cabeçalho', () {
    test('probe aceita SOF2 em vez de recusar o arquivo', () {
      final info = JpegDecoder.probe(_jpeg(_progressive444));

      expect(info.width, equals(24));
      expect(info.height, equals(16));
      expect(info.components, equals(3));
      expect(info.decodable, isTrue);
      expect(info.reason, isNull);
    });

    test('tabela de Huffman sobre-inscrita vira exceção declarada', () {
      // Não é específico do progressivo, mas é o mesmo caminho de tabelas que
      // as varreduras progressivas usam onze vezes por arquivo. Três códigos
      // de um bit não cabem em um bit: antes isso estourava um RangeError que
      // um chamador que só captura JpegDecodeException não conseguia tratar.
      final bytes = Uint8List.fromList([
        0xFF, 0xD8, //
        0xFF, 0xC4, 0x00, 0x16, 0x00,
        3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0x01, 0x02, 0x03,
        0xFF, 0xD9,
      ]);

      expect(
          () => JpegDecoder.probe(bytes),
          throwsA(isA<JpegDecodeException>().having(
              (e) => e.message, 'message', contains('over-subscribed'))));
    });

    test('arquivo de codificação aritmética continua recusado', () {
      // SOF9: DCT sequencial, codificação aritmética.
      final bytes = Uint8List.fromList([
        0xFF, 0xD8, //
        0xFF, 0xC9, 0x00, 0x0B, 0x08, 0x00, 0x10, 0x00, 0x18, 0x01, 0x01,
        0x11, 0x00,
        0xFF, 0xD9,
      ]);
      final info = JpegDecoder.probe(bytes);

      expect(info.decodable, isFalse);
      expect(info.reason, contains('Arithmetic'));
      expect(
          () => JpegDecoder.decode(bytes), throwsA(isA<JpegDecodeException>()));
    });
  });
}
