import '../pdf_array.dart';
import '../pdf_date.dart';
import '../pdf_dictionary.dart';
import '../pdf_name.dart';
import '../pdf_number.dart';
import '../pdf_object.dart';
import '../pdf_object_wrapper.dart';
import '../pdf_string.dart';

/// A URL alias dictionary.
///
/// ISO 32000-1:2008, 14.10.5.2, Table 356. It records a set of URL chains that
/// all lead, through HTTP redirection, to the one destination named by `/U`.
class PdfUrlAliasDictionary extends PdfObjectWrapper<PdfDictionary> {
  /// `/U`, the destination URL.
  static final PdfName destination = PdfName.intern('U');

  /// `/C`, the chains of URLs leading to `/U`.
  static final PdfName chains = PdfName.intern('C');

  PdfUrlAliasDictionary(super.pdfObject);

  /// Creates a URL alias dictionary for [url].
  PdfUrlAliasDictionary.create(String url) : super(PdfDictionary()) {
    setDestination(url);
  }

  /// 14.10.5.1: "the entire URL alias dictionary (excluding the URL strings)
  /// should be represented as a direct object because its internal structure
  /// should never be shared or externally referenced."
  @override
  bool requiresIndirectStorage() => false;

  /// Sets `/U`.
  PdfUrlAliasDictionary setDestination(String url) {
    if (url.isEmpty) {
      throw ArgumentError.value(
          url, 'url', 'A URL alias dictionary /U is required (Table 356)');
    }
    pdfRepresentation().put(destination, PdfString(url));
    markChanged();
    return this;
  }

  /// Gets `/U`.
  Future<String?> getDestination() async =>
      (await pdfRepresentation().stringEntry(destination))?.getValue();

  /// Adds one chain of URLs leading to `/U`.
  ///
  /// "Within each chain, the URLs shall be stored as ASCII strings in the order
  /// in which they occur in the redirection sequence. The common destination
  /// (the last URL in a chain) may be omitted, since it is already identified
  /// by the U entry."
  PdfUrlAliasDictionary addChain(List<String> chain) {
    if (chain.isEmpty) {
      throw ArgumentError.value(chain, 'chain',
          'A URL alias chain shall hold at least one URL (Table 356)');
    }
    var array = _chainArray();
    if (array == null) {
      array = PdfArray();
      pdfRepresentation().put(chains, array);
    }
    array.add(PdfArray.fromList([for (final url in chain) PdfString(url)]));
    markChanged();
    return this;
  }

  /// Gets `/C` as a list of chains.
  Future<List<List<String>>> getChains() async {
    final array = _chainArray();
    if (array == null) return const [];
    final result = <List<String>>[];
    for (var i = 0; i < array.size(); i++) {
      final chain = await array.arrayEntry(i);
      if (chain == null) continue;
      final urls = <String>[];
      for (var j = 0; j < chain.size(); j++) {
        final url = await chain.stringEntry(j);
        if (url != null) urls.add(url.getValue());
      }
      result.add(urls);
    }
    return result;
  }

  PdfArray? _chainArray() {
    final value = pdfRepresentation().getMap()?[chains];
    return value is PdfArray ? value : null;
  }

  /// Reports every way in which this dictionary departs from Table 356.
  Future<List<String>> validate() async {
    final problems = <String>[];
    if (await getDestination() == null) {
      problems.add('/U is required in a URL alias dictionary (Table 356)');
    }
    if (pdfRepresentation().containsKey(chains)) {
      final array = await pdfRepresentation().arrayEntry(chains);
      if (array == null) {
        problems.add('/C shall be an array of arrays of strings (Table 356)');
      } else {
        for (var i = 0; i < array.size(); i++) {
          final chain = await array.arrayEntry(i);
          if (chain == null) {
            problems.add('/C entry $i shall be an array of URL strings '
                '(Table 356)');
            continue;
          }
          for (var j = 0; j < chain.size(); j++) {
            if (await chain.stringEntry(j) == null) {
              problems.add('/C entry $i element $j shall be an ASCII string '
                  '(Table 356)');
            }
          }
        }
      }
    }
    return problems;
  }
}

