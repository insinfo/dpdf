import 'dart:typed_data';

import 'package:dpdf/src/kernel/pdf/layer/pdf_optional_content_config.dart';
import 'package:dpdf/src/kernel/pdf/layer/pdf_optional_content_group.dart';
import 'package:dpdf/src/kernel/pdf/layer/pdf_optional_content_membership.dart';
import 'package:dpdf/src/kernel/pdf/layer/pdf_optional_content_name.dart';
import 'package:dpdf/src/kernel/pdf/layer/pdf_optional_content_properties.dart';
import 'package:dpdf/src/kernel/pdf/layer/pdf_optional_content_state.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_object.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/canvas/pdf_canvas.dart';
import 'package:test/test.dart';

PdfName _n(String value) => PdfName.intern(value);

/// A group dictionary detached from any document.
PdfDictionary _group(String name) =>
    PdfOptionalContentGroup(name).pdfRepresentation();

/// A configuration dictionary built from raw entries.
PdfOptionalContentConfiguration _config(Map<String, PdfObject> entries) {
  final dict = PdfDictionary();
  entries.forEach((key, value) => dict.put(_n(key), value));
  return PdfOptionalContentConfiguration.fromDictionary(dict);
}

PdfArray _array(List<PdfObject> objects) => PdfArray.fromList(objects);

