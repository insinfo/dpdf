import 'dart:convert';
import 'dart:typed_data';

import 'package:dpdf/src/kernel/geom/page_size.dart';
import 'package:dpdf/src/kernel/geom/rectangle.dart';
import 'package:dpdf/src/kernel/pdf/pdf_array.dart';
import 'package:dpdf/src/kernel/pdf/pdf_dictionary.dart';
import 'package:dpdf/src/kernel/pdf/pdf_document.dart';
import 'package:dpdf/src/kernel/pdf/pdf_name.dart';
import 'package:dpdf/src/kernel/pdf/pdf_number.dart';
import 'package:dpdf/src/kernel/pdf/pdf_reader.dart';
import 'package:dpdf/src/kernel/pdf/pdf_stream.dart';
import 'package:dpdf/src/kernel/pdf/pdf_string.dart';
import 'package:dpdf/src/kernel/pdf/pdf_writer.dart';
import 'package:dpdf/src/kernel/pdf/webcapture/pdf_web_capture_command.dart';
import 'package:dpdf/src/kernel/pdf/webcapture/pdf_web_capture_content_set.dart';
import 'package:dpdf/src/kernel/pdf/webcapture/pdf_web_capture_database.dart';
import 'package:dpdf/src/kernel/pdf/webcapture/pdf_web_capture_info.dart';
import 'package:dpdf/src/kernel/pdf/webcapture/pdf_web_capture_source.dart';
import 'package:dpdf/src/kernel/pdf/webcapture/web_capture_names.dart';
import 'package:dpdf/src/kernel/pdf/xobject/pdf_form_x_object.dart';
import 'package:test/test.dart';

Uint8List ascii(String value) => Uint8List.fromList(latin1.encode(value));

