import 'dart:convert';
import 'dart:typed_data';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';

/// The contract shared by the host service and the client app.
///
/// Both projects keep an identical copy of this file. If you change a UUID or
/// a message shape here, change it in the other project too or they will stop
/// understanding each other.
abstract final class BtLink {
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
  /// takes 18 and the flags 3. 'BTLink' fits in what is left; a longer name
  /// spills into the scan response and only passive scanners lose it.
  static const advertisedName = 'BTLink';

  /// Points square for a rendered app icon.
  ///
  /// Deck buttons fill their whole tappable area with the icon, so on a 3x
  /// phone screen this is scaled to roughly 300 physical pixels; 64px was
  /// visibly soft there. The cost is ~15KB per icon instead of ~5KB, paid
  /// once because the client caches them.
  ///
  /// The client's cache keys include this number, so changing it invalidates
  /// stored icons rather than leaving stale ones at the old resolution.
  static const iconSize = 128;
}

/// One message on the link.
///
/// Every message is a single JSON object on a single ATT operation — there is
/// no reassembly, so a message must fit the negotiated MTU. Keys are one or
/// two characters for that reason.
sealed class BtMessage {
  const BtMessage();

  Map<String, Object?> toJson();

  Uint8List encode() => Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  /// Returns null for anything that is not a message this build understands,
  /// so an older peer cannot crash a newer one.
  static BtMessage? decode(List<int> bytes) {
    try {
      final json = jsonDecode(utf8.decode(bytes));
      if (json is! Map<String, Object?>) return null;
      return switch (json['t']) {
        'ls' => const ListApps(),
        'app' => AppEntry(
          name: json['n'] as String,
          category: json['c'] as String?,
        ),
        'end' => ListEnd(count: json['c'] as int? ?? 0),
        'press' => PressSlot(index: json['i'] as int),
        'thm' => SetAppearance(
          theme: DeckTheme.fromWire(json['v'] as String?),
          // Absent on an older host, which always drew labels.
          showLabels: json['lbl'] as bool? ?? true,
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
final class ListApps extends BtMessage {
  const ListApps();

  @override
  Map<String, Object?> toJson() => {'t': 'ls'};
}

/// Host -> client: one entry of the catalogue.
final class AppEntry extends BtMessage {
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
final class ListEnd extends BtMessage {
  const ListEnd({required this.count});

  final int count;

  @override
  Map<String, Object?> toJson() => {'t': 'end', 'c': count};
}

/// One button on the deck.
///
/// Stored as a string in the layout. Simple items keep their original
/// prefixed form (`app:Safari`, `act:mute`) so a layout written by an older
/// build still loads; anything carrying extra fields — a custom emoji, a
/// command — is stored as JSON, which the parser recognises by its leading
/// brace.
sealed class DeckItem {
  const DeckItem();

  String get stored;
  String get label;

  /// Shown instead of an app icon or a built-in glyph when set.
  String? get emoji;

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
      return switch (json['t']) {
        'app' => AppItem(json['n'] as String, emoji: emoji),
        'act' => switch (DeckAction.fromWire(json['a'] as String? ?? '')) {
          final action? => ActionItem(action, emoji: emoji),
          null => null,
        },
        'sh' => ShellItem(
          command: json['c'] as String,
          label: json['l'] as String,
          emoji: emoji,
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
        ),
        'sc' => ShortcutItem(
          name: json['n'] as String,
          label: json['l'] as String?,
          emoji: emoji,
        ),
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
  const AppItem(this.name, {this.emoji});

  final String name;

  @override
  final String? emoji;

  @override
  String get stored => emoji == null
      ? 'app:$name'
      : jsonEncode({'t': 'app', 'n': name, 'e': emoji});

  @override
  String get label => name;
}

final class ActionItem extends DeckItem {
  const ActionItem(this.action, {this.emoji});

  final DeckAction action;

  @override
  final String? emoji;

  @override
  String get stored => emoji == null
      ? 'act:${action.wire}'
      : jsonEncode({'t': 'act', 'a': action.wire, 'e': emoji});

  @override
  String get label => action.label;
}

/// Runs a shell command on the host.
///
/// The command lives only in the host's layout. A client presses a slot by
/// index and the host looks up what that slot holds, so nothing a client
/// sends can become a command — see [PressSlot].
final class ShellItem extends DeckItem {
  const ShellItem({
    required this.command,
    required this.label,
    this.emoji,
  });

  final String command;

  @override
  final String label;

  @override
  final String? emoji;

  @override
  String get stored => jsonEncode({
    't': 'sh',
    'c': command,
    'l': label,
    if (emoji != null) 'e': emoji,
  });
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
  });
}

/// Runs a macOS Shortcut by name.
final class ShortcutItem extends DeckItem {
  const ShortcutItem({required this.name, String? label, this.emoji})
    : _label = label;

  final String name;
  final String? _label;

  @override
  String get label => _label?.isNotEmpty == true ? _label! : name;

  @override
  final String? emoji;

  @override
  String get stored => jsonEncode({
    't': 'sc',
    'n': name,
    if (_label != null) 'l': _label,
    if (emoji != null) 'e': emoji,
  });
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
    this.isTurned = false,
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
    slots: List<String?>.filled(columns * rows * pages, null),
  );

  static const defaultColumns = 5;
  static const defaultRows = 3;
  static const maxPages = 8;

  final int columns;
  final int rows;
  final int pages;

  /// True when this is a turned view of the host's layout. Cell indices
  /// here are not the host's, so [sourceIndex] must translate before one is
  /// sent back.
  final bool isTurned;

  /// One entry per cell across every page, in reading order, null where the
  /// cell is empty. Flat rather than nested so an index identifies a cell
  /// globally and a drag between pages needs no special case.
  ///
  /// Values are [DeckItem] storage strings; the protocol does not interpret
  /// them.
  final List<String?> slots;

  /// Cells on one page.
  int get pageCapacity => columns * rows;

  /// Cells across every page.
  int get capacity => pageCapacity * pages;

  int indexOf({required int page, required int cell}) =>
      page * pageCapacity + cell;

  /// The slots belonging to [page], in reading order.
  List<String?> page(int index) =>
      slots.sublist(index * pageCapacity, (index + 1) * pageCapacity);

  DeckLayout resized({int? columns, int? rows, int? pages}) {
    final newColumns = columns ?? this.columns;
    final newRows = rows ?? this.rows;
    final newPages = pages ?? this.pages;
    final resized = List<String?>.filled(
      newColumns * newRows * newPages,
      null,
    );
    // Keep cells where they are on screen rather than where they are in the
    // list: a row of buttons should not shuffle sideways when a column is
    // added, and a page should not absorb the next one's buttons.
    for (var page = 0; page < newPages && page < this.pages; page++) {
      for (var row = 0; row < newRows && row < this.rows; row++) {
        for (var column = 0;
            column < newColumns && column < this.columns;
            column++) {
          resized[page * newColumns * newRows + row * newColumns + column] =
              slots[page * this.columns * this.rows + row * this.columns +
                  column];
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

  /// The index this cell has in the host's layout.
  ///
  /// A turned view renumbers every cell, and the host resolves a press
  /// against its own unturned copy — so sending the on-screen index would
  /// fire whichever button happens to sit at that number over there.
  int sourceIndex(int index) {
    if (!isTurned) return index;
    final page = index ~/ pageCapacity;
    final cell = index % pageCapacity;
    final row = cell ~/ columns;
    final column = cell % columns;
    // Rows and columns are swapped relative to the source, so this view's
    // column is the source's row. The source is `rows` wide.
    return page * pageCapacity + column * rows + row;
  }

  /// Swaps rows and columns, so a 5-wide grid becomes 5-tall.
  ///
  /// A transpose rather than a rotation: the first row becomes the first
  /// column, which is what "the wide one turned upright" looks like and
  /// keeps every button's neighbours the same. A rotation would also move
  /// buttons to the opposite edge, which is harder to predict.
  DeckLayout transposed() {
    if (columns == rows) return this;
    final swapped = List<String?>.filled(slots.length, null);
    for (var page = 0; page < pages; page++) {
      final offset = page * pageCapacity;
      for (var row = 0; row < rows; row++) {
        for (var column = 0; column < columns; column++) {
          swapped[offset + column * rows + row] =
              slots[offset + row * columns + column];
        }
      }
    }
    return DeckLayout(
      columns: rows,
      rows: columns,
      pages: pages,
      slots: swapped,
      // Turning twice returns to the host's numbering.
      isTurned: !isTurned,
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
    final copy = List<String?>.of(slots);
    copy[index] = value;
    return DeckLayout(
      columns: columns,
      rows: rows,
      pages: pages,
      slots: copy,
    );
  }

  /// Moves the contents of [from] to [to], swapping if [to] is occupied.
  DeckLayout moved(int from, int to) {
    if (from == to) return this;
    final copy = List<String?>.of(slots);
    final moving = copy[from];
    copy[from] = copy[to];
    copy[to] = moving;
    return DeckLayout(
      columns: columns,
      rows: rows,
      pages: pages,
      slots: copy,
    );
  }

  Map<String, Object?> toJson() => {
    'columns': columns,
    'rows': rows,
    'pages': pages,
    'slots': slots,
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
      slots: slots.map((slot) => slot is String ? slot : null).toList(),
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

/// Host -> client: use this appearance.
///
/// Sent with the layout on connect and again whenever it changes, so the
/// phone follows the Mac rather than keeping settings of its own — the host
/// owns configuration here as it does the grid.
final class SetAppearance extends BtMessage {
  const SetAppearance({required this.theme, required this.showLabels});

  final DeckTheme theme;

  /// With labels off the deck is icons alone: cells go square and the icon
  /// fills them, since there is no caption to leave room for.
  final bool showLabels;

  @override
  Map<String, Object?> toJson() => {
    't': 'thm',
    'v': theme.wire,
    'lbl': showLabels,
  };
}

/// Client -> host: send me the deck layout.
final class RequestLayout extends BtMessage {
  const RequestLayout();

  @override
  Map<String, Object?> toJson() => {'t': 'lay?'};
}

/// Host -> client: a layout of this size follows, cell by cell.
///
/// Sent as a header plus one message per occupied cell rather than as one
/// payload, for the same reason as the app catalogue: there is no reassembly
/// on this link and a full grid would not fit a single notification.
final class LayoutStart extends BtMessage {
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
final class LayoutSlot extends BtMessage {
  const LayoutSlot({required this.index, required this.value});

  final int index;
  final String value;

  @override
  Map<String, Object?> toJson() => {'t': 'slot', 'i': index, 'v': value};
}

/// Host -> client: the layout is complete.
final class LayoutEnd extends BtMessage {
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

  bool get isVolume =>
      this == volumeUp || this == volumeDown || this == mute;
}

/// Client -> host: the button in this slot was pressed.
///
/// The only way a client asks for anything to happen. An index rather than a
/// description of what to do: the host looks the slot up in its own layout
/// and acts on what it finds there, so a client can only trigger what the
/// host was already configured with. That matters once buttons can hold
/// shell commands, and it keeps every kind of button on one path.
final class PressSlot extends BtMessage {
  const PressSlot({required this.index});

  final int index;

  @override
  Map<String, Object?> toJson() => {'t': 'press', 'i': index};
}

/// Client -> host: send me this app's icon.
final class RequestIcon extends BtMessage {
  const RequestIcon({required this.name});

  final String name;

  @override
  Map<String, Object?> toJson() => {'t': 'ico', 'n': name};
}

/// Host -> client: there is no icon for this app, stop waiting for one.
final class IconUnavailable extends BtMessage {
  const IconUnavailable({required this.name});

  final String name;

  @override
  Map<String, Object?> toJson() => {'t': 'ico!', 'n': name};
}

/// Host -> client: the result of the last command.
final class Ack extends BtMessage {
  const Ack({required this.ok, required this.message});

  final bool ok;
  final String message;

  @override
  Map<String, Object?> toJson() => {'t': 'ack', 'ok': ok, 'm': message};
}

/// Either direction: free text, used only by the debug console.
final class DebugText extends BtMessage {
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
