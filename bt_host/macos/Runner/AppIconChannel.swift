import AppKit
import FlutterMacOS
import UniformTypeIdentifiers

/// Serves application icons, and lets the user pick their own image, on the
/// Dart side.
///
/// `NSWorkspace.icon(forFile:)` is used rather than reading `CFBundleIconFile`
/// out of Info.plist: modern apps ship their icon inside `Assets.car`, where
/// the plist route finds nothing, and this call also returns a sensible
/// generic icon for apps that have none.
enum AppIconChannel {
    static let name = "btlink/icons"

    static func register(with controller: FlutterViewController) {
        let channel = FlutterMethodChannel(
            name: name,
            binaryMessenger: controller.engine.binaryMessenger
        )
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "icon":
                handleIcon(call, result)
            case "pickImage":
                handlePickImage(result)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private static func handleIcon(
        _ call: FlutterMethodCall,
        _ result: @escaping FlutterResult
    ) {
        guard let arguments = call.arguments as? [String: Any],
              let path = arguments["path"] as? String
        else {
            result(
                FlutterError(
                    code: "bad-arguments",
                    message: "icon requires a path",
                    details: nil
                )
            )
            return
        }
        let size = arguments["size"] as? Int ?? 64
        guard let data = pngIcon(forApp: path, size: size) else {
            result(
                FlutterError(
                    code: "no-icon",
                    message: "Could not render an icon for \(path)",
                    details: nil
                )
            )
            return
        }
        result(FlutterStandardTypedData(bytes: data))
    }

    /// Opens a file picker restricted to images. Resolves to the picked
    /// file's raw bytes, or null if the user cancelled — cancelling is not
    /// an error, so this never calls `result` with a `FlutterError` for it.
    ///
    /// No sandbox entitlement is needed to read the result: the app has
    /// `com.apple.security.app-sandbox` off (see the .entitlements files),
    /// the same reason launching other applications works at all.
    private static func handlePickImage(_ result: @escaping FlutterResult) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.image]
        }
        panel.begin { response in
            guard response == .OK, let url = panel.url,
                  let data = try? Data(contentsOf: url)
            else {
                result(nil)
                return
            }
            result(FlutterStandardTypedData(bytes: data))
        }
    }

    private static func pngIcon(forApp path: String, size: Int) -> Data? {
        let image = NSWorkspace.shared.icon(forFile: path)
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(
            bitmapImageRep: representation
        )
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()

        return representation.representation(using: .png, properties: [:])
    }
}