/// How the source data of a page set was reached, the `/S` code of Table 355.
enum PdfWebCaptureSubmitMethod {
  /// 0, not accessed by means of a form submission. The default.
  notSubmitted,

  /// 1, accessed by means of an HTTP GET request.
  httpGet,

  /// 2, accessed by means of an HTTP POST request.
  httpPost,
}

/// A source information dictionary.
///
/// ISO 32000-1:2008, 14.10.5.1, Table 355. It is the `/SI` entry of a content
/// set and records where the source data came from.
class PdfWebCaptureSourceInformation extends PdfObjectWrapper<PdfDictionary> {
  /// `/AU`, the URLs the source data was retrieved from.
  static final PdfName aliasedUrls = PdfName.intern('AU');

  /// `/TS`, the time stamp.
  static final PdfName timeStamp = PdfName.intern('TS');

  /// `/E`, the expiration stamp.
  static final PdfName expiration = PdfName.intern('E');

  /// `/S`, the form submission code.
  static final PdfName submitMethod = PdfName.intern('S');

  /// `/C`, the command that retrieved the source data.
  static final PdfName command = PdfName.intern('C');

  PdfWebCaptureSourceInformation(super.pdfObject);

  /// Creates a source information dictionary for a single URL.
  PdfWebCaptureSourceInformation.forUrl(String url) : super(PdfDictionary()) {
    setUrl(url);
  }

  /// Creates a source information dictionary for a set of aliased URLs.
  PdfWebCaptureSourceInformation.forAlias(PdfUrlAliasDictionary alias)
      : super(PdfDictionary()) {
    setUrlAlias(alias);
  }

  @override
  bool requiresIndirectStorage() => false;

  /// Sets `/AU` to a single URL string.
  PdfWebCaptureSourceInformation setUrl(String url) {
    if (url.isEmpty) {
      throw ArgumentError.value(url, 'url',
          'A source information dictionary /AU is required (Table 355)');
    }
    pdfRepresentation().put(aliasedUrls, PdfString(url));
    markChanged();
    return this;
  }

  /// Sets `/AU` to a URL alias dictionary, the form used when several URLs
  /// redirect to the same location.
  PdfWebCaptureSourceInformation setUrlAlias(PdfUrlAliasDictionary alias) {
    pdfRepresentation().put(aliasedUrls, alias.pdfRepresentation());
    markChanged();
    return this;
  }

  /// Gets `/AU` when it is a plain string.
  Future<String?> getUrl() async {
    final value = await pdfRepresentation().get(aliasedUrls, true);
    return value is PdfString ? value.getValue() : null;
  }

  /// Gets `/AU` when it is a URL alias dictionary.
  Future<PdfUrlAliasDictionary?> getUrlAlias() async {
    final value = await pdfRepresentation().get(aliasedUrls, true);
    return value is PdfDictionary ? PdfUrlAliasDictionary(value) : null;
  }

  /// Every URL this dictionary names: the plain `/AU` string, or the
  /// destination and every chain member of the alias dictionary.
  Future<List<String>> allUrls() async {
    final single = await getUrl();
    if (single != null) return [single];
    final alias = await getUrlAlias();
    if (alias == null) return const [];
    final urls = <String>[];
    final target = await alias.getDestination();
    if (target != null) urls.add(target);
    for (final chain in await alias.getChains()) {
      for (final url in chain) {
        if (!urls.contains(url)) urls.add(url);
      }
    }
    return urls;
  }

  /// Sets `/TS`, the most recent moment at which the content was known to be
  /// up to date with the source.
  PdfWebCaptureSourceInformation setTimeStamp(DateTime moment) {
    pdfRepresentation().put(timeStamp, PdfString(PdfDate(moment).getValue()));
    markChanged();
    return this;
  }

  /// Gets `/TS`.
  Future<DateTime?> getTimeStamp() async => _date(timeStamp);

