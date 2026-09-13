///
///
/// dpdf a dart PDF library
library;

export 'package:dgfx/dgfx.dart'
    show
        BLCallbackFontProvider,
        BLFontBytesProvider,
        BLFontCollection,
        BLFontProvider,
        BLFontQuery,
        BLFontSlant;

export 'src/editing/pdf_page_assembly.dart';
export 'src/editing/pdf_page_overlay.dart';
export 'src/compatibility/pdf_percent_comments.dart';
export 'src/compatibility/certificate_serial.dart';
export 'src/compatibility/pdf_quick_info.dart';
export 'src/editing/pdf_text_extraction.dart';
export 'src/editing/pdf_unicode_cmap.dart';
export 'src/editing/pdf_simple_encoding.dart';
export 'src/editing/pdf_standard_font_metrics.dart';
export 'src/html/html_to_pdf.dart';

// SVG: desenho vetorial em cima do canvas do kernel.
export 'src/svg/svg_converter.dart';
export 'src/svg/svg_resource_loader.dart';

export 'src/commons/exceptions/dpdf_exception.dart';

export 'src/io/exceptions/io_exception.dart';
export 'src/io/exceptions/io_exception_message_constant.dart';

export 'src/io/source/random_access_source.dart';
export 'src/io/source/array_random_access_source.dart';
export 'src/io/source/independent_random_access_source.dart';
export 'src/io/source/thread_safe_random_access_source.dart';
export 'src/io/source/byte_buffer.dart';
export 'src/io/source/byte_utils.dart';
export 'src/io/source/random_access_file_or_array.dart';
export 'src/io/source/pdf_tokenizer.dart';

export 'src/kernel/pdf/pdf_object.dart';
export 'src/kernel/pdf/pdf_boolean.dart';
export 'src/kernel/pdf/pdf_null.dart';
export 'src/kernel/pdf/pdf_number.dart';
export 'src/kernel/pdf/pdf_string.dart';
export 'src/kernel/pdf/pdf_name.dart';
export 'src/kernel/pdf/pdf_array.dart';
export 'src/kernel/pdf/pdf_dictionary.dart';
export 'src/kernel/pdf/pdf_stream.dart';
export 'src/kernel/pdf/pdf_primitive_object.dart';
export 'src/kernel/pdf/pdf_literal.dart';
export 'src/kernel/pdf/pdf_xref_table.dart';
export 'src/kernel/pdf/pdf_reader.dart';
export 'src/kernel/pdf/pdf_document.dart';
export 'src/kernel/pdf/pdf_catalog.dart';
export 'src/kernel/pdf/pdf_page.dart';
export 'src/kernel/pdf/pdf_pages_tree.dart';
export 'src/kernel/pdf/pdf_writer.dart';
export 'src/kernel/pdf/pdf_linearization.dart';
export 'src/kernel/pdf/stamping_properties.dart';
export 'src/kernel/pdf/pdf_output_intent.dart';
export 'src/kernel/pdf/canvas/pdf_canvas.dart';
export 'src/kernel/geom/rectangle.dart';
export 'src/kernel/font/pdf_font.dart';
export 'src/kernel/font/pdf_font_factory.dart';
export 'src/io/font/pdf_encodings.dart';
export 'src/io/font/cjk_resource_loader.dart';
export 'src/io/font/cjk_resource_provider.dart';

export 'src/sign/simple_signature_appearance.dart';
export 'src/sign/pdf_signer.dart';
export 'src/sign/external_signature.dart';
export 'src/sign/external_signature_container.dart';
export 'src/sign/signer_properties.dart';

export 'src/kernel/exceptions/kernel_exception_message_constant.dart';
export 'src/kernel/exceptions/pdf_exception.dart';

export 'src/kernel/utils/filter_handlers.dart';
export 'src/kernel/xmp/xmp_meta.dart';
export 'src/kernel/xmp/xmp_const.dart';
export 'src/kernel/xmp/pdf_const.dart';

export 'src/forms/pdf_acro_form.dart';
export 'src/forms/fields/pdf_form_field.dart';
export 'src/forms/fields/pdf_text_form_field.dart';
export 'src/forms/fields/pdf_button_form_field.dart';
export 'src/forms/fields/pdf_choice_form_field.dart';
export 'src/forms/fields/pdf_signature_form_field.dart';
export 'src/kernel/pdf/annot/pdf_annotation.dart';
export 'src/kernel/pdf/annot/pdf_widget_annotation.dart';

