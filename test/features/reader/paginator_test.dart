import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/features/reader/logic/paginator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const style = TextStyle(fontSize: 18, height: 1.45);

  test('分页结果：页区间单调、覆盖全文、至少一行', () {
    final body = ('这是一段用于测试的中文正文。' * 300);
    final breaks = Paginator.paginateChapter(
      body: body,
      style: style,
      maxWidth: 380,
      heightForPage: (page) => page == 0 ? 600 : 700,
    );

    expect(breaks.length, greaterThan(1));
    expect(breaks.first.start, 0);
    expect(breaks.last.end, body.length);
    for (var i = 0; i < breaks.length; i++) {
      expect(breaks[i].end, greaterThan(breaks[i].start), reason: '第 $i 页不能为空');
      if (i > 0) {
        expect(breaks[i].start, breaks[i - 1].end, reason: '页区间必须首尾相接');
      }
    }
  });

  test('pageIndexForOffset 能找回字符所在的页', () {
    final body = '段落一。' * 500;
    final breaks = Paginator.paginateChapter(
      body: body,
      style: style,
      maxWidth: 380,
      heightForPage: (_) => 700,
    );
    final mid = body.length ~/ 2;
    final page = Paginator.pageIndexForOffset(breaks, mid);
    expect(breaks[page].start, lessThanOrEqualTo(mid));
    expect(mid, lessThan(breaks[page].end));
  });

  test('pageText 会截掉页尾换行', () {
    final body = '第一行内容\n第二行内容\n第三行内容';
    final breaks = Paginator.paginateChapter(
      body: body,
      style: style,
      maxWidth: 380,
      heightForPage: (_) => 40, // 每页一行
    );
    expect(Paginator.pageText(body, breaks.first), '第一行内容');
  });

  test('首页被标题挤占得放不下首行时：首页只放标题，正文从次页满高开始', () {
    final body = '正文第一行。\n正文第二行。\n正文第三行。';
    final breaks = Paginator.paginateChapter(
      body: body,
      style: style,
      maxWidth: 380,
      heightForPage: (page) => page == 0 ? 10 : 700, // 首页预算连一行都不够
    );

    expect(breaks.first.start, 0);
    expect(breaks.first.end, 0, reason: '首页应是仅标题的空正文页，不能强塞首行再裁剪');
    expect(Paginator.pageText(body, breaks.first), isEmpty);
    expect(Paginator.pageIndexForOffset(breaks, 0), 1, reason: '正文第一字在第二页');
    expect(breaks[1].start, 0, reason: '正文从次页开始，无文字被分页吞掉');
    expect(breaks.last.end, body.length);
    for (var i = 1; i < breaks.length; i++) {
      expect(
        breaks[i].end,
        greaterThan(breaks[i].start),
        reason: '第 $i 页必须有实际内容',
      );
    }
  });

  test('回归：每页子串独立排版必须放进自己的预算（防页尾截字）', () {
    final body = List.generate(40, (i) {
      return '　　这是第$i段测试正文，用来验证分页测量与逐页渲染保持一致，'
          '句子足够长以便产生多行折行，并覆盖段首缩进的场景。';
    }).join('\n\n');

    for (final fontSize in [14.0, 18.0, 20.0, 28.0]) {
      final s = TextStyle(fontSize: fontSize, height: 1.45);
      const firstPageBudget = 560.0;
      const pageBudget = 620.0;
      final breaks = Paginator.paginateChapter(
        body: body,
        style: s,
        maxWidth: 316,
        heightForPage: (page) => page == 0 ? firstPageBudget : pageBudget,
      );

      expect(breaks.length, greaterThan(2), reason: '字号 $fontSize 应产生多页');
      for (var i = 0; i < breaks.length; i++) {
        final sub = Paginator.pageText(body, breaks[i]);
        final tp = TextPainter(
          text: TextSpan(text: sub, style: s),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.noScaling,
        )..layout(maxWidth: 316);
        final used = tp.computeLineMetrics().fold<double>(
          0.0,
          (sum, l) => sum + l.height,
        );
        final budget = i == 0 ? firstPageBudget : pageBudget;
        expect(
          used,
          lessThanOrEqualTo(budget),
          reason: '字号 $fontSize 第 $i 页排版高度 $used 超出预算 $budget，渲染会截字',
        );
        tp.dispose();
      }
    }
  });
}
