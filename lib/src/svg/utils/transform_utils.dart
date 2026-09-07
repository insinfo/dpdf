import 'dart:math' as math;
import 'package:pdfcraft/src/kernel/geom/affine_transform.dart';
import 'package:pdfcraft/src/styledxmlparser/css/util/css_dimension_parsing_utils.dart';
import 'package:pdfcraft/src/svg/exceptions/svg_exception_message_constant.dart';
import 'package:pdfcraft/src/svg/exceptions/svg_processing_exception.dart';
import 'package:pdfcraft/src/svg/utils/svg_css_utils.dart';

class CraftTransformUtils {
  CraftTransformUtils._();

  static const String MATRIX = "MATRIX";
  static const String ROTATE = "ROTATE";
  static const String SCALE = "SCALE";
  static const String SKEWX = "SKEWX";
  static const String SKEWY = "SKEWY";
  static const String TRANSLATE = "TRANSLATE";

  static CraftAffineTransform parseTransform(String transform) {
    if (transform.trim().isEmpty) {
      throw CraftSvgProcessingException(
          CraftSvgExceptionMessageConstant.TRANSFORM_EMPTY);
    }

    CraftAffineTransform matrix = CraftAffineTransform();
    List<String> listWithTransformations = _splitString(transform);
    for (String transformation in listWithTransformations) {
      CraftAffineTransform? newMatrix =
          _transformationStringToMatrix(transformation);
      if (newMatrix != null) {
        matrix.concatenate(newMatrix);
      }
    }
    return matrix;
  }

  static List<String> _splitString(String transform) {
    List<String> list = [];
    int start = 0;
    while (true) {
      int end = transform.indexOf(')', start);
      if (end == -1) {
        if (transform.substring(start).trim().isNotEmpty) {
          throw CraftSvgProcessingException(
              CraftSvgExceptionMessageConstant.INVALID_TRANSFORM_DECLARATION);
        }
        break;
      }
      String trim = transform.substring(start, end + 1).trim();
      if (trim.isNotEmpty) {
        if (trim.startsWith(',')) {
          trim = trim.substring(1).trim();
        }
        if (trim.isNotEmpty) {
          list.add(trim);
        }
      }
      start = end + 1;
    }
    if (list.isEmpty) {
      throw CraftSvgProcessingException(
          CraftSvgExceptionMessageConstant.INVALID_TRANSFORM_DECLARATION);
    }
    return list;
  }

  static CraftAffineTransform? _transformationStringToMatrix(
      String transformation) {
    String name = _getNameFromString(transformation).toUpperCase();
    if (name.isEmpty) {
      throw CraftSvgProcessingException(
          CraftSvgExceptionMessageConstant.INVALID_TRANSFORM_DECLARATION);
    }

    List<String> values = _getValuesFromTransformationString(transformation);

    switch (name) {
      case MATRIX:
        return _createMatrixTransformation(values);
      case TRANSLATE:
        return _createTranslateTransformation(values);
      case SCALE:
        return _createScaleTransformation(values);
      case ROTATE:
        return _createRotationTransformation(values);
      case SKEWX:
        return _createSkewXTransformation(values);
      case SKEWY:
        return _createSkewYTransformation(values);
      default:
        throw CraftSvgProcessingException(
            CraftSvgExceptionMessageConstant.UNKNOWN_TRANSFORMATION_TYPE);
    }
  }

  static CraftAffineTransform _createSkewYTransformation(List<String> values) {
    if (values.length != 1) {
      throw CraftSvgProcessingException(CraftSvgExceptionMessageConstant
          .TRANSFORM_INCORRECT_NUMBER_OF_VALUES);
    }
    double tan = math.tan(_toRadians(_parseTransformationValue(values[0])));
    return CraftAffineTransform.fromValues(1, tan, 0, 1, 0, 0);
  }

  static CraftAffineTransform _createSkewXTransformation(List<String> values) {
    if (values.length != 1) {
      throw CraftSvgProcessingException(CraftSvgExceptionMessageConstant
          .TRANSFORM_INCORRECT_NUMBER_OF_VALUES);
    }
    double tan = math.tan(_toRadians(_parseTransformationValue(values[0])));
    return CraftAffineTransform.fromValues(1, 0, tan, 1, 0, 0);
  }

