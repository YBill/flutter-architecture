import 'helpers/reader_test_support.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/features/reader/logic/reader_brightness.dart';
import 'package:novelverse/app/app.dart';
import 'package:novelverse/features/books/data/book_api.dart';
import 'package:novelverse/features/books/presentation/book_detail_page.dart';
import 'package:novelverse/features/reader/domain/reader_settings.dart';
import 'package:novelverse/features/reader/presentation/reader_page.dart';
import 'package:novelverse/features/reader/state/reader_brightness_provider.dart';
import 'package:novelverse/features/reader/state/reader_providers.dart';
import 'package:novelverse/features/books/data/book_cache.dart';
import 'package:novelverse/features/reader/widgets/paged_reader.dart';
import 'package:novelverse/features/reader/widgets/scroll_reader.dart';

void main() {
  testWidgets('Night mode仅影响阅读页，手动亮度在系统返回和按钮返回时都还原', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var currentBrightness = 0.72;
    double? originalBrightness;
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      ReaderBrightnessDriver.channel,
      (call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'getBrightness':
            return currentBrightness;
          case 'setBrightness':
            originalBrightness ??= currentBrightness;
            currentBrightness = (call.arguments as Map)['brightness'] as double;
            return null;
          case 'resetBrightness':
            currentBrightness = originalBrightness ?? currentBrightness;
            originalBrightness = null;
            return null;
          default:
            throw PlatformException(code: 'unexpected_method');
        }
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        ReaderBrightnessDriver.channel,
        null,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...readerTestOverrides(),
          bookCacheProvider.overrideWithValue(MemoryBookCache()),
          bookApiProvider.overrideWithValue(MockBookApi(delay: Duration.zero)),
        ],
        child: const NovelverseApp(),
      ),
    );
    await tester.pumpAndSettle();
    final originalOverlay = SystemChrome.latestStyle;
    final homeColor = tester
        .widget<Scaffold>(find.byType(Scaffold))
        .backgroundColor;
    await tester.tap(find.byKey(const ValueKey('start-reading')));
    await tester.pumpAndSettle();
    expect(currentBrightness, 0.72, reason: '进入时不覆盖系统亮度');
    await tester.tapAt(const Offset(370, 400));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NovelverseApp)),
    );
    final offset = container
        .read(readerPositionProvider(sampleBookId))
        .charOffset;
    final controller = tester
        .widget<PageView>(find.byType(PageView))
        .controller;
    await tester.tapAt(const Offset(195, 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Night mode'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('Night mode'))).brightness,
      Brightness.dark,
    );
    expect(
      tester
          .widgetList<Material>(
            find.ancestor(
              of: find.text('Night mode'),
              matching: find.byType(Material),
            ),
          )
          .any(
            (box) =>
                box.color ==
                container.read(readerSettingsProvider).surfaceColor,
          ),
      isTrue,
      reason: '弹层打开期间切换Night mode，实际背景也必须跟随变化',
    );
    expect(
      Theme.of(tester.element(find.byType(PagedReader))).brightness,
      Brightness.dark,
    );
    expect(
      tester.widget<PageView>(find.byType(PageView)).controller,
      same(controller),
      reason: '只改配色不重新分页',
    );
    expect(
      container.read(readerPositionProvider(sampleBookId)).charOffset,
      offset,
    );
    final body = tester
        .widgetList<Text>(
          find.byWidgetPredicate(
            (w) => w is Text && (w.data?.length ?? 0) > 100,
          ),
        )
        .first;
    expect(body.style?.color, container.read(readerSettingsProvider).textColor);

    tester.widget<Slider>(find.byType(Slider)).onChanged!(0.25);
    await tester.pumpAndSettle();
    expect(currentBrightness, 0.25);
    await tester.tap(find.text('Use system'));
    await tester.pumpAndSettle();
    expect(currentBrightness, 0.72);
    expect(container.read(readerBrightnessProvider).followSystem, isTrue);
    tester.widget<Slider>(find.byType(Slider)).onChanged!(0.4);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute(); // 只关闭Settings面板
    await tester.pumpAndSettle();
    expect(currentBrightness, 0.4);
    container
        .read(readerSettingsProvider.notifier)
        .update((s) => s.copyWith(mode: ReaderMode.scroll));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(ScrollReader))).brightness,
      Brightness.dark,
    );
    expect(currentBrightness, 0.4, reason: '切换阅读模式不还原亮度');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(BookDetailPage), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(BookDetailPage), findsOneWidget);
    expect(find.byType(ReaderPage), findsNothing);
    expect(currentBrightness, 0.72);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      homeColor,
    );
    expect(
      Theme.of(tester.element(find.byType(BookDetailPage))).brightness,
      Brightness.light,
    );
    expect(
      SystemChrome.latestStyle?.statusBarIconBrightness,
      originalOverlay?.statusBarIconBrightness,
    );
    expect(
      SystemChrome.latestStyle?.systemNavigationBarColor,
      originalOverlay?.systemNavigationBarColor,
    );

    await tester.tap(find.byKey(const ValueKey('start-reading')));
    await tester.pumpAndSettle();
    expect(currentBrightness, 0.72);
    expect(container.read(readerBrightnessProvider).followSystem, isTrue);
    container.read(readerBrightnessProvider.notifier).setBrightness(0.35);
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(195, 400));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back to book'));
    await tester.pumpAndSettle();
    expect(currentBrightness, 0.72);
    expect(find.byType(BookDetailPage), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(BookDetailPage), findsOneWidget);
    expect(calls.where((method) => method == 'resetBrightness'), hasLength(3));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
