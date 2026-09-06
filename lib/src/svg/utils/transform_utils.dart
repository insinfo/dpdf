import 'dart:math' as math;
import 'package:dpdf/src/kernel/geom/affine_transform.dart';
import 'package:dpdf/src/styledxmlparser/css/util/css_dimension_parsing_utils.dart';
import 'package:dpdf/src/svg/exceptions/svg_exception_message_constant.dart';
import 'package:dpdf/src/svg/exceptions/svg_processing_exception.dart';
import 'package:dpdf/src/svg/utils/svg_css_utils.dart';

class TransformUtils {
  TransformUtils._();

  static const String MATRIX = "MATRIX";
  static const String ROTATE = "ROTATE";
  static const String SCALE = "SCALE";
  static const String SKEWX = "SKEWX";
  static const String SKEWY = "SKEWY";
  static const String TRANSLATE = "TRANSLATE";

  static AffineTransform parseTransform(String transform) {
    if (transform.isEmpty) {
      throw SvgProcessingException(SvgExceptionMessageConstant.TRANSFORM_EMPTY);
    }

    AffineTransform matrix = AffineTransform();
    List<String> listWithTransformations = _splitString(transform);
    for (String transformation in listWithTransformations) {
      AffineTransform? newMatrix =
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
      if (end == -1) break;
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
    return list;
  }

  static AffineTransform? _transformationStringToMatrix(String transformation) {
    String name = _getNameFromString(transformation).toUpperCase();
    if (name.isEmpty) {
      throw SvgProcessingException(
          SvgExceptionMessageConstant.INVALID_TRANSFORM_DECLARATION);
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
        throw SvgProcessingException(
            SvgExceptionMessageConstant.UNKNOWN_TRANSFORMATION_TYPE);
    }
  }

  static AffineTransform _createSkewYTransformation(List<String> values) {
    if (values.length != 1) {
      throw SvgProcessingException(
          SvgExceptionMessageConstant.TRANSFORM_INCORRECT_NUMBER_OF_VALUES);
    }
    double tan = math.tan(_toRadians(_parseTransformationValue(values[0])));
    return AffineTransform.fromValues(1, tan, 0, 1, 0, 0);
  }

  static AffineTransform _createSkewXTransformation(List<String> values) {
    if (values.length != 1) {
      throw SvgProcessingException(
          SvgExceptionMessageConstant.TRANSFORM_INCORRECT_NUMBER_OF_VALUES);
    }
    double tan = math.tan(_toRadians(_parseTransformationValue(values[0])));
    return AffineTransform.fromValues(1, 0, tan, 1, 0, 0);
  }

  static AffineTransform _createRotationTransformation(List<String> values) {
    if (values.length != 1 && values.length != 3) {
      throw SvgProcessingException(
          SvgExceptionMessageConstant.TRANSFORM_INCORRECT_NUMBER_OF_VALUES);
    }
    double angle = _toRadians(_parseTransformationValue(values[0]));
    if (values.length == 3) {
      double centerX = CssDimensionParsingUtils.parseAbsoluteLength(values[1]);
      double centerY = CssDimensionParsingUtils.parseAbsoluteLength(values[2]);
      return AffineTransform.getRotateInstanceAround(angle, centerX, centerY);
    }
    return AffineTransform.getRotateInstance(angle);
  }

  static AffineTransform _createScaleTransformation(List<String> values) {
    if (values.isEmpty || values.length > 2) {
      throw SvgProcessingException(
          SvgExceptionMessageConstant.TRANSFORM_INCORRECT_NUMBER_OF_VALUES);
    }
    double scaleX = CssDimensionParsingUtils.parseRelativeValue(values[0], 1.0);
    double scaleY = values.length == 2
        ? CssDimensionParsingUtils.parseRelativeValue(values[1], 1.0)
        : scaleX;
    return AffineTransform.getScaleInstance(scaleX, scaleY);
  }

  static AffineTransform _createTranslateTransformation(List<String> values) {
    if (values.isEmpty || values.length > 2) {
      throw SvgProcessingException(
          SvgExceptionMessageConstant.TRANSFORM_INCORRECT_NUMBER_OF_VALUES);
    }
    double translateX = CssDimensionParsingUtils.parseAbsoluteLength(values[0]);
    double translateY = values.length == 2
        ? CssDimensionParsingUtils.parseAbsoluteLength(values[1])
        : 0.0;
    return AffineTransform.getTranslateInstance(translateX, translateY);
  }

  static AffineTransform _createMatrixTransformation(List<String> values) {
    if (values.length != 6) {
      throw SvgProcessingException(
          SvgExceptionMessageConstant.TRANSFORM_INCORRECT_NUMBER_OF_VALUES);
    }
    double a = double.parse(values[0]);
    double b = double.parse(values[1]);
    double c = double.parse(values[2]);
    double d = double.parse(values[3]);
    double e = CssDimensionParsingUtils.parseAbsoluteLength(values[4]);
    double f = CssDimensionParsingUtils.parseAbsoluteLength(values[5]);
    return AffineTransform.fromValues(a, b, c, d, e, f);
  }

  static String _getNameFromString(String transformation) {
    int indexOfParenthesis = transformation.indexOf("(");
    if (indexOfParenthesis == -1) {
      throw SvgProcessingException(
          SvgExceptionMessageConstant.INVALID_TRANSFORM_DECLARATION);
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
    return SvgCssUtils.splitValueList(numbers);
  }

  static double _parseTransformationValue(String valueStr) {
    double? valueParsed = CssDimensionParsingUtils.parseFloat(valueStr);
    if (valueParsed == null) {
      throw SvgProcessingException("Invalid transform value: $valueStr");
    }
    return valueParsed;
  }

  static double _toRadians(double degrees) {
    return degrees * math.pi / 180.0;
  }
}
