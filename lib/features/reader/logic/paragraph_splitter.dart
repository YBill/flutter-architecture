import 'package:characters/characters.dart';

/// 章节正文的段落拆分结果：texts 与 starts 一一对应，
/// starts[i] 是第 i 段首字符在章内 body 中的偏移（滚动模式据此回写/恢复位置）。
class ChapterParagraphs {
  const ChapterParagraphs(this.texts, this.starts, this.endsParagraph);

  final List<String> texts;
  final List<int> starts;
  final List<bool> endsParagraph;

  bool get isEmpty => texts.isEmpty;

  /// 包含 [charOffset] 的段落；offset 落在段落间空行时返回其后第一个段落
  /// （分页页首可能正好落在空行上，恢复时应显示下一页的首段）。空正文返回 -1。
  int indexForOffset(int charOffset) {
    if (starts.isEmpty) return -1;
    var lo = 0;
    var hi = starts.length - 1;
    var result = starts.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final end = starts[mid] + texts[mid].length;
      if (end > charOffset) {
        result = mid;
        hi = mid - 1;
      } else {
        lo = mid + 1;
      }
    }
    return result;
  }
}

/// 段落 = 连续非空行（空行分段），段内的软换行保留。
final _paragraphPattern = RegExp(r'[^\n]+(?:\n(?!\n)[^\n]+)*');

ChapterParagraphs splitParagraphs(String body) {
  final texts = <String>[];
  final starts = <int>[];
  final endsParagraph = <bool>[];
  for (final m in _paragraphPattern.allMatches(body)) {
    // 单换行正文也可能长达整章。限制每个 Text 的长度，同时把原始
    // offset 留下来；续块之间不额外加段距。按字素拆分，不切开 emoji。
    final text = m[0]!;
    var start = 0;
    while (start < text.length) {
      final range = CharacterRange.at(text, start)..expandNext(200);
      var end = text.length - range.stringAfterLength;
      if (end < text.length) {
        final newline = text.lastIndexOf('\n', end - 1);
        if (newline >= start) end = newline + 1;
        // 英文单词不能因 Text 分块被拆成两半。优先退到最近的词间空白，
        // 极长且没有空白的单词仍按字素退化，保证有进展。
        if (end > start &&
            end < text.length &&
            RegExp(r'[A-Za-z]').hasMatch(text[end - 1]) &&
            RegExp(r'[A-Za-z]').hasMatch(text[end])) {
          final whitespace = text
              .substring(start, end)
              .lastIndexOf(RegExp(r'\s'));
          if (whitespace > 0) end = start + whitespace + 1;
        }
      }
      texts.add(text.substring(start, end));
      starts.add(m.start + start);
      endsParagraph.add(end == text.length);
      start = end;
    }
  }
  return ChapterParagraphs(texts, starts, endsParagraph);
}
