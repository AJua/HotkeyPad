import AppKit
import FlutterMacOS

/// Posts system media keys on behalf of the Dart side.
///
/// macOS routes play/pause and track skipping through HID system events, not
/// through any scriptable interface. Posting them requires the app to be
/// trusted for Accessibility; without that, `CGEvent.post` reports success and
/// the event is silently dropped, so the trust state is reported explicitly
/// rather than letting a button appear to work.
enum MediaKeyChannel {
    static let name = "btlink/media"

    // From IOKit/hidsystem/ev_keymap.h
    private static let keys: [String: Int32] = [
        "playpause": 16,  // NX_KEYTYPE_PLAY
        "next": 17,       // NX_KEYTYPE_FAST
        "previous": 18,   // NX_KEYTYPE_REWIND
    ]

    static func register(with controller: FlutterViewController) {
        let channel = FlutterMethodChannel(
            name: name,
            binaryMessenger: controller.engine.binaryMessenger
        )
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "trusted":
                result(AXIsProcessTrusted())

            case "requestTrust":
                // Shows the system prompt that deep-links to the
                // Accessibility pane. Returns the state before the user acts.
                let options =
                    [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                        as CFDictionary
                result(AXIsProcessTrustedWithOptions(options))

            case "key":
                guard let arguments = call.arguments as? [String: Any],
                      let name = arguments["key"] as? String,
                      let key = keys[name]
                else {
                    result(
                        FlutterError(
                            code: "bad-arguments",
                            message: "unknown media key",
                            details: nil
                        )
                    )
                    return
                }
                guard AXIsProcessTrusted() else {
                    result(
                        FlutterError(
                            code: "not-trusted",
                            message:
                                "Grant this app Accessibility in System Settings "
                                + "> Privacy & Security > Accessibility",
                            details: nil
                        )
                    )
                    return
                }
                post(key)
                result(true)

            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private static func post(_ key: Int32) {
        for isDown in [true, false] {
            let flags: UInt = isDown ? 0xa00 : 0xb00
            let data1 = Int((key << 16) | Int32(flags))
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: flags),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            ) else { continue }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
