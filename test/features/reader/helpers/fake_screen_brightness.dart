import 'package:screen_brightness_platform_interface/screen_brightness_platform_interface.dart';

class FakeScreenBrightness extends ScreenBrightnessPlatform {
  FakeScreenBrightness({this.brightness = 0.7});

  double brightness;
  double? _originalBrightness;
  bool autoReset = false;
  bool animate = true;
  final calls = <String>[];
  Future<double> Function()? onRead;
  Future<void> Function(double)? onSet;

  @override
  Future<void> setAutoReset(bool value) async => autoReset = value;

  @override
  Future<void> setAnimate(bool value) async => animate = value;

  @override
  Future<double> get application async {
    calls.add('getApplicationScreenBrightness');
    return onRead == null ? brightness : await onRead!();
  }

  @override
  Future<void> setApplicationScreenBrightness(double value) async {
    calls.add('setApplicationScreenBrightness');
    await onSet?.call(value);
    _originalBrightness ??= brightness;
    brightness = value;
  }

  @override
  Future<void> resetApplicationScreenBrightness() async {
    calls.add('resetApplicationScreenBrightness');
    brightness = _originalBrightness ?? brightness;
    _originalBrightness = null;
  }
}