  static CraftAffineTransform _createRotationTransformation(
      List<String> values) {
    if (values.length != 1 && values.length != 3) {
      throw CraftSvgProcessingException(CraftSvgExceptionMessageConstant
          .TRANSFORM_INCORRECT_NUMBER_OF_VALUES);
    }
    double angle = _toRadians(_parseTransformationValue(values[0]));
    if (values.length == 3) {
      double centerX =
          CraftCssDimensionParsingUtils.parseAbsoluteLength(values[1]);
      double centerY =
          CraftCssDimensionParsingUtils.parseAbsoluteLength(values[2]);
      return CraftAffineTransform.getRotateInstanceAround(
          angle, centerX, centerY);
    }
    return CraftAffineTransform.getRotateInstance(angle);
  }

  static CraftAffineTransform _createScaleTransformation(List<String> values) {
    if (values.isEmpty || values.length > 2) {
      throw CraftSvgProcessingException(CraftSvgExceptionMessageConstant
          .TRANSFORM_INCORRECT_NUMBER_OF_VALUES);
    }
    double scaleX =
        CraftCssDimensionParsingUtils.parseRelativeValue(values[0], 1.0);
    double scaleY = values.length == 2
        ? CraftCssDimensionParsingUtils.parseRelativeValue(values[1], 1.0)
        : scaleX;
    return CraftAffineTransform.getScaleInstance(scaleX, scaleY);
  }

  static CraftAffineTransform _createTranslateTransformation(
      List<String> values) {
    if (values.isEmpty || values.length > 2) {
      throw CraftSvgProcessingException(CraftSvgExceptionMessageConstant
          .TRANSFORM_INCORRECT_NUMBER_OF_VALUES);
    }
    double translateX =
        CraftCssDimensionParsingUtils.parseAbsoluteLength(values[0]);
    double translateY = values.length == 2
        ? CraftCssDimensionParsingUtils.parseAbsoluteLength(values[1])
        : 0.0;
    return CraftAffineTransform.getTranslateInstance(translateX, translateY);
  }

  static CraftAffineTransform _createMatrixTransformation(List<String> values) {
    if (values.length != 6) {
      throw CraftSvgProcessingException(CraftSvgExceptionMessageConstant
          .TRANSFORM_INCORRECT_NUMBER_OF_VALUES);
    }
    double a = double.parse(values[0]);
    double b = double.parse(values[1]);
    double c = double.parse(values[2]);
    double d = double.parse(values[3]);
    double e = CraftCssDimensionParsingUtils.parseAbsoluteLength(values[4]);
    double f = CraftCssDimensionParsingUtils.parseAbsoluteLength(values[5]);
    return CraftAffineTransform.fromValues(a, b, c, d, e, f);
  }

  static String _getNameFromString(String transformation) {
    int indexOfParenthesis = transformation.indexOf("(");
    if (indexOfParenthesis == -1) {
      throw CraftSvgProcessingException(
          CraftSvgExceptionMessageConstant.INVALID_TRANSFORM_DECLARATION);
    }
    return transformation.substring(0, indexOfParenthesis);
  }

  static List<String> _getValuesFromTransformationString(
      String transformation) {
    int open = transformation.indexOf('(');
    int close = transformation.indexOf(')');
    if (open == -1 || close == -1 || close <= open) {
      return [];
    }
    String numbers = transformation.substring(open + 1, close);
    return CraftSvgCssUtils.splitValueList(numbers);
  }

  static double _parseTransformationValue(String valueStr) {
    double? valueParsed = CraftCssDimensionParsingUtils.parseFloat(valueStr);
    if (valueParsed == null) {
      throw CraftSvgProcessingException("Invalid transform value: $valueStr");
    }
    return valueParsed;
  }

  static double _toRadians(double degrees) {
    return degrees * math.pi / 180.0;
  }
}
