import Flutter
import UIKit

// Adopts the UIScene lifecycle (see UIApplicationSceneManifest in
// Info.plist): iOS 27 terminates an app built against its SDK at launch if
// it still relies on the app-delegate-only lifecycle. Under scenes the
// window and its FlutterViewController do not exist yet when
// didFinishLaunchingWithOptions runs, so plugins and channels are
// registered once the implicit engine is up instead.
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

    // Serves this phone's own Bluetooth-assigned name to the Dart side —
    // see DeviceInfo in lib/src/device_info.dart. UIDevice.name is generic
    // ("iPhone") for every third-party app since iOS 16; that is a platform
    // limitation this channel cannot work around.
    let channel = FlutterMethodChannel(
      name: "btlink/device",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "name":
        result(UIDevice.current.name)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