void main() {
  group('Optional content groups (8.11.2)', () {
    test('a new group carries /Type /OCG and its /Name', () async {
      final ocg = PdfOptionalContentGroup('Camada 1');
      expect(await ocg.pdfRepresentation().nameEntry(PdfOcName.type),
          PdfOcName.ocg);
      expect(await ocg.getName(), 'Camada 1');
    });

    test('a name outside latin-1 round trips through UTF-16BE', () async {
      final ocg = PdfOptionalContentGroup('Kałá 中文');
      final raw =
          await ocg.pdfRepresentation().stringEntry(PdfOcName.name) as PdfString;
      expect(raw.getValueBytes()!.take(2), <int>[0xFE, 0xFF]);
      expect(await ocg.getName(), 'Kałá 中文');
    });

    test('/Intent defaults to View and accepts both forms', () async {
      final ocg = PdfOptionalContentGroup('x');
      expect(await ocg.getIntents(), <PdfName>[PdfOcName.view]);

      ocg.setIntents(<PdfName>[PdfOcName.design]);
      expect(await ocg.pdfRepresentation().get(PdfOcName.intent, true),
          isA<PdfName>());
      expect(await ocg.getIntents(), <PdfName>[PdfOcName.design]);

      ocg.setIntents(<PdfName>[PdfOcName.view, PdfOcName.design]);
      expect(await ocg.getIntents(),
          <PdfName>[PdfOcName.view, PdfOcName.design]);
    });

    test('parse rejects a dictionary that is not an /OCG', () async {
      expect(await PdfOptionalContentGroup.parse(PdfDictionary()), isNull);
      final ocmd = PdfDictionary()..put(PdfOcName.type, PdfOcName.ocmd);
      expect(await PdfOptionalContentGroup.parse(ocmd), isNull);
    });
  });

  group('Usage dictionary (8.11.4.4, table 102)', () {
    test('every category round trips', () async {
      final ocg = PdfOptionalContentGroup('usage');
      final usage = await ocg.usageDirectory();
      usage.setCreatorInfo('dpdf', _n('Technical'));
      usage.setLanguage('es-MX', preferred: true);
      usage.setExportState(false);
      usage.setZoom(min: 1.0, max: 2.0);
      usage.setPrint(subtype: _n('Watermark'), printState: true);
      usage.setViewState(true);
      usage.setUser(_n('Org'), <String>['Acme', 'Acme Brasil']);
      usage.setPageElement(_n('HF'));

      final reread = (await ocg.getUsage())!;
      expect(await reread.getCreator(), 'dpdf');
      expect(await reread.getCreatorSubtype(), _n('Technical'));
      expect(await reread.getLanguage(), 'es-MX');
      expect(await reread.isLanguagePreferred(), isTrue);
      expect(await reread.getExportState(), isFalse);
      expect(await reread.getZoomMin(), 1.0);
      expect(await reread.getZoomMax(), 2.0);
      expect(await reread.getPrintSubtype(), _n('Watermark'));
      expect(await reread.getPrintState(), isTrue);
      expect(await reread.getViewState(), isTrue);
      expect(await reread.getUserType(), _n('Org'));
      expect(await reread.getUserNames(), <String>['Acme', 'Acme Brasil']);
      expect(await reread.getPageElementSubtype(), _n('HF'));
    });

    test('absent entries use the defaults of table 102', () async {
      final usage = PdfOptionalContentUsage();
      expect(await usage.getZoomMin(), 0.0);
      expect(await usage.getZoomMax(), double.infinity);
      // An absent /PrintState leaves the group unchanged, which reads as null
      // rather than OFF.
      expect(await usage.getPrintState(), isNull);
      expect(await usage.isLanguagePreferred(), isFalse);
    });
  });

  group('Membership dictionaries (8.11.2.2)', () {
    late PdfDictionary a;
    late PdfDictionary b;
    late PdfOptionalContentState state;

    setUp(() async {
      a = _group('A');
      b = _group('B');
      state = PdfOptionalContentState();
      state.setGroupOn(a, true);
      state.setGroupOn(b, false);
    });

    Future<bool> visible(PdfName policy) async {
      final ocmd = PdfDictionary()
        ..put(PdfOcName.type, PdfOcName.ocmd)
        ..put(PdfOcName.ocgs, _array(<PdfObject>[a, b]))
        ..put(PdfOcName.p, policy);
      return state.isVisible(ocmd);
    }

    test('/P applies the four policies of table 99', () async {
      expect(await visible(PdfOcName.anyOn), isTrue);
      expect(await visible(PdfOcName.allOn), isFalse);
      expect(await visible(PdfOcName.anyOff), isTrue);
      expect(await visible(PdfOcName.allOff), isFalse);
    });

    test('/P defaults to AnyOn and an empty /OCGs has no effect', () async {
      final noPolicy = PdfDictionary()
        ..put(PdfOcName.type, PdfOcName.ocmd)
        ..put(PdfOcName.ocgs, _array(<PdfObject>[b]));
      expect(await state.isVisible(noPolicy), isFalse);

      final empty = PdfDictionary()
        ..put(PdfOcName.type, PdfOcName.ocmd)
        ..put(PdfOcName.ocgs, PdfArray())
        ..put(PdfOcName.p, PdfOcName.allOn);
      expect(await state.isVisible(empty), isTrue);
    });

    test('null and non-group entries in /OCGs are ignored', () async {
      final ocmd = PdfDictionary()
        ..put(PdfOcName.type, PdfOcName.ocmd)
        ..put(
            PdfOcName.ocgs,
            _array(<PdfObject>[
              PdfDictionary(), // not an /OCG
              b,
            ]))
        ..put(PdfOcName.p, PdfOcName.allOff);
      expect(await state.isVisible(ocmd), isTrue);
    });

    test('a single dictionary is accepted where /OCGs expects an array',
        () async {
      final ocmd = PdfDictionary()
        ..put(PdfOcName.type, PdfOcName.ocmd)
        ..put(PdfOcName.ocgs, b);
      expect(await state.isVisible(ocmd), isFalse);
    });

    test('/VE evaluates And, Or and Not', () async {
      Future<bool> evaluate(PdfArray expression) async {
        final ocmd = PdfDictionary()
          ..put(PdfOcName.type, PdfOcName.ocmd)
          ..put(PdfOcName.ve, expression);
        return state.isVisible(ocmd);
      }

      expect(await evaluate(_array(<PdfObject>[PdfOcName.and, a, b])), isFalse);
      expect(await evaluate(_array(<PdfObject>[PdfOcName.or, a, b])), isTrue);
      expect(await evaluate(_array(<PdfObject>[PdfOcName.not, b])), isTrue);
      expect(await evaluate(_array(<PdfObject>[PdfOcName.not, a])), isFalse);
    });

    test('/VE nests, as in EXAMPLE 3 of clause 8.11.2.2', () async {
      final c = _group('C');
      state.setGroupOn(c, true);
      // "A" OR (NOT "B") OR ("A" AND "C")
      final expression = _array(<PdfObject>[
        PdfOcName.or,
        b,
        _array(<PdfObject>[PdfOcName.not, b]),
        _array(<PdfObject>[PdfOcName.and, a, c]),
      ]);
      final ocmd = PdfDictionary()
        ..put(PdfOcName.type, PdfOcName.ocmd)
        ..put(PdfOcName.ve, expression);
      expect(await state.isVisible(ocmd), isTrue);
    });

    test('/VE wins over /P when both are present', () async {
      final ocmd = PdfDictionary()
        ..put(PdfOcName.type, PdfOcName.ocmd)
        ..put(PdfOcName.ocgs, _array(<PdfObject>[a, b]))
        ..put(PdfOcName.p, PdfOcName.allOn)
        ..put(PdfOcName.ve, _array(<PdfObject>[PdfOcName.or, a, b]));
      expect(await state.isVisible(ocmd), isTrue);
    });

    test('a malformed /VE is ignored and /P takes over', () async {
      final ocmd = PdfDictionary()
        ..put(PdfOcName.type, PdfOcName.ocmd)
        ..put(PdfOcName.ocgs, _array(<PdfObject>[a]))
        ..put(PdfOcName.p, PdfOcName.allOff)
        // /Not accepts exactly one operand.
        ..put(PdfOcName.ve, _array(<PdfObject>[PdfOcName.not, a, a]));
      expect(await state.isVisible(ocmd), isFalse);
    });

    test('an expression can be built in memory and serialized', () {
      final expression = PdfVisibilityOperation.and(<PdfVisibilityExpression>[
        PdfVisibilityGroup(a),
        PdfVisibilityOperation.not(PdfVisibilityGroup(b)),
      ]);
      expect(expression.evaluate((group) => identical(group, a)), isTrue);
      final serialized = expression.toPdfObject() as PdfArray;
      expect(serialized.size(), 3);
      expect(serialized.toListCopy().first, PdfOcName.and);
    });
  });

  group('Configuration dictionaries (8.11.4.3)', () {
    test('BaseState ON with an OFF override', () async {
      final a = _group('A');
      final b = _group('B');
      final config = _config(<String, PdfObject>{
        'BaseState': PdfOcName.on,
        'OFF': _array(<PdfObject>[b]),
      });
      final state = await PdfOptionalContentState.fromConfiguration(
          config, <PdfDictionary>[a, b]);
      expect(state.isGroupOn(a), isTrue);
      expect(state.isGroupOn(b), isFalse);
    });

    test('BaseState OFF with an ON override', () async {
      final a = _group('A');
      final b = _group('B');
      final config = _config(<String, PdfObject>{
        'BaseState': PdfOcName.off,
        'ON': _array(<PdfObject>[a]),
      });
      final state = await PdfOptionalContentState.fromConfiguration(
          config, <PdfDictionary>[a, b]);
      expect(state.isGroupOn(a), isTrue);
      expect(state.isGroupOn(b), isFalse);
    });

    test('BaseState Unchanged keeps the previous state', () async {
      final a = _group('A');
      final previous = PdfOptionalContentState()..setGroupOn(a, false);
      final config =
          _config(<String, PdfObject>{'BaseState': PdfOcName.unchanged});
      final state = await PdfOptionalContentState.fromConfiguration(
          config, <PdfDictionary>[a],
          previous: previous);
      expect(state.isGroupOn(a), isFalse);
    });

    test('/Locked marks a group as not user toggleable', () async {
      final a = _group('A');
      final b = _group('B');
      final config =
          _config(<String, PdfObject>{'Locked': _array(<PdfObject>[a])});
      final state = await PdfOptionalContentState.fromConfiguration(
          config, <PdfDictionary>[a, b]);
      expect(state.isLocked(a), isTrue);
      expect(state.isLocked(b), isFalse);
    });

    test('/RBGroups turns siblings off when one is switched on', () async {
      final a = _group('A');
      final b = _group('B');
      final c = _group('C');
      final config = _config(<String, PdfObject>{
        'RBGroups': _array(<PdfObject>[
          _array(<PdfObject>[a, b, c])
        ]),
      });
      final state = await PdfOptionalContentState.fromConfiguration(
          config, <PdfDictionary>[a, b, c]);

      state.setGroupOn(b, true);
      expect(state.isGroupOn(a), isFalse);
      expect(state.isGroupOn(b), isTrue);
      expect(state.isGroupOn(c), isFalse);

      // Turning a group off forces nothing on (table 101).
      state.setGroupOn(b, false);
      expect(state.isGroupOn(a), isFalse);
      expect(state.isGroupOn(c), isFalse);
    });

    test('/Order reads labelled and nested entries', () async {
      final skin = _group('Skin');
      final bones = _group('Bones');
      final config = _config(<String, PdfObject>{
        'Order': _array(<PdfObject>[
          skin,
          _array(<PdfObject>[PdfString('Frog Anatomy'), bones]),
        ]),
      });
      final order = await config.getOrder();
      expect(order.length, 2);
      expect(order[0].isGroup, isTrue);
      expect(order[0].group, same(skin));
      expect(order[1].isGroup, isFalse);
      expect(order[1].label, 'Frog Anatomy');
      expect(order[1].children.single.group, same(bones));
    });

    test('/Order can be written from a tree and read back', () async {
      final a = _group('A');
      final b = _group('B');
      final config = PdfOptionalContentConfiguration();
      config.setOrderTree(<PdfOptionalContentOrder>[
        PdfOptionalContentOrder.group(a),
        PdfOptionalContentOrder.nested(
            <PdfOptionalContentOrder>[PdfOptionalContentOrder.group(b)],
            label: 'Grupo'),
      ]);
      final order = await config.getOrder();
      expect(order[0].group, same(a));
      expect(order[1].label, 'Grupo');
      expect(order[1].children.single.group, same(b));
    });

    test('/Name, /Creator and /ListMode round trip', () async {
      final config = PdfOptionalContentConfiguration();
      config.setName('Vista impressa');
      config.setCreator('dpdf');
      config.setListMode(PdfOcName.visiblePages);
      expect(await config.getName(), 'Vista impressa');
      expect(await config.getCreator(), 'dpdf');
      expect(await config.getListMode(), PdfOcName.visiblePages);

      expect(await PdfOptionalContentConfiguration().getListMode(),
          PdfOcName.allPages);
    });
  });

  group('Intent (8.11.2.3)', () {
    test('a Design group is ignored by a View configuration', () async {
      final design = PdfOptionalContentGroup('design')
        ..setIntents(<PdfName>[PdfOcName.design]);
      final group = design.pdfRepresentation();
      final config = _config(<String, PdfObject>{
        'BaseState': PdfOcName.off,
        'Intent': PdfOcName.view,
      });
      final state = await PdfOptionalContentState.fromConfiguration(
          config, <PdfDictionary>[group]);

      expect(state.isGroupOn(group), isFalse);
      // The group takes no part in visibility, so the content stays visible.
      expect(await state.isConsidered(group), isFalse);
      expect(await state.isVisible(group), isTrue);
    });

    test('an /All configuration intent matches every group', () async {
      final design = PdfOptionalContentGroup('design')
        ..setIntents(<PdfName>[PdfOcName.design]);
      final group = design.pdfRepresentation();
      final config = _config(<String, PdfObject>{
        'BaseState': PdfOcName.off,
        'Intent': PdfOcName.all,
      });
      final state = await PdfOptionalContentState.fromConfiguration(
          config, <PdfDictionary>[group]);
      expect(await state.isVisible(group), isFalse);
    });

    test('an empty configuration intent makes all content visible', () async {
      final group = _group('A');
      final config = _config(<String, PdfObject>{
        'BaseState': PdfOcName.off,
        'Intent': PdfArray(),
      });
      final state = await PdfOptionalContentState.fromConfiguration(
          config, <PdfDictionary>[group]);
      expect(await state.isVisible(group), isTrue);
    });

    test('an ignored group does not hide a membership dictionary', () async {
      final design = PdfOptionalContentGroup('design')
        ..setIntents(<PdfName>[PdfOcName.design]);
      final ignored = design.pdfRepresentation();
      final visibleGroup = _group('visible');
      final config = _config(<String, PdfObject>{'BaseState': PdfOcName.off});
      final state = await PdfOptionalContentState.fromConfiguration(
          config, <PdfDictionary>[ignored, visibleGroup]);
      state.setGroupOn(visibleGroup, true);

      final ocmd = PdfDictionary()
        ..put(PdfOcName.type, PdfOcName.ocmd)
        ..put(PdfOcName.ocgs, _array(<PdfObject>[ignored, visibleGroup]))
        ..put(PdfOcName.p, PdfOcName.allOn);
      expect(await state.isVisible(ocmd), isTrue);
    });
  });

  group('Automatic states (8.11.4.4, table 103)', () {
    PdfDictionary usageApplication(
        PdfName event, List<PdfDictionary> groups, List<PdfName> categories) {
      return PdfDictionary()
        ..put(PdfOcName.event, event)
        ..put(PdfOcName.ocgs, _array(List<PdfObject>.of(groups)))
        ..put(PdfOcName.category, _array(List<PdfObject>.of(categories)));
    }

    test('/Zoom turns a group on only inside [min, max)', () async {
      final ocg = PdfOptionalContentGroup('zoom');
      (await ocg.usageDirectory()).setZoom(min: 1.0, max: 2.0);
      final group = ocg.pdfRepresentation();
      final config = _config(<String, PdfObject>{
        'AS': _array(<PdfObject>[
          usageApplication(
              PdfOcName.view, <PdfDictionary>[group], <PdfName>[PdfOcName.zoom])
        ]),
      });

      Future<bool> at(double zoom) async {
        final state = await PdfOptionalContentState.fromConfiguration(
            config, <PdfDictionary>[group]);
        await state.applyUsageApplications(config, PdfOcName.view,
            context: PdfOptionalContentUsageContext(zoom: zoom));
        return state.isGroupOn(group);
      }

      expect(await at(0.5), isFalse);
      expect(await at(1.0), isTrue);
      expect(await at(1.5), isTrue);
      expect(await at(2.0), isFalse);
    });

    test('an absent /PrintState leaves the state unchanged', () async {
      final ocg = PdfOptionalContentGroup('print');
      (await ocg.usageDirectory()).setPrint(subtype: _n('Watermark'));
      final group = ocg.pdfRepresentation();
      final config = _config(<String, PdfObject>{
        'BaseState': PdfOcName.on,
        'AS': _array(<PdfObject>[
          usageApplication(PdfOcName.print, <PdfDictionary>[group],
              <PdfName>[PdfOcName.print])
        ]),
      });
      final state = await PdfOptionalContentState.fromConfiguration(
          config, <PdfDictionary>[group]);
      await state.applyUsageApplications(config, PdfOcName.print);
      expect(state.isGroupOn(group), isTrue);
    });

    test('only usage applications with a matching /Event are applied',
        () async {
      final ocg = PdfOptionalContentGroup('export');
      (await ocg.usageDirectory()).setExportState(false);
      final group = ocg.pdfRepresentation();
      final config = _config(<String, PdfObject>{
        'AS': _array(<PdfObject>[
          usageApplication(PdfOcName.export, <PdfDictionary>[group],
              <PdfName>[PdfOcName.export])
        ]),
      });

      final viewing = await PdfOptionalContentState.fromConfiguration(
          config, <PdfDictionary>[group]);
      await viewing.applyUsageApplications(config, PdfOcName.view);
      expect(viewing.isGroupOn(group), isTrue);

      final exporting = await PdfOptionalContentState.fromConfiguration(
          config, <PdfDictionary>[group]);
      await exporting.applyUsageApplications(config, PdfOcName.export);
      expect(exporting.isGroupOn(group), isFalse);
    });

    test('/Language prefers an exact match over a partial one', () async {
      final exact = PdfOptionalContentGroup('exact');
      (await exact.usageDirectory()).setLanguage('pt-BR');
      final partial = PdfOptionalContentGroup('partial');
      (await partial.usageDirectory()).setLanguage('pt-PT', preferred: true);
      final groups = <PdfDictionary>[
        exact.pdfRepresentation(),
        partial.pdfRepresentation()
      ];
      final config = _config(<String, PdfObject>{
        'AS': _array(<PdfObject>[
          usageApplication(
              PdfOcName.view, groups, <PdfName>[PdfOcName.language])
        ]),
      });

      final brazilian = await PdfOptionalContentState.fromConfiguration(
          config, groups);
      await brazilian.applyUsageApplications(config, PdfOcName.view,
          context: const PdfOptionalContentUsageContext(language: 'pt-BR'));
      expect(brazilian.isGroupOn(groups[0]), isTrue);
      expect(brazilian.isGroupOn(groups[1]), isFalse);

      // No exact match: only the group whose /Preferred is ON wins.
      final angolan =
          await PdfOptionalContentState.fromConfiguration(config, groups);
      await angolan.applyUsageApplications(config, PdfOcName.view,
          context: const PdfOptionalContentUsageContext(language: 'pt-AO'));
      expect(angolan.isGroupOn(groups[0]), isFalse);
      expect(angolan.isGroupOn(groups[1]), isTrue);
    });

    test('/User matches the identity of the reader', () async {
      final ocg = PdfOptionalContentGroup('user');
      (await ocg.usageDirectory()).setUser(_n('Ind'), <String>['Isaque']);
      final group = ocg.pdfRepresentation();
      final config = _config(<String, PdfObject>{
        'AS': _array(<PdfObject>[
          usageApplication(
              PdfOcName.view, <PdfDictionary>[group], <PdfName>[PdfOcName.user])
        ]),
      });

      Future<bool> forUser(Set<String> names) async {
        final state = await PdfOptionalContentState.fromConfiguration(
            config, <PdfDictionary>[group]);
        await state.applyUsageApplications(config, PdfOcName.view,
            context: PdfOptionalContentUsageContext(userNames: names));
        return state.isGroupOn(group);
      }

      expect(await forUser(<String>{'Isaque'}), isTrue);
      expect(await forUser(<String>{'Outro'}), isFalse);
    });

    test('every category must agree before a group is turned on', () async {
      final ocg = PdfOptionalContentGroup('both');
      final usage = await ocg.usageDirectory();
      usage.setViewState(true);
      usage.setZoom(min: 4.0);
      final group = ocg.pdfRepresentation();
      final config = _config(<String, PdfObject>{
        'AS': _array(<PdfObject>[
          usageApplication(PdfOcName.view, <PdfDictionary>[group],
              <PdfName>[PdfOcName.view, PdfOcName.zoom])
        ]),
      });
      final state = await PdfOptionalContentState.fromConfiguration(
          config, <PdfDictionary>[group]);
      await state.applyUsageApplications(config, PdfOcName.view,
          context: const PdfOptionalContentUsageContext(zoom: 1.0));
      expect(state.isGroupOn(group), isFalse);
    });
  });

  group('Making content optional (8.11.3)', () {
    test('a /OC entry decides whether an XObject is drawn', () async {
      final group = _group('A');
      final state = PdfOptionalContentState()..setGroupOn(group, false);

      final xObject = PdfDictionary()..put(PdfOcName.oc, group);
      expect(await state.isOwnerVisible(xObject), isFalse);
      // An object without /OC is never optional.
      expect(await state.isOwnerVisible(PdfDictionary()), isTrue);

      state.setGroupOn(group, true);
      expect(await state.isOwnerVisible(xObject), isTrue);
    });

    test('a /OC name is resolved through the /Properties resources', () async {
      final group = _group('A');
      final state = PdfOptionalContentState()..setGroupOn(group, false);
      final resources = PdfDictionary()
        ..put(PdfOcName.properties,
            PdfDictionary()..put(_n('oc1'), group));

      expect(await state.isMarkedContentVisible(resources, _n('oc1')), isFalse);
      // An unknown name is not optional content, so the section is drawn.
      expect(await state.isMarkedContentVisible(resources, _n('oc9')), isTrue);
      expect(await state.isMarkedContentVisible(null, _n('oc1')), isTrue);
    });

    test('a /OC tag over a non-optional dictionary is ordinary marked content',
        () async {
      final state = PdfOptionalContentState();
      final language = PdfDictionary()..put(_n('Lang'), PdfString('pt-BR'));
      expect(await state.isVisible(language), isTrue);
    });

    test('the canvas writes /OC BDC and the DP reference point', () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final page = await document.appendBlankPage();
      final ocg = PdfOptionalContentGroup('Camada');
      ocg.pdfRepresentation().attachToDocument(document);

      final canvas = await PdfCanvas.fromPage(page);
      await canvas.beginOptionalContent(ocg.pdfRepresentation());
      canvas.saveState().restoreState();
      canvas.endOptionalContent();
      await canvas.markOptionalContentPoint(ocg.pdfRepresentation());

      final content =
          String.fromCharCodes((await canvas.contentStream!.getBytes())!);
      expect(content, contains(' BDC\n'));
      expect(content, contains('/OC /'));
      expect(content, contains(' DP\n'));
      expect(content, contains('EMC'));
      await document.close();
    });
  });

  group('Properties dictionary (8.11.4.2) and round trip', () {
    test('groups, configurations and visibility survive a save and reload',
        () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      await document.appendBlankPage();

      final visible = PdfOptionalContentGroup('Visivel');
      final hidden = PdfOptionalContentGroup('Oculta');
      visible.pdfRepresentation().attachToDocument(document);
      hidden.pdfRepresentation().attachToDocument(document);

      final properties =
          await PdfOptionalContentProperties.forDocument(document);
      await properties.addGroup(visible);
      await properties.addGroup(hidden);
      // Adding the same group twice must not duplicate the /OCGs entry.
      await properties.addGroup(hidden);

      final config = await properties.getDefaultConfiguration();
      config.setBaseState(PdfOcName.on);
      config.setOffGroups(<PdfOptionalContentGroup>[hidden]);
      config.setOrder(<PdfOptionalContentGroup>[visible, hidden]);
      config.setLockedGroups(<PdfOptionalContentGroup>[hidden]);

      final alternate = PdfOptionalContentConfiguration();
      alternate.setName('Tudo oculto');
      alternate.setBaseState(PdfOcName.off);
      properties.addAlternateConfiguration(alternate);

      await document.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(bytes.toBytes()));
      addTearDown(reopened.close);

      final reloaded =
          (await PdfOptionalContentProperties.fromDocument(reopened))!;
      final groups = await reloaded.getGroups();
      expect(groups.length, 2);

      final names = <String?>[];
      for (final group in groups) {
        names.add(
            await PdfOptionalContentGroup.fromDictionary(group).getName());
      }
      expect(names, <String>['Visivel', 'Oculta']);

      final state = await reloaded.resolveState();
      expect(await state.isVisible(groups[0]), isTrue);
      expect(await state.isVisible(groups[1]), isFalse);
      expect(state.isLocked(groups[1]), isTrue);

      final order = await (await reloaded.getDefaultConfiguration()).getOrder();
      expect(order.length, 2);
      expect(order.every((entry) => entry.isGroup), isTrue);

      final alternates = await reloaded.getAlternateConfigurations();
      expect(alternates.length, 1);
      expect(await alternates.single.getName(), 'Tudo oculto');
      final alternateState =
          await reloaded.resolveState(configuration: alternates.single);
      expect(await alternateState.isVisible(groups[0]), isFalse);
    });

    test('a document without /OCProperties reports none', () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      await document.appendBlankPage();
      expect(await PdfOptionalContentProperties.fromDocument(document), isNull);
      await document.close();
    });

    test('isOptionalContent recognizes groups and membership dictionaries',
        () async {
      expect(await PdfOptionalContentProperties.isOptionalContent(_group('A')),
          isTrue);
      final ocmd = PdfDictionary()..put(PdfOcName.type, PdfOcName.ocmd);
      expect(
          await PdfOptionalContentProperties.isOptionalContent(ocmd), isTrue);
      expect(await PdfOptionalContentProperties.isOptionalContent(PdfNumber(1)),
          isFalse);
    });

    test('state keys survive two references to the same object', () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final group = _group('A');
      group.attachToDocument(document);
      final reference = group.indirectHandle()!;

      final state = PdfOptionalContentState()..setGroupOn(group, false);
      final resolved =
          await PdfOptionalContentGroup.resolveDictionary(reference);
      expect(state.isGroupOn(resolved!), isFalse);
      await document.close();
    });
  });
}
