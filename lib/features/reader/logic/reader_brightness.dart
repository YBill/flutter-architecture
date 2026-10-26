import 'package:flutter/services.dart';

/// 各次阅读共用队列，确保退出时的还原排在未完成的亮度设置之后。
class ReaderBrightnessDriver {
  static const channel = MethodChannel(
    'com.nova.novel.reader.stories/brightness',
  );
  Future<void> _pending = Future<void>.value();

  Future<T> _run<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<double> read() => _run(() async {
    final value = await channel.invokeMethod<double>('getBrightness');
    if (value == null || !value.isFinite) {
      throw StateError('Invalid brightness');
    }
    return value.clamp(0.05, 1.0);
  });

  Future<void> set(double value, bool Function() isCurrent) => _run(() async {
    // 快速拖动或已经离页的旧请求不用再发往原生端。
    if (isCurrent()) {
      await channel.invokeMethod<void>('setBrightness', {'brightness': value});
    }
  });

  Future<void> reset() =>
      _run(() => channel.invokeMethod<void>('resetBrightness'));
}
