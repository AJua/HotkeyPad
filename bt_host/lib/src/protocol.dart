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
        'open' => OpenApp(name: json['n'] as String),
        'act' => switch (DeckAction.fromWire(json['a'] as String? ?? '')) {
          final action? => RunAction(action: action),
          // An action this build does not know about.
          null => null,
        },
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

/// Client -> host: perform an action that is not an app launch.
final class RunAction extends BtMessage {
  const RunAction({required this.action});

  final DeckAction action;

  @override
  Map<String, Object?> toJson() => {'t': 'act', 'a': action.wire};
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

/// Client -> host: launch this app.
final class OpenApp extends BtMessage {
  const OpenApp({required this.name});

  final String name;

  @override
  Map<String, Object?> toJson() => {'t': 'open', 'n': name};
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
