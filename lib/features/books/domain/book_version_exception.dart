import '../../../core/errors/app_exception.dart';

/// The server no longer matches the metadata used for this request.
final class BookVersionChangedException extends AppException {
  const BookVersionChangedException(super.message);
}
