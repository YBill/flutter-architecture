/// UTF-16 character offsets match TextPainter and the source chapter body.
/// Stable chapter IDs survive catalog insertions; ordinal index is a fallback.
class ReaderPosition {
  const ReaderPosition({
    required this.chapterIndex,
    required this.charOffset,
    this.chapterId,
    this.contentVersion,
  });

  final int chapterIndex;
  final int charOffset;
  final String? chapterId;
  final String? contentVersion;
}
