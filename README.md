# BTLink

Two Flutter apps that talk to each other over Bluetooth Low Energy.

| Project     | Role                | BLE role   |
| ----------- | ------------------- | ---------- |
| `bt_host`   | the host service    | peripheral |
| `bt_client` | the client app      | central    |

`bt_host` publishes a GATT service and advertises it. `bt_client` scans and
lists what it finds, tagging anything that advertises the BTLink service.

## What it does

A Stream Deck Mobile for your Mac: the phone is the deck, the Mac runs the
service, and the buttons launch applications over BLE.

- The client scans, lists nearby devices, and tags BTLink hosts.
- Tapping a host connects, discovers GATT and subscribes.
- On connect the client asks for the app catalogue; the host scans its
  application directories and streams the names back.
- **The deck shows only the apps the user chose**, in the order they chose.
  Pressing one launches it on the host, which replies with an ack.
- **Deck settings** (tune icon) is where the catalogue lives: tick apps to add
  them, drag the chosen ones to reorder, search to find one among ~100.
- Free-text messaging survives as the **debug console** (bug icon), which also
  shows every message on the link.

The chosen deck is stored locally per host (`shared_preferences`, keyed by the
host's peripheral UUID), so the buttons are usable the moment the app opens
rather than after the catalogue finishes arriving, and two hosts keep separate
layouts.

Buttons show the app's real icon, fetched once and cached on disk; the first
letter stands in until one arrives.

Not done yet: actions beyond launching (media keys, shortcuts, scripts),
folders/pages of buttons, reconnect on wake, and bonding.

## Message protocol

`protocol.dart` (identical in both projects) defines a sealed `BtMessage`
hierarchy encoded as single-line JSON, one message per ATT operation:

| Message     | Direction       | Purpose                          |
| ----------- | --------------- | -------------------------------- |
| `ls`        | client -> host  | send the app catalogue           |
| `app`       | host -> client  | one catalogue entry              |
| `end`       | host -> client  | catalogue complete               |
| `open`      | client -> host  | launch an app                    |
| `ack`       | host -> client  | result of the last command       |
| `txt`       | either          | debug console traffic            |
| `ico`       | client -> host  | send this app's icon             |
| `ico!`      | host -> client  | there is no icon, stop waiting   |

There is no reassembly: a message must fit the negotiated MTU. The client
requests a 512-byte MTU on Android, and the host refuses to send anything
larger than `getMaximumNotifyLength` reports rather than truncating it. The
catalogue is therefore streamed as one small notification per app, paced at
20ms so the notification queue does not overflow.

Keys are one or two characters, and `BtMessage.decode` returns null for
anything it does not recognise, so a version mismatch degrades instead of
crashing.

### Icons are binary, not JSON

A 64px PNG is ~5KB. Base64 inside a JSON message would inflate that by a
third and, at the MTU an iPhone negotiates, need roughly sixty notifications
per icon. Icons therefore travel as binary frames on the same characteristic:

```
[0x01][nameLength][name utf8][index u16be][total u16be][payload]
```

A JSON message always starts with `{` (0x7b), so the leading `0x01` tells the
two apart unambiguously. The app name is repeated in every frame rather than
kept as connection state, so reassembly stays correct even if two icons
interleave.

The host renders icons with `NSWorkspace.icon(forFile:)` through a method
channel (`macos/Runner/AppIconChannel.swift`) rather than reading
`CFBundleIconFile` from Info.plist: modern apps keep their icon inside
`Assets.car`, where the plist route finds nothing, and AppKit also returns a
sensible generic icon for apps that have none.

`BtLink.iconSize` (128) is shared by both projects. Deck buttons fill their
whole tappable area with the icon, so on a 3x phone screen it is scaled to
roughly 300 physical pixels and 64px was visibly soft. The cost is ~15KB per
icon instead of ~5KB — around 87 frames and under two seconds each at the MTU
an iPhone negotiates, paid once because of the cache. Cache filenames carry
the size (`<hex>@128`), so changing the constant invalidates stored icons
rather than leaving a set at the old resolution.

### Transfer ordering

The catalogue is delivered before any icon. Names make the deck usable;
pictures only make it pretty, and interleaving ~100 catalogue notifications
with 5KB icons would delay the labels far longer than it delays the images.

Two mechanisms enforce it. The client will not drain its icon queue while
`_loadingApps` is set, and starts draining when `ListEnd` arrives. The host
funnels every multi-notification transfer through a single promise chain, so
a catalogue in flight completes before an icon begins.

Icons are cached on the client's disk per host (`icon_cache.dart`), so this
cost is paid once. A cached icon is read immediately and is *not* held back
by the catalogue, since reading it costs nothing on the link. Files rather
than preferences: shared_preferences is loaded into memory wholesale at
startup, so a deck of thirty icons would weigh on every launch whether the
deck is opened or not.

## A pinned dependency worth revisiting

`bt_client/pubspec.yaml` holds `path_provider_foundation` at **2.5.1** via
`dependency_overrides`. From 2.6.0 that package loads a dylib through
Flutter's native-assets mechanism (via `objective_c`); on this toolchain
(Flutter 3.38.5) it fails to resolve on macOS and crashes the app at launch
on iOS with `EXC_BAD_ACCESS`. 2.5.1 is the last plain method-channel release.

`dependency_overrides` silently wins over the whole resolution graph, so this
is the kind of pin that rots unnoticed. To retire it: drop the override, run
`flutter pub get`, and check that `pubspec.lock` gains no `objective_c` and
that `build/ios/iphoneos/Runner.app/Frameworks` gains no
`objective_c.framework`. Then run it on a physical iPhone — the macOS
symptom and the iOS symptom were different, and only the device showed the
crash.

Note that removing a native dependency does not remove its framework from an
existing build directory. `flutter clean` is required, or the stale framework
loads against a Dart side that no longer registers it and the app opens to a
white screen.

## The macOS host is not sandboxed

`com.apple.security.app-sandbox` is **false** in both entitlements files. The
sandbox forbids launching other applications, which is the host's entire
purpose. This rules out App Store distribution — the same reason the real
Stream Deck ships outside it.

Launching is macOS-only (`open -a`). On every other platform the host reports
the gap in its status card and acks failures honestly rather than pretending
the button worked.

## Why the host list stays empty until a client subscribes

CoreBluetooth's `CBPeripheralManager` has no connect/disconnect callback, so
on macOS and iOS `connectionStateChanged` throws `UnsupportedError` (see
`bluetooth_low_energy_darwin/lib/src/peripheral_manager_impl.dart`). A central
becomes visible to the host only when it *acts* — subscribes, reads or writes.
The host therefore builds its client list from those events, and Android's
connection events on top where available.

Note also that the host's client list is unrelated to the devices macOS shows
in its own Bluetooth panel. Those are peripherals paired to the OS; this list
is centrals attached to this app's GATT server.

## The shared contract

`lib/src/protocol.dart` is duplicated verbatim in both projects. Change a UUID
in one and you must change it in the other. If this grows, promote it to a
shared package under `packages/bt_link_protocol` and depend on it by path.

## Android permission flow

The runtime permission must be requested on entry, not behind the Scan /
Start advertising button. Android reports the adapter as `unauthorized` until
`BLUETOOTH_SCAN` + `BLUETOOTH_CONNECT` are granted, so gating the button on
`poweredOn` deadlocks: the button that would ask for the permission is
disabled by the very state the permission unlocks. Both apps call
`authorize()` from a post-frame callback and the banner carries a Grant
action as a second chance.

The cached `state` is not refreshed by granting — the plugin only re-reads it
on app resume — so discovery/advertising must not be gated on it immediately
after `authorize()` returns.

`ACCESS_COARSE_LOCATION` is declared alongside `ACCESS_FINE_LOCATION` for
Android 11 and below: the plugin requests both there, and a permission that
is not declared is denied outright.

## Verified on hardware

Galaxy A54 (Android 16) as client, macOS as host:

- client scan lists ~200 nearby devices
- the host shows up as `BTLink` with the HOST badge at -52 dBm
- tapping it reaches Connected + Subscribed
- text typed on the client arrives at the host (`wrote: hello from android`)

That run predates the deck and used Android as the client. The user has since confirmed on hardware that
launching apps works and the catalogue arrives.

Covered by tests: `bt_host/test/app_launcher_test.dart` scans this machine for
real (96 apps found, `Safari` among them) and checks a nonexistent app fails
cleanly; `bt_client/test/deck_store_test.dart` covers the reorder off-by-one
and per-host persistence.

Not yet exercised on hardware: the settings/deck flow, and host -> client
notifications.

## Platform support

| Platform | Client (scan) | Host (advertise) |
| -------- | ------------- | ---------------- |
| Android  | yes           | yes              |
| iOS      | yes           | yes              |
| macOS    | yes           | yes              |
| Windows  | yes           | partial          |
| Linux    | yes           | partial          |
| Web      | no            | no               |

All six targets are scaffolded and compile. On web there is no BLE plugin at
all, so both apps detect the missing implementation at startup and show an
"unavailable on this platform" screen instead of crashing.

Windows and Linux report fewer events than Android and Apple do — advertised
device names, connect/disconnect callbacks and service data are not always
available. The code catches `UnsupportedError` where the plugin documents
those gaps rather than assuming every platform behaves like Android.

## Running

Two devices are needed — a radio cannot usefully discover itself.

```sh
cd bt_host   && flutter run -d <device-a>   # tap "Start advertising"
cd bt_client && flutter run -d <device-b>   # tap "Scan"
```

The host should appear in the client's list with a `HOST` badge. Filter the
list down to just hosts with the chip at the top, then tap the row to connect.

The deck starts empty. Open **Deck settings** (tune icon), tick the apps you
want, drag them into the order you like, then go back and press one. The bug
icon opens the debug console.

### iOS client

`flutter build ios` works. The Runner target is signed with a personal team
(`com.chienhunglin.btClient`), which is what a physical device needs; the
RunnerTests target still carries the original `com.titansoft` prefix, which
only matters if you run the XCTest target.

iOS has no MTU request API, so the stage indicator shows no MTU number there —
CoreBluetooth negotiates on its own, and what it settles on is comfortably
larger than any message this protocol sends. The per-host deck is keyed by
`CBPeripheral.identifier`, which is stable for a given device and app install
but is reassigned if the app is reinstalled.

### Prerequisites

- **macOS/iOS builds** need CocoaPods (installed here, 1.17.0).
- **Linux** needs BlueZ (`bluez`, and `libdbus-1-dev` to build).
- **Android** needs a real device; the emulator has no Bluetooth radio.
- **macOS host** may need Bluetooth enabled for the app in
  System Settings → Privacy & Security → Bluetooth on first run.

## Permissions already configured

- Android: `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, `BLUETOOTH_ADVERTISE` (host),
  plus the pre-Android-12 legacy and location permissions.
- iOS/macOS: `NSBluetoothAlwaysUsageDescription` in `Info.plist` and the
  `com.apple.security.device.bluetooth` sandbox entitlement.

The apps call `authorize()` on Android before scanning or advertising.
