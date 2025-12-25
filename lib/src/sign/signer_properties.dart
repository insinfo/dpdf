import '../kernel/geom/rectangle.dart';
import 'access_permissions.dart';

/// Properties to be used in signing operations.
class SignerProperties {
  /// This string could be used to create the SignatureFieldAppearance instance
  /// which will be used for signing since its ID will be ignored anyway.
  static const String ignoredId = '';

  // TODO: PdfSigFieldLock _fieldLock;
  // TODO: SignatureFieldAppearance _appearance;

  DateTime _signDate;
  AccessPermissions _certificationLevel;
  String? _fieldName;
  int _pageNumber;
  Rectangle _pageRect;
  String _signatureCreator;
  String _contact;
  String _reason;
  String _location;

  /// Create instance of SignerProperties.
  SignerProperties()
      : _signDate = DateTime.now(),
        _certificationLevel = AccessPermissions.unspecified,
        _pageNumber = 1,
        _pageRect = Rectangle(0, 0, 0, 0),
        _signatureCreator = '',
        _contact = '',
        _reason = '',
        _location = '';

  /// Gets the signature date.
  ///
  /// @return DateTime set to the signature date
  DateTime getClaimedSignDate() => _signDate;

  /// Sets the signature date.
  ///
  /// @param signDate the signature date
  /// @return this instance to support fluent interface
  SignerProperties setClaimedSignDate(DateTime signDate) {
    _signDate = signDate;
    return this;
  }

  // TODO: setSignatureAppearance and getSignatureAppearance
  // after SignatureFieldAppearance is implemented

  /// Returns the document's certification level.
  ///
  /// For possible values see [AccessPermissions].
  ///
  /// @return AccessPermissions enum which specifies which certification level shall be used
  AccessPermissions getCertificationLevel() => _certificationLevel;

  /// Sets the document's certification level.
  ///
  /// @param accessPermissions AccessPermissions enum which specifies
  ///        which certification level shall be used
  /// @return this instance to support fluent interface
  SignerProperties setCertificationLevel(AccessPermissions accessPermissions) {
    _certificationLevel = accessPermissions;
    return this;
  }

  /// Gets the field name.
  ///
  /// @return the field name
  String? getFieldName() => _fieldName;

  /// Sets the name indicating the field to be signed.
  ///
  /// The field can already be presented in the document but shall not be signed.
  /// If the field is not presented in the document, it will be created.
  ///
  /// @param fieldName the name indicating the field to be signed
  /// @return this instance to support fluent interface
  SignerProperties setFieldName(String? fieldName) {
    if (fieldName != null) {
      _fieldName = fieldName;
    }
    return this;
  }

  /// Provides the page number of the signature field which this signature
  /// appearance is associated with.
  ///
  /// @return the page number of the signature field
  int getPageNumber() => _pageNumber;

  /// Sets the page number of the signature field which this signature
  /// appearance is associated with.
  ///
  /// @param pageNumber the page number of the signature field
  /// @return this instance to support fluent interface
  SignerProperties setPageNumber(int pageNumber) {
    _pageNumber = pageNumber;
    return this;
  }

  /// Provides the rectangle that represent the position and dimension of the
  /// signature field in the page.
  ///
  /// @return the rectangle that represent the position and dimension of the
  ///         signature field in the page
  Rectangle getPageRect() => _pageRect;

  /// Sets the rectangle that represent the position and dimension of the
  /// signature field in the page.
  ///
  /// @param pageRect the rectangle that represents the position and dimension
  ///        of the signature field in the page
  /// @return this instance to support fluent interface
  SignerProperties setPageRect(Rectangle pageRect) {
    _pageRect = pageRect;
    return this;
  }

  // TODO: getFieldLockDict and setFieldLockDict
  // after PdfSigFieldLock is implemented

  /// Returns the signature creator.
  ///
  /// @return the signature creator
  String getSignatureCreator() => _signatureCreator;

  /// Sets the name of the application used to create the signature.
  ///
  /// @param signatureCreator A new name of the application signing a document.
  /// @return this instance to support fluent interface.
  SignerProperties setSignatureCreator(String signatureCreator) {
    _signatureCreator = signatureCreator;
    return this;
  }

  /// Returns the signing contact.
  ///
  /// @return the signing contact
  String getContact() => _contact;

  /// Sets the signing contact.
  ///
  /// @param contact a new signing contact
  /// @return this instance to support fluent interface
  SignerProperties setContact(String contact) {
    _contact = contact;
    return this;
  }

  /// Returns the signing reason.
  ///
  /// @return the signing reason
  String getReason() => _reason;

  /// Sets the signing reason.
  ///
  /// @param reason a new signing reason
  /// @return this instance to support fluent interface
  SignerProperties setReason(String reason) {
    _reason = reason;
    return this;
  }

  /// Returns the signing location.
  ///
  /// @return the signing location
  String getLocation() => _location;

  /// Sets the signing location.
  ///
  /// @param location a new signing location
  /// @return this instance to support fluent interface
  SignerProperties setLocation(String location) {
    _location = location;
    return this;
  }
}
