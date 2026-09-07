import 'package:dpdf/src/styledxmlparser/css/css_style_sheet.dart';
import 'package:dpdf/src/styledxmlparser/css/media/media_device_description.dart';
import 'package:dpdf/src/styledxmlparser/resolver/resource/resource_resolver.dart';

class CraftSvgProcessorContext {
  CraftResourceResolver getResourceResolver() => CraftResourceResolver(null);
  CraftCssStyleSheet getCssStyleSheet() => CraftCssStyleSheet();
  CraftMediaDeviceDescription getDeviceDescription() =>
      CraftMediaDeviceDescription.createDefault();
}
