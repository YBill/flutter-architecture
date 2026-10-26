import 'helpers/reader_test_support.dart';
import 'helpers/fake_screen_brightness.dart';

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/features/reader/logic/reader_brightness.dart';
import 'package:novelverse/features/reader/state/reader_brightness_provider.dart';
import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeScreenBrightness platform;
  setUp(() {
    final original = ScreenBrightnessPlatform.instance;
    platform = FakeScreenBrightness();
    ScreenBrightnessPlatform.instance = platform;
    addTearDown(() => ScreenBrightnessPlatform.instance = original);
  });

  test('读取当前应用亮度，并启用插件自动还原、关闭亮度渐变', () async {
    platform.brightness = 0.62;
    expect(await ReaderBrightnessDriver().read(), 0.62);
    expect(platform.autoReset, isTrue);
    expect(platform.animate, isFalse);
    expect(platform.calls, ['getApplicationScreenBrightness']);
  });

  test('退出时丢弃排队的旧设置，未完成设置之后的最后命令始终是还原', () async {
    final started = Completer<void>();
    final completeSet = Completer<void>();
    final calls = platform.calls;
    platform.onSet = (_) async {
      started.complete();
      await completeSet.future;
    };
    final container = ProviderContainer(overrides: readerTestOverrides());
    addTearDown(container.dispose);
    container.listen(readerBrightnessProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    final notifier = container.read(readerBrightnessProvider.notifier);
    notifier.setBrightness(0.2);
    await started.future;
    notifier.setBrightness(0.4);
    final release = notifier.release();
    completeSet.complete();
    await release;
    expect(calls, [
      'getApplicationScreenBrightness',
      'setApplicationScreenBrightness',
      'resetApplicationScreenBrightness',
    ]);
    expect(platform.brightness, 0.7);
    await notifier.release();
    expect(calls.last, 'resetApplicationScreenBrightness');
    expect(
      calls.where((method) => method == 'resetApplicationScreenBrightness'),
      hasLength(1),
    );
  });

  test('读取亮度尚未结束就离开页面，不写回已销毁的状态，也不修改亮度', () async {
    final started = Completer<void>();
    final read = Completer<double>();
    final calls = platform.calls;
    platform.onRead = () async {
      started.complete();
      return read.future;
    };
    final container = ProviderContainer(overrides: readerTestOverrides());
    container.listen(readerBrightnessProvider, (_, _) {});
    await started.future;
    await container.read(readerBrightnessProvider.notifier).release();
    container.dispose();
    read.complete(0.8);
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['getApplicationScreenBrightness']);
  });

  test('页面直接销毁时也会还原亮度', () async {
    final calls = platform.calls;
    platform.brightness = 0.6;
    final container = ProviderContainer(overrides: readerTestOverrides());
    container.listen(readerBrightnessProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    container.read(readerBrightnessProvider.notifier).setBrightness(0.3);
    await Future<void>.delayed(Duration.zero);
    container.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(calls, [
      'getApplicationScreenBrightness',
      'setApplicationScreenBrightness',
      'resetApplicationScreenBrightness',
    ]);
    expect(platform.brightness, 0.6);
  });

  test('平台不支持亮度时禁用调节，退出不产生无效修改', () async {
    final calls = platform.calls;
    platform.onRead = () async => throw MissingPluginException();
    final container = ProviderContainer(overrides: readerTestOverrides());
    addTearDown(container.dispose);
    container.listen(readerBrightnessProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    expect(container.read(readerBrightnessProvider).available, isFalse);
    expect(container.read(readerBrightnessProvider).error, isNotNull);
    final notifier = container.read(readerBrightnessProvider.notifier);
    notifier.setBrightness(0.2);
    await notifier.release();
    expect(calls, ['getApplicationScreenBrightness']);
  });
}