  /// Sets `/E`, the moment after which the content is out of date.
  PdfWebCaptureSourceInformation setExpiration(DateTime moment) {
    pdfRepresentation().put(expiration, PdfString(PdfDate(moment).getValue()));
    markChanged();
    return this;
  }

  /// Gets `/E`.
  Future<DateTime?> getExpiration() async => _date(expiration);

  /// Whether the content is out of date at [now], by the `/E` stamp.
  Future<bool> hasExpiredAt(DateTime now) async {
    final limit = await getExpiration();
    return limit != null && now.isAfter(limit);
  }

  /// Sets `/S`. "This entry may be present only in source information
  /// dictionaries associated with page sets."
  PdfWebCaptureSourceInformation setSubmitMethod(
      PdfWebCaptureSubmitMethod method) {
    pdfRepresentation().put(submitMethod, PdfNumber.fromInt(method.index));
    markChanged();
    return this;
  }

  /// Gets `/S`; the default is [PdfWebCaptureSubmitMethod.notSubmitted].
  Future<PdfWebCaptureSubmitMethod> getSubmitMethod() async {
    final value =
        (await pdfRepresentation().numberEntry(submitMethod))?.intValue();
    if (value == null || value < 0 || value > 2) {
      return PdfWebCaptureSubmitMethod.notSubmitted;
    }
    return PdfWebCaptureSubmitMethod.values[value];
  }

  /// Sets `/C`, the command that caused the source data to be retrieved.
  ///
  /// Table 355 marks it "if present, shall be an indirect reference", so the
  /// command dictionary has to be attached to a document already.
  PdfWebCaptureSourceInformation setCommand(PdfDictionary commandDictionary) {
    final reference = commandDictionary.indirectHandle();
    if (reference == null) {
      throw ArgumentError.value(commandDictionary, 'commandDictionary',
          'A source information /C shall be an indirect reference (Table 355)');
    }
    pdfRepresentation().put(command, reference);
    markChanged();
    return this;
  }

  /// Gets `/C`.
  Future<PdfDictionary?> getCommand() async =>
      await pdfRepresentation().dictionaryEntry(command);

  /// Reports every way in which this dictionary departs from Table 355.
  ///
  /// Set [forPageSet] to false to also report the two entries that "may be
  /// present only in source information dictionaries associated with page
  /// sets".
  Future<List<String>> validate({bool forPageSet = true}) async {
    final problems = <String>[];
    final dictionary = pdfRepresentation();

    final au = await dictionary.get(aliasedUrls, true);
    if (au == null) {
      problems.add('/AU is required in a source information dictionary '
          '(Table 355)');
    } else if (au is PdfString) {
      // An ASCII string is one of the two permitted forms.
    } else if (au is PdfDictionary) {
      problems.addAll(await PdfUrlAliasDictionary(au).validate());
    } else {
      problems.add('/AU shall be an ASCII string or a URL alias dictionary '
          '(Table 355)');
    }

    for (final key in [timeStamp, expiration]) {
      if (dictionary.containsKey(key) &&
          await dictionary.stringEntry(key) == null) {
        problems.add('/${key.getValue()} shall be a date (Table 355)');
      }
    }

    if (dictionary.containsKey(submitMethod)) {
      final value = (await dictionary.numberEntry(submitMethod))?.intValue();
      if (value == null || value < 0 || value > 2) {
        problems.add('/S shall be 0, 1 or 2 (Table 355)');
      }
      if (!forPageSet) {
        problems.add('/S may be present only in a source information '
            'dictionary of a page set (Table 355)');
      }
    }

    if (dictionary.containsKey(command)) {
      if (dictionary.getMap()?[command] is! PdfIndirectReference) {
        problems.add('/C shall be an indirect reference (Table 355)');
      }
      if (!forPageSet) {
        problems.add('/C may be present only in a source information '
            'dictionary of a page set (Table 355)');
      }
    }

    return problems;
  }

  Future<DateTime?> _date(PdfName key) async {
    final value = await pdfRepresentation().stringEntry(key);
    if (value == null) return null;
    try {
      return PdfDate.decode(value.getValue());
    } catch (_) {
      return null;
    }
  }
}
