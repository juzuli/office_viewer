/// Typed failures. Documents are untrusted input, so callers get a reason
/// they can act on instead of a string.
sealed class OfficeError implements Exception {
  const OfficeError(this.message);
  final String message;
  @override
  String toString() => '$runtimeType: $message';
}

class UnsupportedFormatError extends OfficeError {
  const UnsupportedFormatError(super.message);
}

class PasswordRequiredError extends OfficeError {
  const PasswordRequiredError() : super('Document is password protected.');
}

class CorruptDocumentError extends OfficeError {
  const CorruptDocumentError(super.message);
}

class ResourceLimitError extends OfficeError {
  const ResourceLimitError(super.message);
}

class EngineUnavailableError extends OfficeError {
  const EngineUnavailableError(super.message);
}
