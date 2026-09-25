import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/widgets.dart';

export 'src/analog_clock.dart';
export 'src/digital_clock.dart';
export 'src/month_calendar.dart';

/// The contract shared by the host service and the client app.
///
/// Both projects depend on this package by path (`packages/hotkeypad_protocol`)
/// rather than keeping their own copy, so a UUID or message shape changed
/// here reaches both sides at once.
abstract final class HotkeyPad {
  /// Advertised primary service. The client filters discovery on this so a
  /// host is distinguishable from every other BLE device in the room.
  static final UUID serviceUuid = UUID.fromString(
    '6f5d0001-9a4c-4f1e-9b2a-7c3d5e8f1a01',
  );

  /// Host -> client. Notifiable, carries responses and the app catalogue.
  static final UUID notifyCharacteristicUuid = UUID.fromString(
    '6f5d0002-9a4c-4f1e-9b2a-7c3d5e8f1a01',
  );

  /// Client -> host. Writable, carries commands.
  static final UUID writeCharacteristicUuid = UUID.fromString(
    '6f5d0003-9a4c-4f1e-9b2a-7c3d5e8f1a01',
  );

  /// Local name put in the advertisement. Keep it short: the legacy
  /// advertising payload is only 31 bytes, of which the 128-bit service UUID
  /// takes 18 and the flags 3. 'HotkeyPad' fits in what is left; a longer name
  /// spills into the scan response and only passive scanners lose it.
  static const advertisedName = 'HotkeyPad';

  /// Points square for a rendered app icon.
  ///
  /// Deck buttons fill their whole tappable area with the icon, so on a 3x
  /// phone screen this is scaled to roughly 300 physical pixels; 64px and
  /// then 128px were both visibly soft there, a detailed custom picture
  /// especially. The cost is a few times the bytes per icon, paid once
  /// because the client caches them.
  ///
  /// The client's cache keys include this number, so changing it invalidates
  /// stored icons rather than leaving stale ones at the old resolution.
  static const iconSize = 256;

  /// The ice-blue from the app icon's own bolt (`#38BDF8`) — both apps'
  /// `ThemeData.colorSchemeSeed`, so the generated app bar/surface colors
  /// actually match the icon sitting next to them, and the one color an
  /// emoji's host-rendered PNG (see `GlyphIconStore`) needs baked in for
  /// its border: the host has no notion of which client theme (light or
  /// dark) will display a given PNG, but this raw seed is the same
  /// regardless, unlike the derived `colorScheme.primary` either theme
  /// would produce. Single source of truth so both apps' `main.dart` and
  /// the glyph renderer can never drift apart on the same brand color.
  static const themeSeedColor = Color(0xFF38BDF8);
}

/// One message on the link.
///
/// Every message is a single JSON object on a single ATT operation — there is
/// no reassembly, so a message must fit the negotiated MTU. Keys are one or
/// two characters for that reason.
sealed class HotkeyPadMessage {
  const HotkeyPadMessage();

  Map<String, Object?> toJson();

  Uint8List encode() => Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  /// Returns null for anything that is not a message this build understands,
  /// so an older peer cannot crash a newer one.
  static HotkeyPadMessage? decode(List<int> bytes) {
    try {
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map<String, Object?>) return null;
      return switch (json['t']) {
        'ls' => const ListApps(),
        'hi' => Hello(
          name: json['n'] as String? ?? '',
          clientId: json['c'] as String? ?? '',
        ),
        'pin?' => const RequestPin(),
        'pin' => SubmitPin(pin: json['v'] as String? ?? ''),
        'pin!' => PinResult(ok: json['ok'] as bool? ?? false),
        'app' => AppEntry(
          name: json['n'] as String,
          category: json['c'] as String?,
        ),
        'end' => ListEnd(count: json['c'] as int? ?? 0),
        'press' => PressSlot(id: json['i'] as int),
        'thm' => SetAppearance(
          theme: DeckTheme.fromWire(json['v'] as String?),
          // Absent on an older host, which always drew labels.
          showLabels: json['lbl'] as bool? ?? true,
          // All three absent on a host built before backgrounds existed, or
          // simply means "no custom background" on a current one — either
          // way the client falls back to its own theme-derived background.
          backgroundImageId: json['bg'] as String?,
          backgroundOpacity: (json['bop'] as num?)?.toDouble() ?? 1.0,
          backgroundFit: BackgroundFit.fromWire(json['bft'] as String?),
        ),
        'lay?' => const RequestLayout(),
        'lay' => LayoutStart(
          columns: json['c'] as int? ?? DeckLayout.defaultColumns,
          rows: json['r'] as int? ?? DeckLayout.defaultRows,
          pages: json['p'] as int? ?? 1,
        ),
        'slot' => LayoutSlot(
          index: json['i'] as int,
          value: json['v'] as String,
        ),
        'laye' => const LayoutEnd(),
        'ico' => RequestIcon(name: json['n'] as String),
        'ico!' => IconUnavailable(name: json['n'] as String),
        'ack' => Ack(
          ok: json['ok'] as bool? ?? false,
          message: json['m'] as String? ?? '',
        ),
        'txt' => DebugText(text: json['m'] as String? ?? ''),
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }
}

/// Client -> host: send me the app catalogue.
final class ListApps extends HotkeyPadMessage {
  const ListApps();

  @override
  Map<String, Object?> toJson() => {'t': 'ls'};
}

/// Client -> host: sent once, right after connecting, so the host can show
/// a friendlier name than a bare central id when more than one device is
/// connected at once — see [PressSlot] and the host's device lock.
final class Hello extends HotkeyPadMessage {
  const Hello({required this.name, required this.clientId});

  final String name;

  /// Generated once per install and persisted (see `hotkeypad_client`'s
  /// `ClientIdentity`), unrelated to any transport-level id — a BLE
  /// central's uuid or a WiFi socket's address:port are both scoped to
  /// one connection, but the PIN-pairing flow (`RequestPin`/`SubmitPin`/
  /// `PinResult`) needs an identity that survives a reconnect on either
  /// transport, which is what this is for.
  final String clientId;

  @override
  Map<String, Object?> toJson() => {'t': 'hi', 'n': name, 'c': clientId};
}

/// Host -> client: this is the first time the host has seen this
/// [Hello.clientId], so it needs a PIN — displayed on the host's own
/// screen for the user to read off and type into the client — before
/// anything else from this connection is acted on. Sent on either
/// transport: a BLE central being close enough to discover the host is
/// no more trusted on its own than a WiFi client being on the same
/// network is.
final class RequestPin extends HotkeyPadMessage {
  const RequestPin();

  @override
  Map<String, Object?> toJson() => {'t': 'pin?'};
}

/// Client -> host: the user's answer to [RequestPin].
final class SubmitPin extends HotkeyPadMessage {
  const SubmitPin({required this.pin});

  final String pin;

  @override
  Map<String, Object?> toJson() => {'t': 'pin', 'v': pin};
}

/// Host -> client: whether [SubmitPin] matched. `true` means this
/// [Hello.clientId] is now remembered and will not be asked again; `false`
/// means the host is done with this connection — trying again means a
/// fresh connection and a fresh PIN, not another guess on this one. Over
/// WiFi that is an explicit closed socket; a BLE peripheral cannot always
/// force a central to disconnect, so there the host instead simply stops
/// responding to anything else this central sends, and it is the
/// well-behaved client (see `hotkeypad_client`'s `HotkeyPadSession`) that
/// disconnects itself on a rejected PIN to get the same fresh-connection
/// outcome.
final class PinResult extends HotkeyPadMessage {
  const PinResult({required this.ok});

