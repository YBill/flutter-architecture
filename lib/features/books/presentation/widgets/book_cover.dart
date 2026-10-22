import 'package:flutter/material.dart';

import '../../domain/book.dart';

/// Displays the cover URL returned by the book API.
class BookCover extends StatelessWidget {
  const BookCover({required this.book, this.rating, super.key});

  final BookSummary book;
  final double? rating;

  @override
  Widget build(BuildContext context) {
    final coverUrl = book.coverUrl?.trim();
    return Semantics(
      label: book.title,
      image: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F30283C),
              blurRadius: 12,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (coverUrl != null && coverUrl.isNotEmpty)
                Image.network(
                  coverUrl,
                  fit: BoxFit.cover,
                  excludeFromSemantics: true,
                  frameBuilder: (
                    context,
                    child,
                    frame,
                    wasSynchronouslyLoaded,
                  ) => frame == null ? const _CoverPlaceholder() : child,
                  errorBuilder: (_, _, _) =>
                      const _CoverPlaceholder(failed: true),
                )
              else
                const _CoverPlaceholder(),
              if (rating case final value?)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 3,
                    ),
                    decoration: const BoxDecoration(
                      color: Color(0xDF211D35),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(8),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          color: Color(0xFFFFD56A),
                          size: 13,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          value.toStringAsFixed(1),
                          style: const TextStyle(
                            color: Color(0xFFFFD56A),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({this.failed = false});
  final bool failed;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFFF0EAF7),
    child: Center(
      child: Icon(
        failed ? Icons.broken_image_outlined : Icons.menu_book_outlined,
        color: const Color(0xFF9985B2),
        size: 28,
      ),
    ),
  );
}
