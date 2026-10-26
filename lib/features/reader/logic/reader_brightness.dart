import 'package:screen_brightness/screen_brightness.dart';

/// 各次阅读共用队列，确保退出时的还原排在未完成的亮度设置之后。
class ReaderBrightnessDriver {
  final _brightness = ScreenBrightness.instance;
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
    // 由插件处理前后台还原；禁用渐变，避免退出后残留动画再次改变亮度。
    await _brightness.setAutoReset(true);
    await _brightness.setAnimate(false);
    final value = await _brightness.application;
    if (!value.isFinite) {
      throw StateError('Invalid brightness');
    }
    return value.clamp(0.05, 1.0);
  });

  Future<void> set(double value, bool Function() isCurrent) => _run(() async {
    // 快速拖动或已经离页的旧请求不用再发往原生端。
    if (isCurrent()) {
      await _brightness.setApplicationScreenBrightness(value);
    }
  });

  Future<void> reset() =>
      _run(() => _brightness.resetApplicationScreenBrightness());
}