  final bool ok;

  @override
  Map<String, Object?> toJson() => {'t': 'pin!', 'ok': ok};
}

/// Host -> client: one entry of the catalogue.
final class AppEntry extends HotkeyPadMessage {
  const AppEntry({required this.name, this.category});

  final String name;
  final String? category;

  @override
  Map<String, Object?> toJson() => {
    't': 'app',
    'n': name,
    if (category != null) 'c': category,
  };
}

/// Host -> client: the catalogue is complete.
final class ListEnd extends HotkeyPadMessage {
  const ListEnd({required this.count});

  final int count;

  @override
  Map<String, Object?> toJson() => {'t': 'end', 'c': count};
}

/// One button on the deck.
///
/// Stored as a string in the layout. Simple items keep their original
/// prefixed form (`app:Safari`, `act:mute`) so a layout written by an older
/// build still loads; anything carrying extra fields — a custom emoji or
/// image, a command — is stored as JSON, which the parser recognises by its
/// leading brace.
sealed class DeckItem {
  const DeckItem();

  String get stored;
  String get label;

  /// Shown instead of an app icon or a built-in glyph when set.
  ///
  /// Mutually exclusive with [customIconId] by construction of the picker
  /// UI that sets them — a button is either given a glyph or a picture, not
  /// both. If somehow both are set, rendering prefers this one, matching
  /// the priority that already existed before [customIconId] did.
  String? get emoji;

  /// An id naming an image the host rendered from a file the user picked,
  /// fetched and cached the same way an app's own icon is — see
  /// [RequestIcon] and [IconFrame]. Shown instead of an app icon or built-in
  /// glyph when set, unless [emoji] is also set.
  String? get customIconId;

  /// Returns null for a stored value this build does not understand, so an
  /// item written by a newer peer is skipped rather than shown as a button
  /// that does nothing.
  static DeckItem? parse(String stored) {
    if (stored.startsWith('{')) return _fromJson(stored);
    if (stored.startsWith('act:')) {
      final action = DeckAction.fromWire(stored.substring(4));
      return action == null ? null : ActionItem(action);
    }
    final name = stored.startsWith('app:') ? stored.substring(4) : stored;
    return name.isEmpty ? null : AppItem(name);
  }

