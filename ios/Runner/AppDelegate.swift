import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ReaderBrightness") {
      ReaderBrightnessPlugin.register(with: registrar)
    }
  }
}

/// iOS 的屏幕亮度会影响整个设备，需要保存首次调节前的值并主动还原。
private class ReaderBrightnessPlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  private let registrar: FlutterPluginRegistrar
  private var originalBrightness: CGFloat?
  private var readerBrightness: CGFloat?
  private var controlledScreen: UIScreen?
  private var isForeground = false

  private var screen: UIScreen {
    registrar.viewController?.view.window?.windowScene?.screen ?? UIScreen.main
  }

  private init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    super.init()
    isForeground = UIApplication.shared.applicationState == .active
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = ReaderBrightnessPlugin(registrar: registrar)
    let channel = FlutterMethodChannel(name: "com.novel.novelverse/brightness", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
    registrar.addSceneDelegate(instance)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getBrightness":
      result(Double(screen.brightness))
    case "setBrightness":
      guard let args = call.arguments as? [String: Any],
        let value = args["brightness"] as? Double,
        value.isFinite, (0.0...1.0).contains(value) else {
        result(FlutterError(code: "invalid_brightness", message: "Brightness must be between 0 and 1", details: nil))
        return
      }
      if originalBrightness == nil {
        controlledScreen = screen
        originalBrightness = screen.brightness
      }
      readerBrightness = CGFloat(value)
      if isForeground { controlledScreen?.brightness = CGFloat(value) }
      result(nil)
    case "resetBrightness":
      resetBrightness()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func resetBrightness() {
    // 后台已经还原过，不覆盖用户随后在控制中心调节的新亮度。
    if isForeground, let value = originalBrightness { controlledScreen?.brightness = value }
    readerBrightness = nil
    originalBrightness = nil
    controlledScreen = nil
  }

  func sceneWillResignActive(_ scene: UIScene) {
    guard isForeground else { return }
    isForeground = false
    if let value = originalBrightness { controlledScreen?.brightness = value }
  }

  func sceneDidBecomeActive(_ scene: UIScene) {
    guard !isForeground else { return }
    isForeground = true
    if let value = readerBrightness {
      // 在后台调整过系统亮度时，退出阅读器应恢复这个最新值。
      controlledScreen = screen
      originalBrightness = screen.brightness
      controlledScreen?.brightness = value
    }
  }

  func sceneDidDisconnect(_ scene: UIScene) { resetBrightness() }
  func applicationWillTerminate(_ application: UIApplication) { resetBrightness() }
  func detachFromEngine(for registrar: FlutterPluginRegistrar) { resetBrightness() }
}
