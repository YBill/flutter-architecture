import 'helpers/mock_book_api.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/features/books/data/book_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real book has 203 chapter metadata entries; body is only read on demand',
    () async {
      final requests = <String>[];
      final api = MockBookApi(delay: Duration.zero, onRequest: requests.add);
      final books = await api.fetchBooks();
      expect(books.single.title, 'Claimed By The Ruthless Alpha');
      expect(books.single.author, 'Ofotokun Bridget');
      final detail = await api.fetchDetail(sampleBookId);
      final catalog = await api.fetchCatalog(sampleBookId);
      expect(catalog.chapters, hasLength(203));
      expect(catalog.version, detail.catalogVersion);
      expect(requests.where((p) => RegExp(r'/chapters/').hasMatch(p)), isEmpty);
      final first = await api.fetchChapter(
        sampleBookId,
        catalog.chapters.first,
      );
      expect(first.title, 'CHAPTER ONE');
      expect(first.body.startsWith('You could hear'), isTrue);
      expect(first.body, isNot(contains('CHAPTER ONE')));
      final last = await api.fetchChapter(sampleBookId, catalog.chapters.last);
      expect(last.body.startsWith('After the intense battle'), isTrue);
      expect(
        requests.where((p) => RegExp(r'/chapters/').hasMatch(p)),
        hasLength(2),
      );
    },
  );
}