export 'src/pki/jks_key_store.dart';
export 'src/pki/bks_key_store.dart';

export 'src/io/source/pdf_byte_source.dart';
export 'src/io/source/pdf_file_source.dart';
export 'src/kernel/pdf/reader_properties.dart';

// Layout: high level text and block composition on top of the kernel.
export 'src/layout/document.dart';
export 'src/layout/canvas.dart';
export 'src/layout/root_element.dart';
export 'src/layout/style.dart';
export 'src/layout/property_container.dart';
export 'src/layout/element_property_container.dart';
export 'src/layout/element/element.dart';
export 'src/layout/element/abstract_element.dart';
export 'src/layout/element/block_element.dart';
export 'src/layout/element/block_content.dart';
export 'src/layout/element/leaf_content.dart';
export 'src/layout/element/area_break.dart';
export 'src/layout/element/cell.dart';
export 'src/layout/element/div.dart';
export 'src/layout/element/image.dart';
export 'src/layout/element/list.dart';
export 'src/layout/element/list_item.dart';
export 'src/layout/element/paragraph.dart';
export 'src/layout/element/table.dart';
export 'src/layout/element/text.dart';
export 'src/layout/borders/border.dart';
export 'src/layout/font/font_provider.dart';
export 'src/layout/layout/layout_area.dart';
export 'src/layout/layout/layout_context.dart';
export 'src/layout/layout/layout_result.dart';
export 'src/layout/layout/root_layout_area.dart';
export 'src/layout/layout/text_layout_result.dart';
export 'src/layout/properties/background.dart';
export 'src/layout/properties/base_direction.dart';
export 'src/layout/properties/clear_property_value.dart';
export 'src/layout/properties/float_property_value.dart';
export 'src/layout/properties/horizontal_alignment.dart';
export 'src/layout/properties/layout_position.dart';
export 'src/layout/properties/leading.dart';
export 'src/layout/properties/list_numbering_type.dart';
export 'src/layout/properties/list_symbol_alignment.dart';
export 'src/layout/properties/list_symbol_position.dart';
export 'src/layout/properties/overflow_property_value.dart';
export 'src/layout/properties/property.dart';
export 'src/layout/properties/text_alignment.dart';
export 'src/layout/properties/transparent_color.dart';
export 'src/layout/properties/unit_value.dart';
export 'src/layout/properties/vertical_alignment.dart';
export 'src/layout/renderer/renderer.dart';
export 'src/layout/renderer/draw_context.dart';

// Geometry and colour helpers shared by the kernel and the layout module.
export 'src/kernel/geom/page_size.dart';
export 'src/kernel/geom/affine_transform.dart';
export 'src/kernel/geom/point.dart';
export 'src/kernel/geom/vector.dart';
export 'src/kernel/geom/matrix.dart';
export 'src/kernel/colors/color.dart';
export 'src/kernel/colors/color_constants.dart';
export 'src/kernel/colors/device_cmyk.dart';
export 'src/kernel/colors/device_gray.dart';
export 'src/kernel/colors/device_rgb.dart';

// Fonts and images used when composing content.
export 'src/io/font/constants/standard_fonts.dart';
export 'src/io/font/true_type_font.dart';
export 'src/io/font/true_type_collection.dart';
export 'src/io/font/font_program.dart';
export 'src/io/font/font_program_factory.dart';
export 'src/io/image/image_data.dart';
export 'src/io/image/image_data_factory.dart';
export 'src/kernel/pdf/xobject/pdf_image_x_object.dart';
export 'src/kernel/pdf/xobject/pdf_form_x_object.dart';
export 'src/kernel/pdf/xobject/pdf_x_object.dart';

// Barcodes.
export 'src/barcodes/barcode_1d.dart';
export 'src/barcodes/barcode_2d.dart';
export 'src/barcodes/barcode_39.dart';
export 'src/barcodes/barcode_128.dart';
export 'src/barcodes/barcode_ean.dart';
export 'src/barcodes/barcode_qr_code.dart';

// Editing helpers beyond the low level object model.
export 'src/editing/pdf_form_merge.dart';

// Structural inspection: does this file open, and what would break a reader.
export 'src/validation/pdf_integrity.dart';
export 'src/validation/pdf_image_inventory.dart';

