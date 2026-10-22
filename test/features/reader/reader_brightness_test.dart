import 'helpers/reader_test_support.dart';

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelverse/features/reader/logic/reader_brightness.dart';
import 'package:novelverse/features/reader/state/reader_brightness_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
    () => messenger.setMockMethodCallHandler(
      ReaderBrightnessDriver.channel,
      null,
    ),
  );

  test('退出时丢弃排队的旧设置，未完成设置之后的最后命令始终是还原', () async {
    final started = Completer<void>();
    final completeSet = Completer<void>();
    final calls = <String>[];
    var brightness = 0.7;
    messenger.setMockMethodCallHandler(ReaderBrightnessDriver.channel, (
      call,
    ) async {
      calls.add(call.method);
      if (call.method == 'getBrightness') return brightness;
      if (call.method == 'setBrightness') {
        started.complete();
        await completeSet.future;
        brightness = (call.arguments as Map)['brightness'] as double;
      } else if (call.method == 'resetBrightness') {
        brightness = 0.7;
      }
      return null;
    });
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
    expect(calls, ['getBrightness', 'setBrightness', 'resetBrightness']);
    expect(brightness, 0.7);
    await notifier.release();
    expect(calls.last, 'resetBrightness');
    expect(calls.where((method) => method == 'resetBrightness'), hasLength(1));
  });

  test('读取亮度尚未结束就离开页面，不写回已销毁的状态，也不修改亮度', () async {
    final started = Completer<void>();
    final read = Completer<double>();
    final calls = <String>[];
    messenger.setMockMethodCallHandler(ReaderBrightnessDriver.channel, (
      call,
    ) async {
      calls.add(call.method);
      started.complete();
      return read.future;
    });
    final container = ProviderContainer(overrides: readerTestOverrides());
    container.listen(readerBrightnessProvider, (_, _) {});
    await started.future;
    await container.read(readerBrightnessProvider.notifier).release();
    container.dispose();
    read.complete(0.8);
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['getBrightness']);
  });

  test('页面直接销毁时也会还原亮度', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(ReaderBrightnessDriver.channel, (
      call,
    ) async {
      calls.add(call.method);
      return call.method == 'getBrightness' ? 0.6 : null;
    });
    final container = ProviderContainer(overrides: readerTestOverrides());
    container.listen(readerBrightnessProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    container.read(readerBrightnessProvider.notifier).setBrightness(0.3);
    await Future<void>.delayed(Duration.zero);
    container.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['getBrightness', 'setBrightness', 'resetBrightness']);
  });

  test('平台不支持亮度时禁用调节，退出不产生无效修改', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(ReaderBrightnessDriver.channel, (
      call,
    ) async {
      calls.add(call.method);
      throw MissingPluginException();
    });
    final container = ProviderContainer(overrides: readerTestOverrides());
    addTearDown(container.dispose);
    container.listen(readerBrightnessProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    expect(container.read(readerBrightnessProvider).available, isFalse);
    expect(container.read(readerBrightnessProvider).error, isNotNull);
    final notifier = container.read(readerBrightnessProvider.notifier);
    notifier.setBrightness(0.2);
    await notifier.release();
    expect(calls, ['getBrightness']);
  });
}