  static DeckItem? _fromJson(String stored) {
    try {
      final json = jsonDecode(stored);
      if (json is! Map) return null;
      final emoji = json['e'] as String?;
      final customIconId = json['ci'] as String?;
      return switch (json['t']) {
        'app' => AppItem(
          json['n'] as String,
          emoji: emoji,
          customIconId: customIconId,
        ),
        'act' => switch (DeckAction.fromWire(json['a'] as String? ?? '')) {
          final action? => ActionItem(
            action,
            emoji: emoji,
            customIconId: customIconId,
          ),
          null => null,
        },
        'sh' => ShellItem(
          command: json['c'] as String,
          label: json['l'] as String,
          shell: ShellKind.fromWire(json['sk'] as String?),
          emoji: emoji,
          customIconId: customIconId,
        ),
        'key' => KeyComboItem(
          modifiers: [
            for (final wire in (json['m'] as List? ?? const []))
              ?KeyModifier.fromWire('$wire'),
          ],
          key: json['k'] as String?,
          special: SpecialKey.fromWire(json['s'] as String?),
          label: json['l'] as String?,
          emoji: emoji,
          customIconId: customIconId,
        ),
        'sc' => ShortcutItem(
          name: json['n'] as String,
          label: json['l'] as String?,
          emoji: emoji,
          customIconId: customIconId,
        ),
        'url' => OpenUrlItem(
          url: json['u'] as String,
          label: json['l'] as String?,
          emoji: emoji,
          customIconId: customIconId,
        ),
        'snd' => PlaySoundItem(
          soundId: json['s'] as String,
          label: json['l'] as String? ?? '',
          target: SoundTarget.fromWire(json['tg'] as String?),
          emoji: emoji,
          customIconId: customIconId,
        ),
        'combo' => ComboItem.fromSteps(
          json['steps'] as List? ?? const [],
          label: json['l'] as String? ?? '',
          emoji: emoji,
          customIconId: customIconId,
        ),
        'widget' => switch (DeckWidgetKind.fromWire(json['k'] as String?)) {
          final kind? => WidgetItem(
            kind: kind,
            rowSpan: (json['rs'] as num?)?.toInt() ?? 1,
            columnSpan: (json['cs'] as num?)?.toInt() ?? 1,
          ),
          null => null,
        },
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) => other is DeckItem && other.stored == stored;

  @override
  int get hashCode => stored.hashCode;
}

final class AppItem extends DeckItem {
  const AppItem(this.name, {this.emoji, this.customIconId});

  final String name;

  @override
  final String? emoji;

  @override
  final String? customIconId;

  @override
  String get stored => emoji == null && customIconId == null
      ? 'app:$name'
      : jsonEncode({
          't': 'app',
          'n': name,
          if (emoji != null) 'e': emoji,
          if (customIconId != null) 'ci': customIconId,
        });

  @override
  String get label => name;
}

final class ActionItem extends DeckItem {
  const ActionItem(this.action, {this.emoji, this.customIconId});

  final DeckAction action;

  @override
  final String? emoji;

  @override
  final String? customIconId;

  @override
  String get stored => emoji == null && customIconId == null
      ? 'act:${action.wire}'
      : jsonEncode({
          't': 'act',
          'a': action.wire,
          if (emoji != null) 'e': emoji,
          if (customIconId != null) 'ci': customIconId,
        });

  @override
  String get label => action.label;
}

/// Runs a shell command on the host.
///
/// The command lives only in the host's layout. A client presses a slot by
/// id and the host looks up what that slot holds, so nothing a client
/// sends can become a command — see [PressSlot].
final class ShellItem extends DeckItem {
  const ShellItem({
    required this.command,
    required this.label,
    this.shell = ShellKind.sh,
    this.emoji,
    this.customIconId,
  });

  final String command;

  /// Which interpreter runs [command]. Defaults to `sh` so a layout written
  /// before this field existed still runs the way it always did.
  final ShellKind shell;

  @override
  final String label;

  @override
  final String? emoji;

  @override
  final String? customIconId;

  @override
  String get stored => jsonEncode({
    't': 'sh',
    'c': command,
    'l': label,
    if (shell != ShellKind.sh) 'sk': shell.wire,
    if (emoji != null) 'e': emoji,
    if (customIconId != null) 'ci': customIconId,
  });
}

/// The interpreter a [ShellItem] runs its command through.
enum ShellKind {
  sh('sh', 'sh'),
  bash('bash', 'bash'),
  zsh('zsh', 'zsh'),
  fish('fish', 'fish');

  const ShellKind(this.wire, this.label);

  final String wire;

  /// Shown in the shell picker.
  final String label;

  /// Falls back to [sh] for a missing or unrecognised wire value, rather
  /// than dropping the button, so a layout from a newer build that picked a
  /// shell this build does not know still runs the command somehow.
  static ShellKind fromWire(String? wire) {
    for (final kind in values) {
      if (kind.wire == wire) return kind;
    }
    return ShellKind.sh;
  }
}

/// Where a [PlaySoundItem] plays.
enum SoundTarget {
  /// The phone's own speaker; the press never reaches the host.
  client('c'),

  /// The host's speakers, like any other host-side button.
  host('h');

  const SoundTarget(this.wire);

  final String wire;

  /// Falls back to [client] for a missing or unrecognised value — the only
  /// target there was before this existed, so an older layout keeps
  /// playing where it always did.
  static SoundTarget fromWire(String? wire) {
    for (final target in values) {
      if (target.wire == wire) return target;
    }
    return SoundTarget.client;
  }
}

/// A modifier key in a combination.
enum KeyModifier {
  command('cmd', '⌘', 'command down'),
  shift('shift', '⇧', 'shift down'),
  option('opt', '⌥', 'option down'),
  control('ctrl', '⌃', 'control down');

  const KeyModifier(this.wire, this.symbol, this.appleScript);

  final String wire;
  final String symbol;

  /// How System Events names it.
  final String appleScript;

  static KeyModifier? fromWire(String wire) {
    for (final modifier in values) {
      if (modifier.wire == wire) return modifier;
    }
    return null;
  }
}

/// Keys that have no character to type and must be sent by virtual key code.
enum SpecialKey {
  escape('escape', 'Escape', 53),
  ret('return', 'Return', 36),
  tab('tab', 'Tab', 48),
  space('space', 'Space', 49),
  delete('delete', 'Delete', 51),
  left('left', 'Left', 123),
  right('right', 'Right', 124),
  down('down', 'Down', 125),
  up('up', 'Up', 126),
  f1('f1', 'F1', 122),
  f2('f2', 'F2', 120),
  f3('f3', 'F3', 99),
  f4('f4', 'F4', 118),
  f5('f5', 'F5', 96),
  f6('f6', 'F6', 97),
  f7('f7', 'F7', 98),
  f8('f8', 'F8', 100),
  f9('f9', 'F9', 101),
  f10('f10', 'F10', 109),
  f11('f11', 'F11', 103),
  f12('f12', 'F12', 111);

  const SpecialKey(this.wire, this.label, this.code);

  final String wire;
  final String label;

  /// macOS virtual key code, for `key code` in System Events.
  final int code;

  static SpecialKey? fromWire(String? wire) {
    for (final key in values) {
      if (key.wire == wire) return key;
    }
    return null;
  }
}

/// Sends a keyboard combination to whatever is frontmost on the host.
final class KeyComboItem extends DeckItem {
  const KeyComboItem({
    required this.modifiers,
    required this.key,
    required this.special,
    String? label,
    this.emoji,
    this.customIconId,
  }) : _label = label;

  /// Held while the key is pressed, in a stable order for display.
  final List<KeyModifier> modifiers;

  /// The character to type, when [special] is null.
  final String? key;

  /// A key with no character, sent by code instead.
  final SpecialKey? special;

  final String? _label;

  @override
  final String? emoji;

  @override
  final String? customIconId;

  /// What the combination reads as: ⌘⇧4, ⌥Space.
  String get combination {
    final parts = [
      for (final modifier in KeyModifier.values)
        if (modifiers.contains(modifier)) modifier.symbol,
      special?.label ?? (key ?? '').toUpperCase(),
    ];
    return parts.join();
  }

  @override
  String get label => _label?.isNotEmpty == true ? _label! : combination;

  @override
  String get stored => jsonEncode({
    't': 'key',
    'm': [for (final modifier in modifiers) modifier.wire],
    if (key != null) 'k': key,
    if (special != null) 's': special!.wire,
    if (_label != null) 'l': _label,
    if (emoji != null) 'e': emoji,
    if (customIconId != null) 'ci': customIconId,
  });
}

/// Runs a macOS Shortcut by name.
final class ShortcutItem extends DeckItem {
  const ShortcutItem({
    required this.name,
    String? label,
    this.emoji,
    this.customIconId,
  }) : _label = label;

  final String name;
  final String? _label;

  @override
  String get label => _label?.isNotEmpty == true ? _label! : name;

  @override
  final String? emoji;

  @override
  final String? customIconId;

  @override
  String get stored => jsonEncode({
    't': 'sc',
    'n': name,
    if (_label != null) 'l': _label,
    if (emoji != null) 'e': emoji,
    if (customIconId != null) 'ci': customIconId,
  });
}

/// Opens a URL in Chrome on the host, focusing a tab already showing it
/// instead of opening a duplicate — see [CommandRunner.openUrl] for how.
final class OpenUrlItem extends DeckItem {
  const OpenUrlItem({
    required this.url,
    String? label,
    this.emoji,
    this.customIconId,
  }) : _label = label;

  final String url;
  final String? _label;

  @override
  String get label => _label?.isNotEmpty == true ? _label! : url;

  @override
  final String? emoji;

  @override
  final String? customIconId;

  @override
  String get stored => jsonEncode({
    't': 'url',
    'u': url,
    if (_label != null) 'l': _label,
    if (emoji != null) 'e': emoji,
    if (customIconId != null) 'ci': customIconId,
  });
}

/// Plays a sound, on the phone or on the host depending on [target].
///
/// [soundId] names an audio file the host stored when the button was made,
/// transferred and cached exactly like an icon (see [RequestIcon] and
/// [IconFrame]; an id is an opaque string to that transfer). It keeps the
/// file's extension (`snd_123.mp3`), which the client's player needs to
/// know the format.
///
/// With [SoundTarget.client], pressing one never reaches the host: the
/// client plays its cached copy itself. With [SoundTarget.host] it is an
/// ordinary press, and the host plays its own copy.
final class PlaySoundItem extends DeckItem {
  const PlaySoundItem({
    required this.soundId,
    required this.label,
    this.target = SoundTarget.client,
    this.emoji,
    this.customIconId,
  });

  final String soundId;
  final SoundTarget target;

  @override
  final String label;

  @override
  final String? emoji;

  @override
  final String? customIconId;

  @override
  String get stored => jsonEncode({
    't': 'snd',
    's': soundId,
    'l': label,
    // Omitted for the default, so a phone-side sound stores exactly as it
    // did before hosts could play them too.
    if (target != SoundTarget.client) 'tg': target.wire,
    if (emoji != null) 'e': emoji,
    if (customIconId != null) 'ci': customIconId,
  });
}

/// One action in a [ComboItem], run in sequence with the others.
final class ComboStep {
  const ComboStep({required this.action, required this.delayMs});

  /// What this step does — never itself a [ComboItem]; combos cannot nest.
  final DeckItem action;

  /// Waited before running [action]. The first step's is typically 0; it is
  /// "before", not "after", so there is nothing to wait for once the last
  /// step has run.
  final int delayMs;

  Map<String, Object?> toJson() => {'v': action.stored, 'd': delayMs};

  /// Returns null for anything that does not decode to a plain action, so a
  /// bad or nested step is dropped rather than taking the whole combo with
  /// it — see [ComboItem.fromSteps].
  static ComboStep? fromJson(Object? json) {
    if (json is! Map) return null;
    final stored = json['v'];
    if (stored is! String) return null;
    final action = DeckItem.parse(stored);
    if (action == null || action is ComboItem) return null;
    final delayMs = json['d'];
    return ComboStep(action: action, delayMs: delayMs is int ? delayMs : 0);
  }
}

/// Runs a fixed sequence of other buttons' actions, waiting between them.
///
/// Steps are copies taken when the combo was composed, not live references
/// to other slots — editing or clearing whatever slot a step was originally
/// picked from does not change this combo, and there is no reference to go
/// stale or cycle back on itself.
final class ComboItem extends DeckItem {
  const ComboItem({
    required this.steps,
    required this.label,
    this.emoji,
    this.customIconId,
  });

  /// Never empty — see [fromSteps].
  final List<ComboStep> steps;

  @override
  final String label;

  @override
  final String? emoji;

  @override
  final String? customIconId;

  /// Drops any step that failed to parse or was itself a combo; null if
  /// that leaves nothing to run.
  static ComboItem? fromSteps(
    List<Object?> rawSteps, {
    required String label,
    String? emoji,
    String? customIconId,
  }) {
    final steps = [for (final raw in rawSteps) ?ComboStep.fromJson(raw)];
    if (steps.isEmpty) return null;
    return ComboItem(
      steps: steps,
      label: label,
      emoji: emoji,
      customIconId: customIconId,
    );
  }

  @override
  String get stored => jsonEncode({
    't': 'combo',
    'l': label,
    'steps': [for (final step in steps) step.toJson()],
    if (emoji != null) 'e': emoji,
    if (customIconId != null) 'ci': customIconId,
  });
}

/// A live widget a [WidgetItem] can render, rather than something a press
/// runs.
enum DeckWidgetKind {
  clock('clock', 'Clock'),
  digitalClock('digital_clock', 'Digital clock'),
  calendar('calendar', 'Calendar');

  const DeckWidgetKind(this.wire, this.label);

  final String wire;
  final String label;

  static DeckWidgetKind? fromWire(String? wire) {
    for (final kind in values) {
      if (kind.wire == wire) return kind;
    }
    return null;
  }
}

/// A live widget (a clock or a calendar) placed like any other button, but
/// anchored at its own top-left slot and spanning [rowSpan] x [columnSpan]
/// cells from there — see [DeckLayout.footprintFor] and [DeckGridView],
/// which is what actually renders a span rather than a single cell.
///
/// Every other cell inside that span is kept empty in [DeckLayout.slots]:
/// there is no separate wire representation for "covered by a widget
/// elsewhere", it is derived fresh from wherever a [WidgetItem] currently
/// sits — see [DeckLayout.widgetCoveredIndexes].
final class WidgetItem extends DeckItem {
  const WidgetItem({
    required this.kind,
    required this.rowSpan,
    required this.columnSpan,
  });

  final DeckWidgetKind kind;
  final int rowSpan;
  final int columnSpan;

  @override
  String get label => kind.label;

  /// A widget renders itself; there is no glyph to override.
  @override
  String? get emoji => null;

  @override
  String? get customIconId => null;

  @override
  String get stored => jsonEncode({
    't': 'widget',
    'k': kind.wire,
    'rs': rowSpan,
    'cs': columnSpan,
  });
}

/// One occupied cell of a [DeckLayout]: a button's content, tagged with the
/// id it is pressed by.
///
/// [id] starts out equal to the cell's own position in the host's layout and
/// travels with the button verbatim through [DeckLayout.transposed] rather
/// than being recomputed there — so a press never needs to invert whatever
/// transform produced the view it was drawn in. It just reports the id
/// already sitting on the button that was tapped.
final class DeckSlot {
  const DeckSlot({required this.id, required this.value});

  /// The host's own index for this button. Opaque everywhere else: never
  /// interpreted, only carried along and sent back with [PressSlot].
  final int id;

  /// A [DeckItem.stored] string.
  final String value;

  @override
  bool operator ==(Object other) =>
      other is DeckSlot && other.id == id && other.value == value;

  @override
  int get hashCode => Object.hash(id, value);

  @override
  String toString() => 'DeckSlot(id: $id, value: $value)';
}

/// A [WidgetItem]'s footprint once actually anchored somewhere — see
/// [DeckLayout.footprintFor]/[DeckLayout.footprintAt].
class DeckWidgetFootprint {
  const DeckWidgetFootprint({
    required this.rows,
    required this.columns,
    required this.indexes,
  });

  /// The span actually used, after clamping to the page's own bounds —
  /// may be smaller than what was asked for; never larger.
  final int rows;
  final int columns;

  /// Every [DeckLayout.slots] index the footprint covers, the anchor first,
  /// then the rest in reading order.
  final List<int> indexes;
}

/// The grid the client draws and the host edits.
///
/// The host owns this: a phone screen is a poor place to arrange a grid, and
/// the host already knows which apps exist. The client receives it and
/// renders it.
class DeckLayout {
  const DeckLayout({
    required this.columns,
    required this.rows,
    required this.pages,
    required this.slots,
  });

  /// An empty grid at the default size.
  factory DeckLayout.empty({
    int columns = defaultColumns,
    int rows = defaultRows,
    int pages = 1,
  }) => DeckLayout(
    columns: columns,
    rows: rows,
    pages: pages,
    slots: List<DeckSlot?>.filled(columns * rows * pages, null),
  );

  static const defaultColumns = 5;
  static const defaultRows = 3;
  static const maxPages = 8;

  final int columns;
  final int rows;
  final int pages;

  /// One entry per cell across every page, in reading order, null where the
  /// cell is empty. Flat rather than nested so a position identifies a cell
  /// globally and a drag between pages needs no special case.
  final List<DeckSlot?> slots;

  /// Cells on one page.
  int get pageCapacity => columns * rows;

  /// Cells across every page.
  int get capacity => pageCapacity * pages;

  int indexOf({required int page, required int cell}) =>
      page * pageCapacity + cell;

  /// The slots belonging to [page], in reading order.
  List<DeckSlot?> page(int index) =>
      slots.sublist(index * pageCapacity, (index + 1) * pageCapacity);

  DeckLayout resized({int? columns, int? rows, int? pages}) {
    final newColumns = columns ?? this.columns;
    final newRows = rows ?? this.rows;
    final newPages = pages ?? this.pages;
    final resized = List<DeckSlot?>.filled(
      newColumns * newRows * newPages,
      null,
    );
    // Keep cells where they are on screen rather than where they are in the
    // list: a row of buttons should not shuffle sideways when a column is
    // added, and a page should not absorb the next one's buttons. The id is
    // re-stamped to the new position, same as every other host-side edit.
    for (var page = 0; page < newPages && page < this.pages; page++) {
      for (var row = 0; row < newRows && row < this.rows; row++) {
        for (
          var column = 0;
          column < newColumns && column < this.columns;
          column++
        ) {
          final newIndex =
              page * newColumns * newRows + row * newColumns + column;
          final old =
              slots[page * this.columns * this.rows +
                  row * this.columns +
                  column];
          resized[newIndex] = old == null
              ? null
              : DeckSlot(id: newIndex, value: old.value);
        }
      }
    }
    return DeckLayout(
      columns: newColumns,
      rows: newRows,
      pages: newPages,
      slots: resized,
    );
  }

  /// Swaps rows and columns, so a 5-wide grid becomes 5-tall.
  ///
  /// A transpose rather than a rotation: the first row becomes the first
  /// column, which is what "the wide one turned upright" looks like and
  /// keeps every button's neighbours the same. A rotation would also move
  /// buttons to the opposite edge, which is harder to predict.
  ///
  /// Cells are moved whole, [DeckSlot.id] included — a turned view renumbers
  /// where a button sits in [slots], never what it reports when pressed.
  DeckLayout transposed() {
    if (columns == rows) return this;
    final swapped = List<DeckSlot?>.filled(slots.length, null);
    for (var page = 0; page < pages; page++) {
      final offset = page * pageCapacity;
      for (var row = 0; row < rows; row++) {
        for (var column = 0; column < columns; column++) {
          swapped[offset + column * rows + row] = _transposedSlot(
            slots[offset + row * columns + column],
          );
        }
      }
    }
    return DeckLayout(
      columns: rows,
      rows: columns,
      pages: pages,
      slots: swapped,
    );
  }

  /// [transposed]'s per-cell copy, widget-aware: a [WidgetItem]'s own
  /// rowSpan/columnSpan describe its shape in the *un*-turned grid, so a
  /// turn that swaps every cell's position has to swap those two numbers
  /// right along with it — otherwise the footprint this widget claims
  /// would silently stop matching the shape it was actually placed in.
  static DeckSlot? _transposedSlot(DeckSlot? slot) {
    if (slot == null) return null;
    final item = DeckItem.parse(slot.value);
    if (item is! WidgetItem) return slot;
    return DeckSlot(
      id: slot.id,
      value: WidgetItem(
        kind: item.kind,
        rowSpan: item.columnSpan,
        columnSpan: item.rowSpan,
      ).stored,
    );
  }

  /// The layout oriented to match the screen: wider than tall in landscape,
  /// taller than wide in portrait. The host edits one shape; the client
  /// turns it to fit whatever it is running on.
  DeckLayout orientedFor({required bool portrait}) {
    if (columns == rows) return this;
    final isTaller = rows > columns;
    return isTaller == portrait ? this : transposed();
  }

  DeckLayout withSlot(int index, String? value) {
    final copy = List<DeckSlot?>.of(slots);
    copy[index] = value == null ? null : DeckSlot(id: index, value: value);
    return DeckLayout(columns: columns, rows: rows, pages: pages, slots: copy);
  }

  /// The cells a [WidgetItem] anchored at [index] with [rowSpan] x
  /// [columnSpan] would occupy on that same page — [index] itself first,
  /// then every other covered cell in reading order. Clamped to whatever
  /// room is actually left on the page from that position, rather than
  /// running past its right or bottom edge: a widget can be placed (or can
  /// simply be left in place through a later shrink) where its full span
  /// would not fit, in which case it just claims less than
  /// `rowSpan x columnSpan`.
  DeckWidgetFootprint footprintFor(
    int index, {
    required int rowSpan,
    required int columnSpan,
  }) {
    final page = index ~/ pageCapacity;
    final cell = index % pageCapacity;
    final anchorRow = cell ~/ columns;
    final anchorColumn = cell % columns;
    final clampedRows = math.min(rowSpan, rows - anchorRow);
    final clampedColumns = math.min(columnSpan, columns - anchorColumn);
    return DeckWidgetFootprint(
      rows: clampedRows,
      columns: clampedColumns,
      indexes: [
        for (var dr = 0; dr < clampedRows; dr++)
          for (var dc = 0; dc < clampedColumns; dc++)
            page * pageCapacity +
                (anchorRow + dr) * columns +
                (anchorColumn + dc),
      ],
    );
  }

  /// [index]'s own footprint as it is actually stored right now: 1x1 for an
  /// ordinary button or an empty cell, or a [WidgetItem]'s own span.
  DeckWidgetFootprint footprintAt(int index) {
    final slot = slots[index];
    final item = slot == null ? null : DeckItem.parse(slot.value);
    if (item is! WidgetItem) {
      return DeckWidgetFootprint(rows: 1, columns: 1, indexes: [index]);
    }
    return footprintFor(
      index,
      rowSpan: item.rowSpan,
      columnSpan: item.columnSpan,
    );
  }

  /// Every cell forced empty because some other cell on its page anchors a
  /// [WidgetItem] whose footprint reaches it — occupied on screen, but not
  /// by a value of its own, so a plain pick or drag must treat it as
  /// unavailable rather than as an ordinary empty slot.
  Set<int> get widgetCoveredIndexes {
    final covered = <int>{};
    for (var index = 0; index < slots.length; index++) {
      if (slots[index] == null) continue;
      covered.addAll(footprintAt(index).indexes.where((i) => i != index));
    }
    return covered;
  }

  /// Whether placing a widget with [rowSpan] x [columnSpan] anchored at
  /// [index] would reach into a cell some other widget already covers.
  ///
  /// Nulling such a cell (which is what [withWidget] does to the rest of
  /// its own footprint) would silently shrink that other widget's shape
  /// rather than actually freeing anything, so a placement reaching into
  /// one is refused outright — this is checked before the footprint is
  /// ever cleared, not cleaned up after. [index]'s own current footprint
  /// (if it already anchors a widget) does not count as "another widget":
  /// resizing a widget in place is not blocked by itself.
  bool widgetPlacementBlocked(
    int index, {
    required int rowSpan,
    required int columnSpan,
  }) {
    final ownFootprint = footprintAt(index).indexes.toSet();
    final blockedByOthers = widgetCoveredIndexes.difference(ownFootprint);
    final candidate = footprintFor(
      index,
      rowSpan: rowSpan,
      columnSpan: columnSpan,
    );
    return candidate.indexes.any(
      (i) => i != index && blockedByOthers.contains(i),
    );
  }

  /// Places [item] anchored at [index], clearing whatever the rest of its
  /// footprint already held. Confirming that loss away first, when there
  /// is one, is the caller's job — see the host's own `confirmResizeDrop`
  /// for the equivalent already used before a grid shrink.
  DeckLayout withWidget(int index, WidgetItem item) {
    final footprint = footprintFor(
      index,
      rowSpan: item.rowSpan,
      columnSpan: item.columnSpan,
    );
    final copy = List<DeckSlot?>.of(slots);
    for (final covered in footprint.indexes) {
      if (covered != index) copy[covered] = null;
    }
    copy[index] = DeckSlot(id: index, value: item.stored);
    return DeckLayout(columns: columns, rows: rows, pages: pages, slots: copy);
  }

  /// Moves the contents of [from] to [to], swapping if [to] is occupied.
  ///
  /// Whichever button ends up at a position takes that position's id — a
  /// move always ships as a full layout resend, so there is no client with a
  /// stale view of this cell to confuse.
  DeckLayout moved(int from, int to) {
    if (from == to) return this;
    final copy = List<DeckSlot?>.of(slots);
    final movingValue = copy[from]?.value;
    final displacedValue = copy[to]?.value;
    copy[from] = displacedValue == null
        ? null
        : DeckSlot(id: from, value: displacedValue);
    copy[to] = movingValue == null
        ? null
        : DeckSlot(id: to, value: movingValue);
    return DeckLayout(columns: columns, rows: rows, pages: pages, slots: copy);
  }

  Map<String, Object?> toJson() => {
    'columns': columns,
    'rows': rows,
    'pages': pages,
    // The id is not persisted: this is always the host's own canonical
    // (untransposed) copy, where it is trivially the slot's own position —
    // fromJson recreates it from that position on the way back in.
    'slots': [for (final slot in slots) slot?.value],
  };

  static DeckLayout? fromJson(Object? json) {
    if (json is! Map) return null;
    final columns = json['columns'];
    final rows = json['rows'];
    // Layouts written before pages existed held a single page.
    final pages = json['pages'] ?? 1;
    final slots = json['slots'];
    if (columns is! int || rows is! int || pages is! int || slots is! List) {
      return null;
    }
    if (columns <= 0 || rows <= 0 || columns > 12 || rows > 12) return null;
    if (pages <= 0 || pages > maxPages) return null;
    if (slots.length != columns * rows * pages) return null;
    return DeckLayout(
      columns: columns,
      rows: rows,
      pages: pages,
      slots: [
        for (var i = 0; i < slots.length; i++)
          if (slots[i] case final String value)
            DeckSlot(id: i, value: value)
          else
            null,
      ],
    );
  }
}

/// The natural size of a [columns] x [rows] grid of cells [spacing] apart,
/// each [cellRatio] wide-to-tall, that fits within [maxWidth] x
/// [maxHeight] — shared by the host's editor preview and the client's own
/// deck so a button looks the same size relative to its neighbours on
/// both, rather than each computing its own slightly different answer to
/// the same question. See also [DeckGridView], which renders a grid at
/// this size.
class DeckGridMetrics {
  const DeckGridMetrics({
    required this.cellWidth,
    required this.cellHeight,
    required this.gridWidth,
    required this.gridHeight,
  });

  final double cellWidth;
  final double cellHeight;
  final double gridWidth;
  final double gridHeight;
}

/// The gap between cells, shared by both apps' decks — see
/// [DeckGridMetrics]'s own doc comment for why matching this exactly is
/// the point.
const kDeckGridSpacing = 2.0;

DeckGridMetrics deckGridMetrics({
  required double maxWidth,
  required double maxHeight,
  required int columns,
  required int rows,
  required double cellRatio,
  double spacing = kDeckGridSpacing,
}) {
  final freeWidth = maxWidth - spacing * (columns - 1);
  final freeHeight = maxHeight - spacing * (rows - 1);
  // Whichever axis runs out first decides the cell width; the other axis
  // keeps its spare room as even margin on both sides.
  final cellWidth = math.min(
    freeWidth / columns,
    freeHeight / rows * cellRatio,
  );
  final cellHeight = cellWidth / cellRatio;
  return DeckGridMetrics(
    cellWidth: cellWidth,
    cellHeight: cellHeight,
    gridWidth: cellWidth * columns + spacing * (columns - 1),
    gridHeight: cellHeight * rows + spacing * (rows - 1),
  );
}

/// The rendered shell of one page of [layout]: a fixed-size, non-scrolling
/// grid sized by [metrics] and centered in the space around it — identical
/// between the host's editable grid and the client's pressable one, since
/// what actually differs between them (drag-to-reorder vs tap-to-press) is
/// entirely inside [cellBuilder], never in the grid's own geometry.
///
/// [metrics] is a parameter rather than computed here so a caller that also
/// has to reserve space for something beside the grid can solve for that
/// layout first and hand back the metrics it settled on, instead of this
/// widget silently recomputing a second, inconsistent answer from raw
/// constraints.
///
/// Built on a [Stack] of explicitly [Positioned] cells rather than a
/// [GridView]: a [WidgetItem] spans more than one cell, which a
/// [SliverGridDelegateWithFixedCrossAxisCount] has no way to express — every
/// cell's own on-screen rectangle is placed by hand instead, from
/// [DeckGridMetrics]'s per-cell size and [DeckLayout.footprintAt]'s span,
/// which collapses to exactly what the old [GridView] drew whenever nothing
/// spans more than 1x1.
class DeckGridView extends StatelessWidget {
  const DeckGridView({
    super.key,
    required this.layout,
    required this.page,
    required this.metrics,
    required this.cellRatio,
    required this.cellBuilder,
    this.spacing = kDeckGridSpacing,
  });

  final DeckLayout layout;

  /// Which page of [layout] to show — cell `n` on this page is
  /// `layout.indexOf(page: page, cell: n)` into [DeckLayout.slots], the
  /// index [cellBuilder] is actually called with.
  final int page;

  final DeckGridMetrics metrics;
  final double cellRatio;
  final double spacing;

  /// Builds the widget for the slot at [DeckLayout.slots] index `index`.
  final Widget Function(BuildContext context, int index) cellBuilder;

  @override
  Widget build(BuildContext context) {
    final width = metrics.gridWidth;
    final height = metrics.gridHeight;
    // Cells [DeckLayout.widgetCoveredIndexes] covers are never built at
    // all: the widget anchored elsewhere already draws over that area, via
    // its own wider/taller Positioned below.
    final covered = layout.widgetCoveredIndexes;
    return Center(
      child: SizedBox(
        // A transient zero/negative constraint (mid-resize, say) is left
        // to the grid's own intrinsic size rather than forced to a size
        // that would just throw.
        width: width.isFinite && width > 0 ? width : null,
        height: height.isFinite && height > 0 ? height : null,
        child: Stack(
          children: [
            for (
              var cellIndex = 0;
              cellIndex < layout.pageCapacity;
              cellIndex++
            )
              if (!covered.contains(
                layout.indexOf(page: page, cell: cellIndex),
              ))
                _positionedCell(context, cellIndex),
          ],
        ),
      ),
    );
  }

  Widget _positionedCell(BuildContext context, int cellIndex) {
    final index = layout.indexOf(page: page, cell: cellIndex);
    final row = cellIndex ~/ layout.columns;
    final column = cellIndex % layout.columns;
    final footprint = layout.footprintAt(index);
    return Positioned(
      left: column * (metrics.cellWidth + spacing),
      top: row * (metrics.cellHeight + spacing),
      width:
          footprint.columns * metrics.cellWidth +
          (footprint.columns - 1) * spacing,
      height:
          footprint.rows * metrics.cellHeight + (footprint.rows - 1) * spacing,
      child: cellBuilder(context, index),
    );
  }
}

/// Appearance, chosen on the host and applied on both.
enum DeckTheme {
  system('sys', 'System'),
  light('light', 'Light'),
  dark('dark', 'Dark');

  const DeckTheme(this.wire, this.label);

  /// Short identifier on the wire; the enum name is not used so renaming a
  /// constant cannot silently break an installed client.
  final String wire;
  final String label;

  static DeckTheme fromWire(String? wire) {
    for (final theme in values) {
      if (theme.wire == wire) return theme;
    }
    return DeckTheme.system;
  }
}

/// How a background image scales to fill the screen behind the deck.
///
/// A deliberate subset of Flutter's `BoxFit` rather than all of it: cropping
/// to fill, letterboxing to fit, and stretching cover every look a user
/// actually wants from a wallpaper, and a longer menu of the more esoteric
/// values would just be more to explain. The client, not this package,
/// knows what `BoxFit` is — this lives here as an opaque wire value the same
/// way [DeckTheme] does, and hotkeypad_client maps it to a real `BoxFit` for
/// painting.
enum BackgroundFit {
  cover('cover', 'Fill screen'),
  contain('contain', 'Fit whole image'),
  stretch('fill', 'Stretch');

  const BackgroundFit(this.wire, this.label);

  /// Short identifier on the wire; the enum name is not used so renaming a
  /// constant cannot silently break an installed client.
  final String wire;
  final String label;

  static BackgroundFit fromWire(String? wire) {
    for (final fit in values) {
      if (fit.wire == wire) return fit;
    }
    return BackgroundFit.cover;
  }
}

/// Host -> client: use this appearance.
///
/// Sent with the layout on connect and again whenever it changes, so the
/// phone follows the Mac rather than keeping settings of its own — the host
/// owns configuration here as it does the grid.
final class SetAppearance extends HotkeyPadMessage {
  const SetAppearance({
    required this.theme,
    required this.showLabels,
    this.backgroundImageId,
    this.backgroundOpacity = 1.0,
    this.backgroundFit = BackgroundFit.cover,
  });

  final DeckTheme theme;

  /// With labels off the deck is icons alone: cells go square and the icon
  /// fills them, since there is no caption to leave room for.
  final bool showLabels;

  /// Names an image behind the deck's button grid, fetched and cached the
  /// same way an app's own icon or a button's custom image is — see
  /// [RequestIcon] and [IconFrame]. Null means no custom background: the
  /// client draws its ordinary theme-derived background instead, which is
  /// also what an older host that never sent this field gets.
  final String? backgroundImageId;

  /// How opaque [backgroundImageId] is drawn over the deck's own background,
  /// 0 (invisible) to 1 (fully opaque). Meaningless while that id is null.
  final double backgroundOpacity;

  /// How [backgroundImageId] is scaled to fill the screen. Meaningless
  /// while that id is null.
  final BackgroundFit backgroundFit;

  @override
  Map<String, Object?> toJson() => {
    't': 'thm',
    'v': theme.wire,
    'lbl': showLabels,
    // Omitted entirely rather than sent as null/defaults when there is no
    // background, so an older client parsing this message with a stricter
    // decoder would still see nothing background-shaped to misinterpret.
    if (backgroundImageId != null) 'bg': backgroundImageId,
    if (backgroundImageId != null) 'bop': backgroundOpacity,
    if (backgroundImageId != null) 'bft': backgroundFit.wire,
  };
}

/// Client -> host: send me the deck layout.
final class RequestLayout extends HotkeyPadMessage {
  const RequestLayout();

  @override
  Map<String, Object?> toJson() => {'t': 'lay?'};
}

/// Host -> client: a layout of this size follows, cell by cell.
///
/// Sent as a header plus one message per occupied cell rather than as one
/// payload, for the same reason as the app catalogue: there is no reassembly
/// on this link and a full grid would not fit a single notification.
final class LayoutStart extends HotkeyPadMessage {
  const LayoutStart({
    required this.columns,
    required this.rows,
    required this.pages,
  });

  final int columns;
  final int rows;
  final int pages;

  @override
  Map<String, Object?> toJson() => {
    't': 'lay',
    'c': columns,
    'r': rows,
    'p': pages,
  };
}

/// Host -> client: the contents of one cell.
final class LayoutSlot extends HotkeyPadMessage {
  const LayoutSlot({required this.index, required this.value});

  final int index;
  final String value;

  @override
  Map<String, Object?> toJson() => {'t': 'slot', 'i': index, 'v': value};
}

/// Host -> client: the layout is complete.
final class LayoutEnd extends HotkeyPadMessage {
  const LayoutEnd();

  @override
  Map<String, Object?> toJson() => {'t': 'laye'};
}

/// Something a deck button can do besides launching an app.
///
/// Volume goes through AppleScript, which needs no special permission.
/// Transport control has to be posted as a system media key, which macOS
/// silently drops unless the host has been granted Accessibility — the host
/// reports that rather than letting the button fail quietly.
enum DeckAction {
  playPause('playpause', 'Play / Pause'),
  next('next', 'Next track'),
  previous('previous', 'Previous track'),
  volumeUp('volup', 'Volume up'),
  volumeDown('voldown', 'Volume down'),
  mute('mute', 'Mute');

  const DeckAction(this.wire, this.label);

  /// Short identifier on the wire; the enum name is not used so renaming a
  /// constant cannot silently break an installed client.
  final String wire;
  final String label;

  static DeckAction? fromWire(String wire) {
    for (final action in values) {
      if (action.wire == wire) return action;
    }
    return null;
  }

  bool get isVolume => this == volumeUp || this == volumeDown || this == mute;
}

/// Client -> host: the button in this slot was pressed.
///
/// The only way a client asks for anything to happen. An id rather than a
/// description of what to do: the host looks the slot up in its own layout
/// and acts on what it finds there, so a client can only trigger what the
/// host was already configured with. That matters once buttons can hold
/// shell commands, and it keeps every kind of button on one path.
final class PressSlot extends HotkeyPadMessage {
  const PressSlot({required this.id});

  /// A [DeckSlot.id], carried unchanged from whatever [LayoutSlot] put it on
  /// the button that was tapped.
  final int id;

  @override
  Map<String, Object?> toJson() => {'t': 'press', 'i': id};
}

/// Client -> host: send me this app's icon.
final class RequestIcon extends HotkeyPadMessage {
  const RequestIcon({required this.name});

  final String name;

  @override
  Map<String, Object?> toJson() => {'t': 'ico', 'n': name};
}

/// Host -> client: there is no icon for this app, stop waiting for one.
final class IconUnavailable extends HotkeyPadMessage {
  const IconUnavailable({required this.name});

  final String name;

  @override
  Map<String, Object?> toJson() => {'t': 'ico!', 'n': name};
}

/// Host -> client: the result of the last command.
final class Ack extends HotkeyPadMessage {
  const Ack({required this.ok, required this.message});

  final bool ok;
  final String message;

  @override
  Map<String, Object?> toJson() => {'t': 'ack', 'ok': ok, 'm': message};
}

/// Either direction: free text, used only by the debug console.
final class DebugText extends HotkeyPadMessage {
  const DebugText({required this.text});

  final String text;

  @override
  Map<String, Object?> toJson() => {'t': 'txt', 'm': text};
}

/// One slice of an icon, sent as binary rather than JSON.
///
/// A 64px PNG is around 5KB; base64 inside a JSON message would inflate that
/// by a third and, at the MTU an iPhone negotiates, need roughly sixty
/// notifications per icon. Binary frames roughly halve that.
///
/// Frames share the notify characteristic with JSON messages. A JSON message
/// always begins with `{` (0x7b), so a leading [magic] byte tells them apart
/// unambiguously.
///
/// Layout: `[magic][nameLength][name utf8][index u16be][total u16be][payload]`
///
/// The app name is repeated in every frame rather than tracked as connection
/// state, so reassembly stays correct even if two icons ever interleave.
abstract final class IconFrame {
  static const magic = 0x01;

  static bool looksLikeFrame(List<int> bytes) =>
      bytes.isNotEmpty && bytes.first == magic;

  static int headerSize(String name) => 6 + utf8.encode(name).length;

  /// Bytes of icon data that fit in one notification of [maxNotifyLength].
  static int payloadCapacity(int maxNotifyLength, String name) =>
      maxNotifyLength - headerSize(name);

  static Uint8List encode({
    required String name,
    required int index,
    required int total,
    required List<int> payload,
  }) {
    final nameBytes = utf8.encode(name);
    if (nameBytes.length > 255) {
      throw ArgumentError.value(name, 'name', 'too long to frame');
    }
    final bytes = BytesBuilder()
      ..addByte(magic)
      ..addByte(nameBytes.length)
      ..add(nameBytes)
      ..addByte((index >> 8) & 0xff)
      ..addByte(index & 0xff)
      ..addByte((total >> 8) & 0xff)
      ..addByte(total & 0xff)
      ..add(payload);
    return bytes.toBytes();
  }

  /// Returns null for anything that is not a well-formed frame, including a
  /// truncated one.
  static ({String name, int index, int total, Uint8List payload})? decode(
    List<int> bytes,
  ) {
    if (!looksLikeFrame(bytes) || bytes.length < 2) return null;
    final nameLength = bytes[1];
    final headerEnd = 2 + nameLength + 4;
    if (bytes.length < headerEnd) return null;
    try {
      final name = utf8.decode(bytes.sublist(2, 2 + nameLength));
      final index = (bytes[2 + nameLength] << 8) | bytes[3 + nameLength];
      final total = (bytes[4 + nameLength] << 8) | bytes[5 + nameLength];
      if (total == 0 || index >= total) return null;
      return (
        name: name,
        index: index,
        total: total,
        payload: Uint8List.fromList(bytes.sublist(headerEnd)),
      );
    } catch (_) {
      return null;
    }
  }
}

/// How a client reached the host — shown next to a connected device's name
/// wherever more than one might be picked between (the device lock), since
/// the same phone can show up twice at once, once per transport.
enum LinkTransport {
  bluetooth('bluetooth'),
  wifi('wifi');

  const LinkTransport(this.label);
  final String label;
}

/// Fixed ports for the WiFi transport, agreed on by both ends since neither
/// negotiates the other's address ahead of time.
abstract final class WifiLink {
  /// Where the host's `ServerSocket` listens. BLE has no equivalent to pick
  /// — a peripheral's GATT server just *is* the service — so WiFi needs a
  /// fixed rendezvous point instead.
  static const tcpPort = 54871;

  /// Where the host's discovery beacon is broadcast, and where a client
  /// listens for one. Deliberately not [tcpPort]: a broadcast socket and a
  /// connection-oriented server socket are different concerns, and sharing
  /// a port would make either harder to reason about on its own.
  static const discoveryPort = 54872;

  /// How often the host re-announces itself. Frequent enough that a client
  /// which starts listening a moment late still finds it quickly; sparse
  /// enough not to be noise on the network.
  static const beaconInterval = Duration(seconds: 2);
}

/// Adds a 4-byte big-endian length prefix so a byte *stream* with no
/// built-in message boundaries (a TCP socket) can still carry the same
/// discrete messages BLE already delivers one per GATT write/notify —
/// [HotkeyPadMessage] bytes and [IconFrame] bytes alike, unchanged either way.
/// Nothing else in the protocol needs to know this exists.
abstract final class FrameCodec {
  static Uint8List encode(List<int> payload) {
    final framed = Uint8List(4 + payload.length);
    framed.buffer.asByteData().setUint32(0, payload.length, Endian.big);
    framed.setRange(4, framed.length, payload);
    return framed;
  }
}

/// Reassembles [FrameCodec]-framed messages out of a byte stream, needed
/// only for a stream transport like TCP — BLE already delivers one whole
/// message per GATT write/notify, so it has no equivalent.
///
/// Stateful and incremental on purpose: a socket hands over bytes in
/// whatever chunks the network happened to deliver, which may split a
/// frame's header or payload anywhere at all, or bundle several frames
/// into one chunk.
class FrameReassembler {
  final _buffer = BytesBuilder();
  int? _expectedLength;

  /// Feeds [chunk] in and returns every frame it completed, in order. A
  /// still-incomplete trailing frame is buffered for the next call rather
  /// than returned.
  List<Uint8List> add(List<int> chunk) {
    _buffer.add(chunk);
    final frames = <Uint8List>[];
    while (true) {
      final bytes = _buffer.toBytes();
      final expected = _expectedLength;
      if (expected == null) {
        if (bytes.length < 4) break;
        _expectedLength = ByteData.sublistView(
          bytes,
          0,
          4,
        ).getUint32(0, Endian.big);
        continue;
      }
      if (bytes.length < 4 + expected) break;
      frames.add(Uint8List.fromList(bytes.sublist(4, 4 + expected)));
      _buffer
        ..clear()
        ..add(bytes.sublist(4 + expected));
      _expectedLength = null;
    }
    return frames;
  }
}

/// Broadcast over UDP so a client on the same LAN can find the host without
/// the user typing in an IP address — WiFi's equivalent of a BLE
/// advertisement.
class WifiBeacon {
  const WifiBeacon({
    required this.hostId,
    required this.name,
    required this.port,
  });

  /// Persists across restarts (see the host's `HostIdentity`) and is
  /// namespaced separately from a BLE peripheral's own UUID — the two
  /// transports do not share an identity, so the same Mac reached over
  /// either one is cached separately on the client. Not shown to the user;
  /// [name] is.
  final String hostId;

  /// The host's own display name (its computer name), so a client picking
  /// between several discovered hosts sees something meaningful rather
  /// than a bare id.
  final String name;

  final int port;

  Uint8List encode() => Uint8List.fromList(
    utf8.encode(jsonEncode({'t': 'beacon', 'h': hostId, 'n': name, 'p': port})),
  );

  /// Returns null for anything that is not a well-formed beacon, so a
  /// stray or malformed UDP packet on the same port cannot be mistaken for
  /// one — this travels outside the app's own service boundary (BLE at
  /// least filters by service UUID), so it must not trust its input.
  static WifiBeacon? tryParse(List<int> bytes) {
    try {
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map || json['t'] != 'beacon') return null;
      final hostId = json['h'];
      final name = json['n'];
      final port = json['p'];
      if (hostId is! String || name is! String || port is! int) return null;
      return WifiBeacon(hostId: hostId, name: name, port: port);
    } catch (_) {
      return null;
    }
  }
}

/// A host's WiFi pairing QR code, scanned instead of typed in — see the
/// host's "Pair via QR" button and the client's QR-scan screen.
///
/// Distinct from [WifiBeacon]: a beacon's sender address is inferred from
/// the UDP packet's own envelope, but a QR code has no such envelope, so
/// [address] has to travel in the payload here. Kept in this shared
/// package, not duplicated on each side, for the same reason [WifiBeacon]
/// is: the host encodes it and the client decodes it, and a format change
/// on one side without the other would otherwise fail silently (an
/// unrecognized QR code just looks like "not a HotkeyPad host").
class WifiPairingQr {
  const WifiPairingQr({
    required this.hostId,
    required this.name,
    required this.address,
    required this.port,
  });

