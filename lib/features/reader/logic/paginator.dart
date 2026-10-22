import 'package:characters/characters.dart';
import 'package:flutter/painting.dart';

class PageBreak {
  const PageBreak(this.start, this.end);

  /// 字符区间 [start, end)，offset 相对整章正文
  final int start;
  final int end;
}

/// 基于 TextPainter 的整章排版分页：
/// 每一页用「自己那段文本」独立 layout 来定边界（逐页子串测量），
/// 保证测量与渲染逐字节一致——整章一次测量的断行会因字体/空白处理差异
/// 与逐页渲染漂移（如段首全角空格被段落起点吞掉），导致页尾截字。
class Paginator {
  /// 整章分页。每页可用高度由 [heightForPage] 决定（如第 1 页因带章节标题而更矮）。
  /// [textScaler] 必须与渲染端 Text 的一致，否则断行会漂移。
  /// 保证每页至少一行；offset 基于完整 body。
  static List<PageBreak> paginateChapter({
    required String body,
    required TextStyle style,
    required double maxWidth,
    required double Function(int pageIndex) heightForPage,
    TextScaler textScaler = TextScaler.noScaling,
    Locale? locale,
  }) => paginateChapterPages(
    body: body,
    style: style,
    maxWidth: maxWidth,
    heightForPage: heightForPage,
    textScaler: textScaler,
    locale: locale,
  ).toList();

  /// 逐页产出，调用方可在页与页之间让出 UI 线程，避免整本重排阻塞一帧。
  static Iterable<PageBreak> paginateChapterPages({
    required String body,
    required TextStyle style,
    required double maxWidth,
    required double Function(int pageIndex) heightForPage,
    TextScaler textScaler = TextScaler.noScaling,
    Locale? locale,
  }) sync* {
    if (body.trim().isEmpty) {
      yield PageBreak(0, body.length);
      return;
    }

    var pageStart = 0;
    var pageIndex = 0;
    var windowLength = 1024;

    while (pageStart < body.length) {
      // 渲染端每页只排自己的子串，这里同样只排子串。
      // 窗口按上一页容量调整，不必为几百字的一页反复排版 4000 字。
      // 窗口全部放得下时继续扩展，防止大屏/小字号下人为生成不满的页。
      final budget = heightForPage(pageIndex);
      final tp = TextPainter(
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        locale: locale,
      );
      var windowEnd = pageStart;
      while (true) {
        final tentativeEnd = (pageStart + windowLength).clamp(0, body.length);
        // 不在代理对、组合音标或 ZWJ emoji 中间截断测量窗口。
        windowEnd =
            body.length -
            CharacterRange.at(body, tentativeEnd).stringAfterLength;
        tp.text = TextSpan(
          text: body.substring(pageStart, windowEnd),
          style: style,
        );
        tp.layout(maxWidth: maxWidth);
        if (windowEnd == body.length || tp.height > budget) break;
        windowLength *= 2;
      }

      final lines = tp.computeLineMetrics();

      var used = 0.0;
      var fitLines = 0;
      for (var i = 0; i < lines.length; i++) {
        final lineH = lines[i].height;
        if (i > 0 && used + lineH > budget) break;
        used += lineH;
        fitLines = i + 1;
      }

      PageBreak pageBreak;
      // 循环对 i=0 不做预算检查，首行必然被计入；used > budget 即「首行都放不下」。
      // 这只会发生在首页（被章节标题挤占）：本页只放标题，正文从下一页（满高）开始。
      // 不能强行分配首行再靠裁剪消化——那行文字会显示不出来却被分页消耗，静默丢失。
      if (used > budget && pageIndex == 0) {
        pageBreak = PageBreak(pageStart, pageStart);
      } else if (fitLines >= lines.length) {
        // 已到章尾，剩余内容全部放入本页。
        pageBreak = PageBreak(pageStart, windowEnd);
      } else {
        var boundary = _lineStartCharOffset(tp, lines, fitLines);
        if (boundary <= 0) {
          // 单行超过整页高度：至少放一行，避免死循环
          boundary = fitLines + 1 < lines.length
              ? _lineStartCharOffset(tp, lines, fitLines + 1)
              : windowEnd - pageStart;
        }
        pageBreak = PageBreak(pageStart, pageStart + boundary);
      }

      // 行高求和只是候选值。混合字体、双向文字以及页尾重新断行后，
      // 实际子串的高度可能变化；用最终渲染文本再校验，超高则退掉末行。
      if (pageBreak.end > pageStart) {
        while (true) {
          tp.text = TextSpan(text: pageText(body, pageBreak), style: style);
          tp.layout(maxWidth: maxWidth);
          if (tp.height <= budget) break;
          final pageLines = tp.computeLineMetrics();
          if (pageLines.length <= 1) {
            if (pageIndex == 0) pageBreak = PageBreak(pageStart, pageStart);
            break;
          }
          final end =
              pageStart +
              _lineStartCharOffset(tp, pageLines, pageLines.length - 1);
          if (end <= pageStart || end >= pageBreak.end) break;
          pageBreak = PageBreak(pageStart, end);
        }
      }
      tp.dispose();
      final consumed = pageBreak.end - pageStart;
      if (consumed > 0) windowLength = (consumed * 2).clamp(256, 4000);
      pageStart = pageBreak.end;
      pageIndex++;
      yield pageBreak;
    }
  }

  /// 第 [lineIndex] 行行首的字符位置（相对本次 layout 的文本）。
  static int _lineStartCharOffset(
    TextPainter tp,
    List<LineMetrics> lines,
    int lineIndex,
  ) {
    final lm = lines[lineIndex];
    final pos = tp.getPositionForOffset(
      Offset(lm.left + lm.width / 2, lm.baseline),
    );
    // 双向文字的视觉左端不一定是逻辑行首，必须取该行的文字区间。
    return tp.getLineBoundary(pos).start;
  }

  /// 页面渲染文本：截掉页尾换行/空格，避免末尾空行把内容顶出页面。
  static String pageText(String body, PageBreak b) {
    return body.substring(b.start, b.end).trimRight();
  }

  /// 找到包含 [charOffset] 的页下标（改字号后恢复阅读位置用）。
  static int pageIndexForOffset(List<PageBreak> breaks, int charOffset) {
    for (var i = 0; i < breaks.length; i++) {
      if (charOffset < breaks[i].end) return i;
    }
    return breaks.length - 1;
  }
}
