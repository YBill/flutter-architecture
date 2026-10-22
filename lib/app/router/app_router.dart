import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../l10n/app_localizations.dart';
import '../../features/books/data/book_api.dart';
import '../../features/books/presentation/book_detail_page.dart';
import '../../features/reader/presentation/reader_page.dart';

part 'app_router.g.dart';

@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', redirect: (context, state) => '/books/$sampleBookId'),
      GoRoute(
        path: '/books/:bookId',
        name: 'book-detail',
        builder: (context, state) => BookDetailPage(
          key: ValueKey('detail-${state.pathParameters['bookId']}'),
          bookId: state.pathParameters['bookId']!,
        ),
        routes: [
          GoRoute(
            path: 'read',
            name: 'reader',
            builder: (context, state) => ReaderPage(
              key: ValueKey('reader-${state.pathParameters['bookId']}'),
              bookId: state.pathParameters['bookId']!,
              initialChapterId: state.uri.queryParameters['chapter'],
            ),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: Text(AppLocalizations.of(context).pageNotFound)),
    ),
  );
  ref.onDispose(router.dispose);
  return router;
}