  /// Same identity a beacon-discovered connection would get — see
  /// [WifiBeacon.hostId] — so a QR-paired connection's cached layout/icons
  /// land in the same place a later beacon-discovered reconnect would use,
  /// rather than a separate `manual:`-prefixed entry.
  final String hostId;

  final String name;
  final String address;
  final int port;

  /// A `hotkeypad://connect?...` URI — human-unreadable is fine, it is
  /// only ever produced as a QR code and consumed by [tryParse], never
  /// typed or displayed as text.
  Uri encode() => Uri(
    scheme: 'hotkeypad',
    host: 'connect',
    queryParameters: {
      'host': hostId,
      'name': name,
      'address': address,
      'port': '$port',
    },
  );

  /// Returns null for anything that is not a well-formed pairing URI, so
  /// scanning an arbitrary QR code in the wild (a URL, a WiFi-password
  /// code, anything) is reported as "not a HotkeyPad host" rather than
  /// crashing or connecting somewhere nonsensical.
  static WifiPairingQr? tryParse(String data) {
    final uri = Uri.tryParse(data.trim());
    if (uri == null) return null;
    if (uri.scheme != 'hotkeypad' || uri.host != 'connect') return null;
    final hostId = uri.queryParameters['host'];
    final address = uri.queryParameters['address'];
    final port = int.tryParse(uri.queryParameters['port'] ?? '');
    if (hostId == null || hostId.isEmpty) return null;
    if (address == null || address.isEmpty) return null;
    if (port == null || port <= 0) return null;
    final name = uri.queryParameters['name'];
    return WifiPairingQr(
      hostId: hostId,
      name: (name == null || name.isEmpty) ? HotkeyPad.advertisedName : name,
      address: address,
      port: port,
    );
  }
}
