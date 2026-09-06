import 'package:dpdf/src/styledxmlparser/css/css_style_sheet.dart';
import 'package:dpdf/src/styledxmlparser/css/media/media_device_description.dart';
import 'package:dpdf/src/styledxmlparser/resolver/resource/resource_resolver.dart';

class SvgProcessorContext {
  ResourceResolver getResourceResolver() => ResourceResolver(null);
  CssStyleSheet getCssStyleSheet() => CssStyleSheet();
  MediaDeviceDescription getDeviceDescription() =>
      MediaDeviceDescription.createDefault();
}
