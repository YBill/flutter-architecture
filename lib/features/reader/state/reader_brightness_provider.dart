import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic/reader_brightness.dart';

class ReaderBrightnessState {
  const ReaderBrightnessState({
    this.value,
    this.followSystem = true,
    this.error,
  });

  final double? value;
  final bool followSystem;
  final String? error;
  bool get available => value != null && error == null;
}

final _brightnessDriverProvider = Provider((ref) => ReaderBrightnessDriver());

/// 只在阅读页存在期间存活。原生端另行处理切后台时的还原及回前台时的恢复。
class ReaderBrightnessNotifier extends Notifier<ReaderBrightnessState>
    with WidgetsBindingObserver {
  late ReaderBrightnessDriver _driver;
  int _revision = 0;
  bool _closed = false;
  bool _hasOverride = false;
  Future<void>? _releaseFuture;

  @override
  ReaderBrightnessState build() {
    _driver = ref.read(_brightnessDriverProvider);
    WidgetsBinding.instance.addObserver(this);
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      unawaited(release());
    });
    unawaited(_load(++_revision));
    return const ReaderBrightnessState();
  }

  bool _isCurrent(int revision) =>
      !_closed && ref.mounted && revision == _revision;

  Future<void> _load(int revision) async {
    try {
      final value = await _driver.read();
      if (_isCurrent(revision)) state = ReaderBrightnessState(value: value);
    } catch (_) {
      if (_isCurrent(revision)) {
        state = const ReaderBrightnessState(
          error: 'Brightness control is unavailable on this device',
        );
      }
    }
  }

  void setBrightness(double value) {
    if (_closed || !state.available) return;
    final revision = ++_revision;
    value = value.clamp(0.05, 1.0);
    state = ReaderBrightnessState(value: value, followSystem: false);
    _hasOverride = true;
    unawaited(_apply(value, revision));
  }

  Future<void> _apply(double value, int revision) async {
    try {
      await _driver.set(value, () => _isCurrent(revision));
    } catch (_) {
      if (!_isCurrent(revision)) return;
      state = ReaderBrightnessState(
        value: state.value,
        error: 'Could not adjust brightness. Please reopen the reader.',
      );
      await _resetSafely();
    }
  }

  void useSystemBrightness() {
    if (_closed || !state.available) return;
    final revision = ++_revision;
    state = ReaderBrightnessState(value: state.value);
    unawaited(_useSystem(revision));
  }

  Future<void> _useSystem(int revision) async {
    try {
      await _driver.reset();
      if (!_isCurrent(revision)) return;
      _hasOverride = false;
      await _load(revision);
    } catch (_) {
      if (_isCurrent(revision)) {
        state = ReaderBrightnessState(
          value: state.value,
          error: 'Could not restore system brightness. Please close the reader and try again.',
        );
      }
    }
  }

  Future<void> _resetSafely() async {
    try {
      await _driver.reset();
    } catch (error) {
      debugPrint('Could not restore reader brightness: $error');
    }
  }

  /// PopScope 在返回开始时调用，dispose 也会兜底；重复调用不会重复还原。
  Future<void> release() {
    if (_releaseFuture != null) return _releaseFuture!;
    _closed = true;
    _revision++;
    return _releaseFuture = _hasOverride
        ? _resetSafely()
        : Future<void>.value();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  void refresh() {
    if (!_closed && state.followSystem) {
      unawaited(_load(++_revision));
    }
  }
}

final readerBrightnessProvider =
    NotifierProvider.autoDispose<
      ReaderBrightnessNotifier,
      ReaderBrightnessState
    >(ReaderBrightnessNotifier.new);
