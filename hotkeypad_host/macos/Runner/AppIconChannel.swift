import AppKit
import FlutterMacOS
import UniformTypeIdentifiers

/// Serves application icons, lets the user pick their own image or a sound
/// file, and backs the Save/Open panels behind exporting and importing a
/// settings backup — all on the Dart side.
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
            case "pickSaveLocation":
                handlePickSaveLocation(call, result)
            case "pickOpenFile":
                handlePickOpenFile(result)
            case "pickAudio":
                handlePickAudio(result)
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

    /// Opens a native "Save As" panel pre-filled with the caller's suggested
    /// file name, restricted to JSON — a backup bundle is one JSON file.
    /// Resolves to the chosen path, or null if the user cancelled, the same
    /// stance `pickImage` takes on cancellation.
    private static func handlePickSaveLocation(
        _ call: FlutterMethodCall,
        _ result: @escaping FlutterResult
    ) {
        let arguments = call.arguments as? [String: Any]
        let suggestedName = arguments?["suggestedName"] as? String ?? "backup.json"
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.json]
        }
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                result(nil)
                return
            }
            result(url.path)
        }
    }

    /// Opens a native "Open" panel restricted to JSON files. Resolves to the
    /// chosen path, or null if the user cancelled.
    private static func handlePickOpenFile(_ result: @escaping FlutterResult) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.json]
        }
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                result(nil)
                return
            }
            result(url.path)
        }
    }

    /// Opens a native "Open" panel restricted to audio files, for a
    /// play-sound button. Resolves to the chosen path, or null if the user
    /// cancelled — the path, not the bytes, since the button plays the file
    /// from where it is.
    private static func handlePickAudio(_ result: @escaping FlutterResult) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.audio]
        }
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                result(nil)
                return
            }
            result(url.path)
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
