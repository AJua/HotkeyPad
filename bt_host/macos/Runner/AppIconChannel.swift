import AppKit
import FlutterMacOS

/// Serves application icons to the Dart side.
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
            guard call.method == "icon" else {
                result(FlutterMethodNotImplemented)
                return
            }
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
