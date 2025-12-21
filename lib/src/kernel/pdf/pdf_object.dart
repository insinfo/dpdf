/*
 * This file is part of the iText (R) project.
 * Copyright (c) 1998-2025 Apryse Group NV
 * Authors: Apryse Software.
 *
 * This program is offered under a commercial and under the AGPL license.
 * For commercial licensing, contact us at https://itextpdf.com/sales.
 * For AGPL licensing, see below.
 *
 * AGPL licensing:
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

/// PDF object type constants.
class PdfObjectType {
  PdfObjectType._();

  /// Array type.
  static const int array = 1;

  /// Boolean type.
  static const int boolean = 2;

  /// Dictionary type.
  static const int dictionary = 3;

  /// Literal type.
  static const int literal = 4;

  /// Indirect reference type.
  static const int indirectReference = 5;

  /// Name type.
  static const int name = 6;

  /// Null type.
  static const int nullType = 7;

  /// Number type.
  static const int number = 8;

  /// Stream type.
  static const int stream = 9;

  /// String type.
  static const int string = 10;
}

/// Base class for all PDF objects.
///
/// All PDF primitive types (boolean, numbers, strings, names, arrays,
/// dictionaries, streams, null, and indirect references) extend this class.
abstract class PdfObject {
  /// Indicates if the object has been flushed.
  static const int flushed = 1;

  /// Indicates that the indirect reference could be reused or marked as free.
  static const int free = 1 << 1;

  /// Indicates that definition of the indirect reference is not found yet.
  static const int reading = 1 << 2;

  /// Indicates that object changed (used in append mode).
  static const int modified = 1 << 3;

  /// Indicates ObjectStream from original document.
  static const int originalObjectStream = 1 << 4;

  /// Marks objects that shall be written to the output document.
  static const int mustBeFlushed = 1 << 5;

  /// Indicates that the object shall be indirect when written.
  static const int mustBeIndirect = 1 << 6;

  /// Indicates that we don't want to release this object.
  static const int forbidRelease = 1 << 7;

  /// Indicates that we don't want to write this object.
  static const int readOnly = 1 << 8;

  /// Indicates that this object is not encrypted.
  static const int unencrypted = 1 << 9;

  /// If object is flushed the indirect reference is kept here.
  PdfIndirectReference? indirectReference;

  /// State flags for this object.
  int _state = 0;

  /// Gets object type.
  int getObjectType();

  /// Flushes the object to the document.
  void flush([bool canBeInObjStm = true]) {
    // Basic implementation - will be expanded when PdfDocument is ported
    if (isFlushed() || getIndirectReference() == null) {
      return;
    }
    // TODO: Implement full flush when PdfDocument is available
  }

  /// Gets the indirect reference associated with the object.
  PdfIndirectReference? getIndirectReference() {
    return indirectReference;
  }

  /// Checks if object is indirect.
  bool isIndirect() {
    return indirectReference != null || checkState(mustBeIndirect);
  }

  /// Indicates if the object has been flushed.
  bool isFlushed() {
    final ref = getIndirectReference();
    return ref != null && ref.checkState(flushed);
  }

  /// Indicates if the object has been modified.
  bool isModified() {
    final ref = getIndirectReference();
    return ref != null && ref.checkState(modified);
  }

  /// Creates a clone of the object.
  PdfObject clone();

  /// Sets the modified flag.
  PdfObject setModified() {
    if (indirectReference != null) {
      indirectReference!.setState(modified);
      setState(forbidRelease);
    }
    return this;
  }

  /// Checks if release is forbidden.
  bool isReleaseForbidden() {
    return checkState(forbidRelease);
  }

  /// Releases the object.
  void release() {
    if (isReleaseForbidden()) {
      return;
    }
    if (indirectReference != null && !indirectReference!.checkState(flushed)) {
      indirectReference = null;
      setState(readOnly);
    }
  }

  /// Checks if this is a PdfNull.
  bool isNull() => getObjectType() == PdfObjectType.nullType;

  /// Checks if this is a PdfBoolean.
  bool isBoolean() => getObjectType() == PdfObjectType.boolean;

  /// Checks if this is a PdfNumber.
  bool isNumber() => getObjectType() == PdfObjectType.number;

  /// Checks if this is a PdfString.
  bool isString() => getObjectType() == PdfObjectType.string;

  /// Checks if this is a PdfName.
  bool isName() => getObjectType() == PdfObjectType.name;

  /// Checks if this is a PdfArray.
  bool isArray() => getObjectType() == PdfObjectType.array;

  /// Checks if this is a PdfDictionary.
  bool isDictionary() => getObjectType() == PdfObjectType.dictionary;

  /// Checks if this is a PdfStream.
  bool isStream() => getObjectType() == PdfObjectType.stream;

  /// Checks if this is a PdfIndirectReference.
  bool isIndirectReference() =>
      getObjectType() == PdfObjectType.indirectReference;

  /// Checks if this is a PdfLiteral.
  bool isLiteral() => getObjectType() == PdfObjectType.literal;

  /// Sets the indirect reference.
  PdfObject setIndirectReference(PdfIndirectReference? ref) {
    indirectReference = ref;
    return this;
  }

  /// Creates new instance of object.
  PdfObject newInstance();

  /// Checks state of a flag.
  bool checkState(int state) {
    return (_state & state) == state;
  }

  /// Sets state flags.
  PdfObject setState(int state) {
    _state |= state;
    return this;
  }

  /// Clears state flags.
  PdfObject clearState(int state) {
    _state &= ~state;
    return this;
  }

  /// Copies content from another object.
  void copyContent(PdfObject from, [dynamic document]) {
    // Override in subclasses
  }
}

/// Represents an indirect reference to a PDF object.
///
/// An indirect reference is a pointer to an object stored elsewhere
/// in the PDF document.
class PdfIndirectReference extends PdfObject {
  /// Object number.
  final int objNr;

  /// Generation number.
  final int genNr;

  /// The object this reference points to.
  PdfObject? _refersTo;

  /// Offset in the file where the object is stored.
  int offset = 0;

  /// State flags for the reference.
  int _refState = 0;

  /// Creates a new indirect reference.
  PdfIndirectReference(this.objNr, this.genNr, [this._refersTo]);

  @override
  int getObjectType() => PdfObjectType.indirectReference;

  @override
  PdfObject clone() {
    return PdfIndirectReference(objNr, genNr, _refersTo);
  }

  @override
  PdfObject newInstance() {
    return PdfIndirectReference(objNr, genNr);
  }

  /// Gets the object this reference points to.
  PdfObject? getRefersTo([bool allowFlushed = false]) {
    if (allowFlushed || !checkState(PdfObject.flushed)) {
      return _refersTo;
    }
    return null;
  }

  /// Sets the object this reference points to.
  void setRefersTo(PdfObject? obj) {
    _refersTo = obj;
  }

  /// Checks if the reference is free.
  bool isFree() {
    return checkState(PdfObject.free);
  }

  /// Gets the object number.
  int getObjNumber() => objNr;

  /// Gets the generation number.
  int getGenNumber() => genNr;

  @override
  bool checkState(int state) {
    return (_refState & state) == state;
  }

  @override
  PdfObject setState(int state) {
    _refState |= state;
    return this;
  }

  @override
  PdfObject clearState(int state) {
    _refState &= ~state;
    return this;
  }

  @override
  String toString() {
    return '$objNr $genNr R';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PdfIndirectReference) return false;
    return objNr == other.objNr && genNr == other.genNr;
  }

  @override
  int get hashCode => Object.hash(objNr, genNr);
}