// Conformance: PDF/A archival and PDF/UA accessibility verification.
export 'src/conformance/pdf_conformance.dart';
export 'src/conformance/pdf_conformance_report.dart';
export 'src/conformance/pdf_a_verifier.dart';
export 'src/conformance/pdf_ua_verifier.dart';
export 'src/conformance/xmp_identification.dart';
export 'src/conformance/finding_sink.dart';

// Writer configuration: compression level, object streams, encryption.
export 'src/kernel/pdf/writer_properties.dart';
export 'src/kernel/pdf/encryption_constants.dart';
export 'src/kernel/pdf/pdf_version.dart';

// Compression: rewrite a document smaller without changing what it draws.
export 'src/compress/pdf_compression_options.dart';
export 'src/compress/pdf_compressor.dart';
export 'src/compress/pdf_image_compressor.dart';

// Image codecs and resampling, used by the compressor and available directly.
export 'src/io/image/jpeg_decoder.dart';
export 'src/io/image/jpeg_encoder.dart';
export 'src/io/image/image_resampler.dart';
export 'src/io/image/png_encoder.dart';

// Content stream parsing, shared by rendering, extraction and rewriting.
export 'src/render/content_parser.dart';
// `PdfFontFallback`, `PdfFontRequest` e `PdfGlyphFailure` fazem parte da API
// do renderizador: aparecem nas opções e no relatório.
export 'src/render/glyph_source.dart'
    show
        PdfFontFallback,
        PdfFontRequest,
        PdfGlyphFailure,
        pdfFontFallbackFromCollection;
export 'src/render/image_decoder.dart';
export 'src/render/page_renderer.dart';
// Substitutas para as fontes que o PDF referencia sem embutir: as URW Core 35
// que viajam no pacote, e o catálogo instalado na máquina. Ambas resolvem para
// nada na web, onde não há bytes de fonte a ler.
export 'src/render/standard_fonts.dart';
export 'src/render/system_fonts.dart';

// Multimedia features: ISO 32000-1:2008, clause 13.
export 'src/kernel/pdf/multimedia/multimedia.dart';
export 'src/kernel/pdf/filespec/pdf_file_spec.dart';
export 'src/kernel/pdf/annot/pdf_media_annotations.dart';
export 'src/kernel/pdf/annot/pdf_3d_annotation.dart';
export 'src/kernel/pdf/action/pdf_action_sound.dart';
export 'src/kernel/pdf/action/pdf_action_movie.dart';
export 'src/kernel/pdf/action/pdf_action_rendition.dart';

// Document structure and page navigation: ISO 32000-1:2008, 7.7.2 (catalog),
// 12.2 (viewer preferences), 12.4.3 (articles), 12.4.4 (presentations),
// 12.9 (measurement properties), 12.10 (requirements) and 14.5 (page pieces).
export 'src/kernel/pdf/viewer/pdf_viewer_preferences.dart';
export 'src/kernel/pdf/viewer/pdf_page_layout.dart';
export 'src/kernel/pdf/viewer/pdf_mark_info.dart';
export 'src/kernel/pdf/viewer/pdf_legal_attestation.dart';
export 'src/kernel/pdf/viewer/pdf_uri_dictionary.dart';
export 'src/kernel/pdf/viewer/pdf_transition.dart';
export 'src/kernel/pdf/viewer/pdf_page_piece.dart';
export 'src/kernel/pdf/viewer/pdf_requirement.dart';
export 'src/kernel/pdf/viewer/pdf_measure.dart';
export 'src/kernel/pdf/article/pdf_article_thread.dart';
export 'src/kernel/pdf/article/pdf_bead.dart';

// Prepress support, ISO 32000-1:2008, 14.11.
export 'src/kernel/pdf/prepress/pdf_page_boundaries.dart';
export 'src/kernel/pdf/prepress/pdf_box_color_info.dart';
export 'src/kernel/pdf/prepress/pdf_separation_info.dart';
export 'src/kernel/pdf/prepress/pdf_printer_mark_form.dart';
export 'src/kernel/pdf/prepress/pdf_trap_network.dart';

// Web Capture, ISO 32000-1:2008, 14.10.
export 'src/kernel/pdf/webcapture/web_capture_names.dart';
export 'src/kernel/pdf/webcapture/pdf_web_capture_info.dart';
export 'src/kernel/pdf/webcapture/pdf_web_capture_command.dart';
export 'src/kernel/pdf/webcapture/pdf_web_capture_content_set.dart';
export 'src/kernel/pdf/webcapture/pdf_web_capture_source.dart';
export 'src/kernel/pdf/webcapture/pdf_web_capture_database.dart';