void main() {
  group('Web Capture information dictionary, ISO 32000-1 14.10.2', () {
    test('a captured document survives a write and reopen', () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final first = await document.appendBlankPage(PageSize.A4);
      final second = await document.appendBlankPage(PageSize.A4);

      final command = PdfWebCaptureCommand.create('http://www.example.com/')
        ..setLevels(2)
        ..setFlags(
            PdfWebCaptureCommand.sameSite | PdfWebCaptureCommand.samePath)
        ..setHeaders(['Referer: http://frumble.com', 'From: veeble@frotz.com']);
      command.pdfRepresentation().attachToDocument(document);

      final source =
          PdfWebCaptureSourceInformation.forUrl('http://www.example.com/')
            ..setTimeStamp(DateTime.utc(2024, 3, 1))
            ..setExpiration(DateTime.utc(2024, 4, 1))
            ..setSubmitMethod(PdfWebCaptureSubmitMethod.httpGet)
            ..setCommand(command.pdfRepresentation());

      final digest =
          WebCaptureNames.pageSetIdentifier(ascii('<html>hi</html>'));
      final pageSet = PdfWebCapturePageSet.create(digest)
        ..setTitle('Example home page')
        ..setTextIdentifier(WebCaptureNames.textIdentifier(ascii('hi')))
        ..setContentType('text/html')
        ..setTimeStamp(DateTime.utc(2024, 3, 1))
        ..setSource(source)
        ..setObjects([first.pdfRepresentation(), second.pdfRepresentation()]);
      pageSet.pdfRepresentation().attachToDocument(document);
      expect(await pageSet.validate(), isEmpty);

      await PdfWebCaptureDatabase.markAsMember(
          first.pdfRepresentation(), pageSet);
      await PdfWebCaptureDatabase.markAsMember(
          second.pdfRepresentation(), pageSet);

      final database = PdfWebCaptureDatabase(document.rootCatalog());
      await database.registerByIdentifier(pageSet);
      await database.registerByUrl('HTTP://WWW.Example.COM:80/', pageSet);

      final info = PdfWebCaptureInfo.create()..addCommand(command);
      info.attachToCatalog(document.rootCatalog());
      expect(await info.validate(), isEmpty);
      await document.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(bytes.toBytes()));
      addTearDown(reopened.close);

      final loadedInfo =
          await PdfWebCaptureInfo.ofCatalog(reopened.rootCatalog());
      expect(loadedInfo, isNotNull);
      expect(await loadedInfo!.getVersion(), 1.0);
      expect(await loadedInfo.validate(), isEmpty);

      final commands = await loadedInfo.getCommands();
      expect(commands.length, 1);
      expect(await commands.single.getUrl(), 'http://www.example.com/');
      expect(await commands.single.getLevels(), 2);
      expect(
          await commands.single.hasFlag(PdfWebCaptureCommand.sameSite), isTrue);
      expect(
          await commands.single.hasFlag(PdfWebCaptureCommand.submit), isFalse);
      expect(await commands.single.getHeaders(),
          ['Referer: http://frumble.com', 'From: veeble@frotz.com']);

      final loadedDatabase = PdfWebCaptureDatabase(reopened.rootCatalog());
      final byId = await loadedDatabase.contentSetsForIdentifier(digest);
      expect(byId.length, 1);
      expect(byId.single, isA<PdfWebCapturePageSet>());
      final loadedSet = byId.single as PdfWebCapturePageSet;
      expect(await loadedSet.getTitle(), 'Example home page');
      expect(await loadedSet.getContentType(), 'text/html');
      expect(await loadedSet.getTimeStamp(), DateTime.utc(2024, 3, 1));
      expect((await loadedSet.getObjectArray())!.size(), 2);
      expect(await loadedSet.validate(), isEmpty);

      final loadedSource = (await loadedSet.getSources()).single;
      expect(await loadedSource.getUrl(), 'http://www.example.com/');
      expect(await loadedSource.getSubmitMethod(),
          PdfWebCaptureSubmitMethod.httpGet);
      expect(await loadedSource.getExpiration(), DateTime.utc(2024, 4, 1));
      expect(await loadedSource.hasExpiredAt(DateTime.utc(2024, 5, 1)), isTrue);
      expect(
          await loadedSource.hasExpiredAt(DateTime.utc(2024, 3, 5)), isFalse);
      expect(await loadedSource.getCommand(), isNotNull);

      // The URL key was canonicalised before it went into /URLS.
      expect(await loadedDatabase.contentSetsForUrl('http://www.example.com/'),
          hasLength(1));
      expect(
          (await loadedDatabase.keysOf(PdfWebCaptureDatabase.urlsTree))
              .map((k) => k.getValue()),
          ['http://www.example.com/']);

      final parent = await loadedDatabase
          .parentContentSet((await reopened.pageAt(1))!.pdfRepresentation());
      expect(parent, isNotNull);
      expect(await parent!.getIdentifier(), digest);
    });

    test('a /URLS entry can hold several content sets', () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final page = await document.appendBlankPage(PageSize.A4);
      final image = PdfFormXObject(Rectangle(0, 0, 10, 10));
      image.pdfRepresentation().attachToDocument(document);

      final pageSet = PdfWebCapturePageSet.create(ascii('page-digest'))
        ..setSource(PdfWebCaptureSourceInformation.forUrl('http://a/'))
        ..setObjects([page.pdfRepresentation()]);
      pageSet.pdfRepresentation().attachToDocument(document);
      final imageSet = PdfWebCaptureImageSet.create(ascii('image-digest'))
        ..setSource(PdfWebCaptureSourceInformation.forUrl('http://a/'))
        ..setObjects([image.pdfRepresentation()])
        ..setReferenceCounts([1]);
      imageSet.pdfRepresentation().attachToDocument(document);

      final database = PdfWebCaptureDatabase(document.rootCatalog());
      await database.registerByUrl('http://a/', pageSet);
      await database.registerByUrl('http://a/', imageSet);
      await document.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(bytes.toBytes()));
      addTearDown(reopened.close);
      final loaded = await PdfWebCaptureDatabase(reopened.rootCatalog())
          .contentSetsForUrl('http://a/');
      expect(loaded.length, 2);
      expect(loaded.whereType<PdfWebCapturePageSet>(), hasLength(1));
      expect(loaded.whereType<PdfWebCaptureImageSet>(), hasLength(1));
    });

    test('an unknown key yields no content set', () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      await document.appendBlankPage(PageSize.A4);
      final database = PdfWebCaptureDatabase(document.rootCatalog());
      expect(await database.contentSetsForUrl('http://absent/'), isEmpty);
      expect(await database.contentSetsForIdentifier(ascii('nope')), isEmpty);
      await document.close();
    });

    test('validate reports a version other than 1.0 and a bad /C entry',
        () async {
      final info = PdfWebCaptureInfo.create()..setVersion(1.2);
      var problems = await info.validate();
      expect(problems, contains(contains('/V shall be 1.0')));

      info.setVersion(PdfWebCaptureInfo.conformingVersion);
      info.pdfRepresentation().put(
          PdfWebCaptureInfo.commands, PdfArray.fromList([PdfDictionary()]));
      problems = await info.validate();
      expect(problems, contains(contains('/C entry 0')));
    });

    test('a command that is not indirect cannot enter /C', () {
      final info = PdfWebCaptureInfo.create();
      expect(() => info.addCommand(PdfWebCaptureCommand.create('http://a/')),
          throwsArgumentError);
    });
  });

  group('Content sets, ISO 32000-1 14.10.4', () {
    test('validate reports the missing required entries of Table 352',
        () async {
      final set = PdfWebCaptureContentSet(PdfDictionary());
      final problems = await set.validate();
      expect(problems, contains(contains('/S is required')));
      expect(problems, contains(contains('/ID is required')));
      expect(problems, contains(contains('/O is required')));
      expect(problems, contains(contains('/SI is required')));
    });

    test('an unknown subtype is reported and cannot be wrapped', () async {
      final dictionary = PdfDictionary();
      dictionary.put(PdfWebCaptureContentSet.subtype, PdfName('SXS'));
      expect(await PdfWebCaptureContentSet.wrap(dictionary), isNull);
      expect(await PdfWebCaptureContentSet(dictionary).validate(),
          contains(contains('/S shall be /SPS or /SIS')));
    });

    test('/O refuses a direct object', () {
      final set = PdfWebCapturePageSet.create(ascii('d'));
      expect(() => set.setObjects([PdfDictionary()]), throwsArgumentError);
      expect(() => set.addObject(PdfDictionary()), throwsArgumentError);
    });

    test('an empty digital identifier is refused', () {
      expect(
          () => PdfWebCapturePageSet.create(Uint8List(0)), throwsArgumentError);
    });

    test('a page set keeps the order in which pages were added', () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final pages = [
        for (var i = 0; i < 3; i++) await document.appendBlankPage(PageSize.A4)
      ];
      final set = PdfWebCapturePageSet.create(ascii('d'));
      set.pdfRepresentation().attachToDocument(document);
      for (final page in pages) {
        set.addObject(page.pdfRepresentation());
      }
      final array = (await set.getObjectArray())!;
      for (var i = 0; i < pages.length; i++) {
        expect(
            identical(await array.get(i, true), pages[i].pdfRepresentation()),
            isTrue);
      }
      await document.close();
    });

    test('a single reference count is written as an integer', () async {
      final set = PdfWebCaptureImageSet.create(ascii('d'))
        ..setReferenceCounts([3]);
      expect(
          await set
              .pdfRepresentation()
              .numberEntry(PdfWebCaptureImageSet.referenceCounts),
          isNotNull);
      expect(await set.getReferenceCounts(), [3]);
    });

    test('several reference counts are written as a parallel array', () async {
      final set = PdfWebCaptureImageSet.create(ascii('d'))
        ..setReferenceCounts([1, 2, 3]);
      final array = await set
          .pdfRepresentation()
          .arrayEntry(PdfWebCaptureImageSet.referenceCounts);
      expect(array, isNotNull);
      expect(array!.size(), 3);
      expect(await set.getReferenceCounts(), [1, 2, 3]);
    });

    test('releasing the last reference removes the XObject and its count',
        () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final forms = [
        for (var i = 0; i < 2; i++) PdfFormXObject(Rectangle(0, 0, 10, 10))
      ];
      for (final form in forms) {
        form.pdfRepresentation().attachToDocument(document);
      }
      final set = PdfWebCaptureImageSet.create(ascii('d'))
        ..setSource(PdfWebCaptureSourceInformation.forUrl('http://a/'))
        ..setObjects([for (final f in forms) f.pdfRepresentation()])
        ..setReferenceCounts([2, 1]);
      set.pdfRepresentation().attachToDocument(document);
      expect(await set.validate(), isEmpty);

      expect(await set.releaseAt(0), 1);
      expect(await set.getReferenceCounts(), [1, 1]);
      expect((await set.getObjectArray())!.size(), 2);

      expect(await set.releaseAt(1), 0);
      expect(await set.getReferenceCounts(), [1]);
      expect((await set.getObjectArray())!.size(), 1);
      expect(await set.validate(), isEmpty);

      await set.retainAt(0);
      expect(await set.getReferenceCounts(), [2]);
      await document.close();
    });

    test('validate reports a /R that does not match /O', () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final forms = [
        for (var i = 0; i < 2; i++) PdfFormXObject(Rectangle(0, 0, 10, 10))
      ];
      for (final form in forms) {
        form.pdfRepresentation().attachToDocument(document);
      }
      final set = PdfWebCaptureImageSet.create(ascii('d'))
        ..setSource(PdfWebCaptureSourceInformation.forUrl('http://a/'))
        ..setObjects([for (final f in forms) f.pdfRepresentation()])
        ..setReferenceCounts([1]);
      set.pdfRepresentation().attachToDocument(document);

      final problems = await set.validate();
      expect(problems, contains(contains('one reference count per entry')));
      await document.close();
    });

    test('an image set without /R is reported', () async {
      final set = PdfWebCaptureImageSet.create(ascii('d'));
      expect(await set.validate(), contains(contains('/R is required')));
      expect(() => set.setReferenceCounts([]), throwsArgumentError);
      expect(() => set.setReferenceCounts([-1]), throwsArgumentError);
    });
  });

  group('Source information, ISO 32000-1 14.10.5', () {
    test('a URL alias dictionary records the chains that lead to /U', () async {
      final alias = PdfUrlAliasDictionary.create('http://final/')
        ..addChain(['http://first/', 'http://second/'])
        ..addChain(['http://other/']);
      expect(await alias.getDestination(), 'http://final/');
      expect(await alias.getChains(), [
        ['http://first/', 'http://second/'],
        ['http://other/'],
      ]);
      expect(await alias.validate(), isEmpty);

      final source = PdfWebCaptureSourceInformation.forAlias(alias);
      expect(await source.getUrl(), isNull);
      expect(await source.getUrlAlias(), isNotNull);
      expect(await source.allUrls(), [
        'http://final/',
        'http://first/',
        'http://second/',
        'http://other/',
      ]);
      expect(await source.validate(), isEmpty);
    });

    test('an empty URL or chain is refused', () {
      expect(() => PdfUrlAliasDictionary.create(''), throwsArgumentError);
      expect(() => PdfUrlAliasDictionary.create('http://a/').addChain([]),
          throwsArgumentError);
      expect(
          () => PdfWebCaptureSourceInformation.forUrl(''), throwsArgumentError);
    });

    test('validate reports a missing /AU and a bad /S', () async {
      final source = PdfWebCaptureSourceInformation(PdfDictionary());
      expect(await source.validate(), contains(contains('/AU is required')));

      source.setUrl('http://a/');
      source.pdfRepresentation().put(
          PdfWebCaptureSourceInformation.submitMethod, PdfNumber.fromInt(7));
      expect(
          await source.validate(), contains(contains('/S shall be 0, 1 or 2')));
      expect(await source.getSubmitMethod(),
          PdfWebCaptureSubmitMethod.notSubmitted);
    });

    test('/S and /C are reported on an image set source', () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      final command = PdfWebCaptureCommand.create('http://a/');
      command.pdfRepresentation().attachToDocument(document);
      final source = PdfWebCaptureSourceInformation.forUrl('http://a/')
        ..setSubmitMethod(PdfWebCaptureSubmitMethod.httpPost)
        ..setCommand(command.pdfRepresentation());

      expect(await source.validate(forPageSet: true), isEmpty);
      final problems = await source.validate(forPageSet: false);
      expect(problems, contains(contains('/S may be present only')));
      expect(problems, contains(contains('/C may be present only')));
      await document.close();
    });

    test('/C refuses a direct command dictionary', () {
      final source = PdfWebCaptureSourceInformation.forUrl('http://a/');
      expect(() => source.setCommand(PdfDictionary()), throwsArgumentError);
    });
  });

  group('Command dictionaries, ISO 32000-1 14.10.5.3', () {
    test('posted data may be a string or a stream', () async {
      final withText = PdfWebCaptureCommand.create('http://a/')
        ..setPostedText('q=dart');
      expect(withText.isPost(), isTrue);
      expect(latin1.decode((await withText.getPostedData())!), 'q=dart');
      expect(await withText.getContentType(),
          PdfWebCaptureCommand.defaultPostContentType);

      final withStream = PdfWebCaptureCommand.create('http://a/')
        ..setPostedStream(PdfStream.withBytes(ascii('q=dart'), 0))
        ..setContentType('multipart/form-data');
      expect(latin1.decode((await withStream.getPostedData())!), 'q=dart');
      expect(await withStream.getContentType(), 'multipart/form-data');
      expect(await withStream.validate(), isEmpty);
    });

    test('/CT is reported when there is no posted data', () async {
      final command = PdfWebCaptureCommand.create('http://a/')
        ..setContentType('text/plain');
      expect(command.isPost(), isFalse);
      expect(await command.validate(),
          contains(contains('/CT shall only be present for POST requests')));
    });

    test('only the flags of Table 358 may be set', () async {
      final command = PdfWebCaptureCommand.create('http://a/');
      expect(() => command.setFlags(8), throwsArgumentError);
      command
          .pdfRepresentation()
          .put(PdfWebCaptureCommand.flags, PdfNumber.fromInt(16));
      expect(await command.validate(),
          contains(contains('Only the flags of Table 358')));
    });

    test('a level below one is refused', () async {
      final command = PdfWebCaptureCommand.create('http://a/');
      expect(() => command.setLevels(0), throwsArgumentError);
      command
          .pdfRepresentation()
          .put(PdfWebCaptureCommand.levels, PdfNumber.fromInt(0));
      expect(await command.validate(),
          contains(contains('/L shall retrieve at least one level')));
      expect(await command.getLevels(), 0);
    });

    test('a missing /URL is reported', () async {
      final command = PdfWebCaptureCommand(PdfDictionary());
      expect(await command.validate(), contains(contains('/URL is required')));
      expect(await command.getLevels(), PdfWebCaptureCommand.defaultLevels);
      expect(await command.getFlags(), 0);
    });

    test('an empty /URL is refused', () {
      expect(() => PdfWebCaptureCommand.create(''), throwsArgumentError);
    });
  });

  group('Command settings, ISO 32000-1 14.10.5.4', () {
    test('an engine name reads company:product:version:contentType', () {
      expect(
          PdfWebCaptureCommandSettings.isValidEngineName('ADBE:H2PDF:1.0:HTML'),
          isTrue);
      expect(PdfWebCaptureCommandSettings.isValidEngineName('ADBE::1.0:HTML'),
          isTrue,
          reason: 'the product field may be left blank');
      expect(PdfWebCaptureCommandSettings.isValidEngineName('ADBE:H2PDF:1.0'),
          isFalse);
      expect(
          PdfWebCaptureCommandSettings.isValidEngineName(
              'ADBE:H2PDF:1.0:HTML:X'),
          isFalse);
      expect(PdfWebCaptureCommandSettings.isValidEngineName(':H2PDF:1.0:HTML'),
          isFalse);
      expect(PdfWebCaptureCommandSettings.isValidEngineName('ADBE:H2PDF::HTML'),
          isFalse);
    });

    test('settings survive a reopen inside a command', () async {
      final bytes = BytesBuilder();
      final document = PdfDocument.create(PdfWriter.fromBytesBuilder(bytes));
      await document.appendBlankPage(PageSize.A4);

      final global = PdfDictionary();
      global.put(PdfName('Margin'), PdfNumber.fromInt(36));
      final engine = PdfDictionary();
      engine.put(PdfName('Fonts'), PdfString('embedded'));
      final settings = PdfWebCaptureCommandSettings.create()
        ..setGlobalSettings(global)
        ..setEngineSettings('ADBE:H2PDF:1.0:HTML', engine);
      final command = PdfWebCaptureCommand.create('http://a/')
        ..setSettings(settings);
      command.pdfRepresentation().attachToDocument(document);
      final info = PdfWebCaptureInfo.create()..addCommand(command);
      info.attachToCatalog(document.rootCatalog());
      await document.close();

      final reopened =
          await PdfDocument.open(PdfReader.fromBytes(bytes.toBytes()));
      addTearDown(reopened.close);
      final loaded =
          (await (await PdfWebCaptureInfo.ofCatalog(reopened.rootCatalog()))!
                  .getCommands())
              .single;
      final loadedSettings = (await loaded.getSettings())!;
      expect(await loadedSettings.engineNames(), ['ADBE:H2PDF:1.0:HTML']);
      expect(
          await (await loadedSettings.getEngineSettings('ADBE:H2PDF:1.0:HTML'))!
              .stringEntry(PdfName('Fonts')),
          isNotNull);
      expect(await loadedSettings.validate(), isEmpty);
    });

    test('a malformed engine name is refused and reported', () async {
      final settings = PdfWebCaptureCommandSettings.create();
      expect(() => settings.setEngineSettings('bogus', PdfDictionary()),
          throwsArgumentError);

      final container = PdfDictionary();
      container.put(PdfName('bogus'), PdfNumber.fromInt(1));
      settings
          .pdfRepresentation()
          .put(PdfWebCaptureCommandSettings.engineSettings, container);
      final problems = await settings.validate();
      expect(problems, contains(contains('shall read company:product')));
      expect(problems, contains(contains('shall be a dictionary')));
    });
  });
}
