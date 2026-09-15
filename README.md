# HotkeyPad

Two Flutter apps that talk to each other over Bluetooth Low Energy or WiFi —
whichever the two happen to find first (see [Message protocol](#message-protocol)
for how a WiFi link differs on the wire).

| Project     | Role                | BLE role   |
| ----------- | ------------------- | ---------- |
| `hotkeypad_host`   | the host service    | peripheral |
| `hotkeypad_client` | the client app      | central    |

`hotkeypad_host` publishes a GATT service (and, over WiFi, a TCP listener plus a
discovery beacon), and is where the deck is arranged. `hotkeypad_client` finds
that service by itself, over whichever transport answers first, and renders
whatever it is sent.

## What it does

A Stream Deck for your Mac: the phone is the deck, the Mac runs the service,
and the two talk over BLE or WiFi. A button can launch an app, work the media
keys, send a keyboard combination, run a shell command, or fire a macOS
Shortcut.

- **The client opens straight onto the deck.** It scans in the background,
  takes the first host that advertises the HotkeyPad service, and connects. With
  one Mac in the room there is nothing to choose between, so a device picker
  was a step to dismiss rather than a feature.
- The scanner survives as a diagnostic under the debug console: what this
  radio can see, and which of it speaks HotkeyPad. It is for working out why the
  automatic connection did not happen, not for making it happen.
- On connect the client asks for the layout and the app catalogue; the host
  streams both back.
- **The host owns the layout.** Arranging a grid on a phone screen is
  miserable, and the host is where the app list already lives, so the host
  window *is* the editor: a grid of cells, click one to choose what it does,
  drag a button to move it. Grid size, appearance and the service details
  live behind a gear, so the window shows the deck and little else. The
  default grid is 5 x 3.
- **Service details are a diagnostic**, reached from that gear — the host's
  equivalent of the client's debug console. Advertising state, connected
  clients and the activity log are for working out why the deck is
  misbehaving, not for daily use.
- **The client renders what it is sent.** It has no settings of its own. The
  host pushes the layout on connect and again after every edit, so the phone
  updates while you arrange the grid.
- Empty cells are drawn rather than skipped, so buttons stay where they were
  put. Every button is visible at once — that is the entire point of a deck —
  in a centred block rather than stretched to fill: filling made buttons wide
  in landscape and tall in portrait, and left uneven margins once the app bar
  took an edge. Whichever axis has room to spare becomes equal margin on both
  sides. Cells are slightly taller than wide — the label needs a band of its
  own, and a taller cell is a bigger thumb target without widening the grid.
  The icon is measured against the cell's *width*, so the space above it
  equals the space at its sides.
- **Pages** extend that without shrinking the buttons: swipe on the phone,
  with dots showing where you are. In the editor, page tabs are also drop
  targets, which is the only way to drag a button onto a page that is not
  currently shown. Slots are one flat list across every page, so a drag
  between pages is an ordinary index move rather than a special case.
- **Every press reports back.** A haptic tick fires immediately, the button
  dims while the command is in flight, then flashes green for success or red
  for failure. Over BLE a press is not instant, and a button that looks
  identical whether it worked or not is worse than no feedback at all.
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

`protocol.dart` (in the shared `hotkeypad_protocol` package, see below) defines
a sealed `HotkeyPadMessage` hierarchy encoded as single-line JSON, one message per
ATT operation:

| Message     | Direction       | Purpose                          |
| ----------- | --------------- | -------------------------------- |
| `ls`        | client -> host  | send the app catalogue           |
| `app`       | host -> client  | one catalogue entry              |
| `end`       | host -> client  | catalogue complete               |
| `open`      | client -> host  | launch an app                    |
| `ack`       | host -> client  | result of the last command       |
| `txt`       | either          | debug console traffic            |
| `lay?`      | client -> host  | send the deck layout             |
| `lay`       | host -> client  | layout header (columns, rows)    |
| `slot`      | host -> client  | contents of one cell             |
| `laye`      | host -> client  | layout complete                  |
| `press`     | client -> host  | the button in slot N was pressed |
| `ico`       | client -> host  | send this app's icon             |
| `ico!`      | host -> client  | there is no icon, stop waiting   |

There is no reassembly: a message must fit the negotiated MTU. The client
requests a 512-byte MTU on Android, and the host refuses to send anything
larger than `getMaximumNotifyLength` reports rather than truncating it. The
catalogue is therefore streamed as one small notification per app, paced at
20ms so the notification queue does not overflow.

Keys are one or two characters, and `HotkeyPadMessage.decode` returns null for
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

`HotkeyPad.iconSize` (128) is shared by both projects. Deck buttons fill their
whole tappable area with the icon, so on a 3x phone screen it is scaled to
roughly 300 physical pixels and 64px was visibly soft. The cost is ~15KB per
icon instead of ~5KB — around 87 frames and under two seconds each at the MTU
an iPhone negotiates, paid once because of the cache. Cache filenames carry
the size (`<hex>@128`), so changing the constant invalidates stored icons
rather than leaving a set at the old resolution.

The layout is streamed the same way as the catalogue — a header, one message
per *occupied* cell, then an end marker — and is only promoted into view on
the end marker, so a partial grid is never drawn. Empty cells are not sent;
the header's dimensions place the rest.

The client caches the layout it was sent (`deck_store.dart`) so the deck draws
immediately on open rather than after the link comes up, and a brief drop does
not blank the screen. It is a cache, never an authority: the host's copy wins
on every connect.

### The app bar follows the device edge

Rotating the phone moves the app bar to whichever edge used to be the top:
left when turned anticlockwise, right when clockwise. It is not a decoration
— reaching for the deck is a one-handed gesture, and a bar that jumps to the
far side of the screen puts the debug button under the hand holding the
phone.

Flutter reports only portrait or landscape, never which way the device was
turned, so `edge_bar.dart` infers it from where the system insets moved.
What that implies depends on which inset it is: on Android the horizontal
inset is the navigation bar, which sits at the bottom when upright, so the
old top is on the **opposite** side; on iOS it is the notch, which sits at
the top, so the bar belongs on the **same** side. A device with neither —
gesture navigation and no cutout — leaves nothing to infer from and defaults
to the left.

Only the client does this. The host is a desktop window and has no
orientation to follow.

### Appearance

System, Light or Dark plus a button-labels switch, chosen on the host and
pushed to the phone with the layout. Turning labels off changes the geometry
as well as hiding text: with no caption to leave room for, cells become
square and the icon fills them edge to edge. It follows the same rule as the grid: the host owns configuration,
the client renders what it is sent. Picking it per-device would mean a
settings screen on the phone, which is the thing this design removed.

The client caches it beside the layout, so a restart draws the right
appearance on the first frame rather than flashing the wrong one.

Host preferences live in `settings.json`, separate from `layout.json`, so
writing one cannot clobber the other.

### Finding the host

The search is driven by the adapter's state, not by asking for permission and
hoping. `authorize()` re-requests through the plugin's Activity even when the
permission is already held, and on a cold start that call can never return —
which showed up as a spinner that never resolved. The deck now listens to
`stateChanged`: `poweredOn` starts the scan, `unauthorized` asks once,
`poweredOff` and `unsupported` say so.

The scan is not filtered on the service UUID, deliberately. A host whose
advertisement puts the UUID in the scan response would be missed entirely,
and checking each result costs nothing.

Every step is behind a timeout armed *before* the first `await`. Android
throttles an app that scans repeatedly, and both `authorize()` and
`startDiscovery()` can then hang indefinitely; a timeout set after them would
never be set at all.

### A button press is an id, not an instruction

The client never says what to do — only which slot was pressed. The host
looks that slot up in its own layout and acts on what it finds. Every kind of
button travels the same path, and a phone cannot ask the Mac to run something
the Mac was not already configured with. That distinction is academic while
buttons only launch apps; it is the whole design once they can hold shell
commands.

**The id must be the host's, not the screen's.** A portrait deck is a
transposed view of the host's grid, which renumbers where every button sits
on screen. Each occupied cell is a `DeckSlot`, pairing the button with the
id it had when the host sent it; `transposed()` carries that id along
verbatim rather than recomputing it, so pressing a button just reports
`slot.id` regardless of how the deck was turned to fit the screen. Without
that indirection, a press in portrait would fire whichever button happens to
sit at that screen position in the host's copy — an error invisible in
landscape, where the two numberings coincide.

### Buttons

Five kinds: an application, a media action, a shell command, a macOS
Shortcut, or a keyboard combination. Any of them can carry an emoji, which
replaces the app icon or the built-in glyph.

Key combinations go through System Events rather than CGEvent key codes:
AppleScript maps a character to the right key for whatever layout is active,
which a hard-coded virtual key code does not. Keys with no character —
Escape, arrows, the function row — are sent by code instead, since there is
nothing to type. Either route needs Accessibility, the same as the media
keys, and the host checks that first rather than letting a button appear to
work.

Shortcuts are *started* rather than awaited. One can legitimately run for
minutes or put up its own interface — Shazam listens to the room — and a deck
button should report that it fired, not spin until the work finishes. Only a
failure to launch comes back as an error. Shell commands are awaited, with a
timeout, because their output is worth reporting and they are usually short.

Items with extra fields — a custom emoji, a command — are stored as JSON in
the layout; simple ones keep their short prefixed form (`app:Safari`), which
stays readable in the file and loadable by an older build.

### What needs Accessibility, and what does not

Three of the five button kinds reach macOS through interfaces that need the
app trusted for Accessibility, and macOS **silently drops** those events
without it — `CGEvent.post` reports success either way. Anything relying on
that is checked first rather than left to fail invisibly:

| Action | Mechanism | Permission |
| ------ | --------- | ---------- |
| Launch an app | `open -a` | none |
| Volume, mute | `osascript`, scriptable | none |
| Play/pause, next, previous | HID system event | **Accessibility** |
| Key combination | System Events keystroke | **Accessibility** |
| Shell command, Shortcut | `sh`, `shortcuts` CLI | none |

Pressing a button that needs the permission puts up the system prompt that
deep-links to the right settings pane. macOS shows that once per app, so
Service details also carries a persistent banner with a Grant button for
afterwards.

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

`hotkeypad_client/pubspec.yaml` holds `path_provider_foundation` at **2.5.1** via
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

`protocol.dart` lives in `packages/hotkeypad_protocol`, a small Dart package
both apps depend on by path. Change a UUID or a message shape once and it
reaches both sides — this used to be a file duplicated verbatim in both
projects, which is also why the package's own tests are the original
`protocol_test.dart` unchanged, just moved.

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

Sony XQ-DC72 (Android 16) as client, macOS as host, end to end:

- the client finds the host and connects with no interaction, then draws the
  layout it is sent — grid, pages, real app icons, emoji overrides
- swiping anywhere in the deck area turns the page, including the wide
  margins in landscape
- rotating transposes the grid (5x3 landscape, 3x5 portrait) and moves the
  app bar to the edge that was the top, in both landscape directions
- pressing a button: Volume up moved the Mac from 44% to 50%; a shell button
  wrote its file; a Shortcut button reported `Started Shazam 捷徑`; an app
  button with a custom emoji still opened Safari
- a key combination reaches the host as the right slot and comes back with
  the Accessibility prompt
- buttons dim while in flight, then flash green or red; a host killed
  mid-session produces the disconnect overlay and the deck reconnects on its
  own when it returns

Covered by tests rather than by hand: the binary icon frame format including
CJK names and truncation, layout serialisation and resizing, transposition
and index mapping, every message shape, the deck cache, and the editor's drag
behaviour.

**Not verified:** the iOS client beyond compiling — in particular the app
bar's edge inference takes a different branch there (notch side rather than
navigation bar side). Actually *sending* a keystroke or a transport media
key also needs Accessibility granted through a macOS dialog, which cannot be
driven from a shell.

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
cd hotkeypad_host   && flutter run -d <device-a>   # tap "Start advertising"
cd hotkeypad_client && flutter run -d <device-b>   # tap "Scan"
```

The host should appear in the client's list with a `HOST` badge. Filter the
list down to just hosts with the chip at the top, then tap the row to connect.

The deck starts empty. Open **Deck settings** (tune icon), tick the apps you
want, drag them into the order you like, then go back and press one. The bug
icon opens the debug console.

### iOS client

`flutter build ios` works. The Runner target is signed with a personal team
(`com.chienhunglin.hotkeypad`), which is what a physical device needs.

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
