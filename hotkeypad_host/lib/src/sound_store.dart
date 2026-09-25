import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'config_dir.dart';

/// Audio files the user has picked for a [PlaySoundItem], played on the
/// client's own speaker.
///
/// Stored next to `layout.json`, one file per id, copied from wherever the
/// user picked it so moving or deleting the original does not break the
/// button. The id is also the name the client requests it by — the same
/// [RequestIcon] transfer an icon or a background image uses, which already
/// carries any bytes keyed by an opaque string — see host_page.dart's
/// `_sendIcon`.
abstract final class SoundStore {
  static const _channel = MethodChannel('btlink/icons');

  /// Largest file accepted. Every byte crosses the link to the phone — over
  /// Bluetooth a few KB a second — so a sound effect fits comfortably but a
  /// whole song would leave the button silent for minutes the first time.
  static const maxBytes = 2 * 1024 * 1024;

  /// The native picker is macOS-only for now, as for custom icons.
  static bool get supported => !kIsWeb && Platform.isMacOS;

  static Directory? get _directory {
    final dir = ConfigDir.path;
    if (dir == null) return null;
    return Directory('$dir/sounds');
  }

  static final _idPattern = RegExp(r'^snd_\d+\.[a-z0-9]{1,5}$');

  /// Whether [id] is one this store hands out. Checked before touching the
  /// disk: ids arrive from the client over the air, and one like
  /// `../layout.json` must not read anything outside this store's folder.
  static bool isSoundId(String id) => _idPattern.hasMatch(id);

  /// A fresh id for a file picked from [path], keeping its extension (the
  /// client's player needs it to recognise the format). Null for a file
  /// with no usable extension.
  @visibleForTesting
  static String? idFor(String path, int micros) {
    final name = path.split(RegExp(r'[/\\]')).last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0) return null;
    final extension = name.substring(dot + 1).toLowerCase();
    final id = 'snd_$micros.$extension';
    return isSoundId(id) ? id : null;
  }

  /// [path]'s file name without its folder or extension, as a default
  /// button label — `/Users/me/Sounds/Applause.mp3` reads as "Applause".
  static String labelFor(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  /// Opens a native file picker restricted to audio files. Returns the
  /// chosen path, or null if the user cancelled or there is no picker.
  static Future<String?> pick() async {
    if (!supported) return null;
    try {
      return await _channel.invokeMethod<String>('pickAudio');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Copies the file at [path] into the store. Returns its new id, or an
  /// error to show the user — too big, not a file with an extension, or
  /// unreadable.
  static Future<({String? id, String? error})> import(String path) async {
    final directory = _directory;
    if (directory == null) return (id: null, error: 'No place to store it');
    final id = idFor(path, DateTime.now().microsecondsSinceEpoch);
    if (id == null) {
      return (id: null, error: 'The file needs an extension like .mp3');
    }
    try {
      final source = File(path);
      final length = await source.length();
      if (length > maxBytes) {
        final megabytes = (length / (1024 * 1024)).toStringAsFixed(1);
        return (
          id: null,
          error:
              'Too large ($megabytes MB); sounds are limited to '
              '${maxBytes ~/ (1024 * 1024)} MB',
        );
      }
      await directory.create(recursive: true);
      await source.copy('${directory.path}/$id');
      return (id: id, error: null);
    } on FileSystemException catch (error) {
      return (id: null, error: error.message);
    }
  }

  static Future<Uint8List?> read(String id) async {
    final directory = _directory;
    if (directory == null || !isSoundId(id)) return null;
    final file = File('${directory.path}/$id');
    try {
      if (!file.existsSync()) return null;
      return await file.readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  /// Best-effort, like [CustomIconStore.delete]: a file left behind costs
  /// disk space, not correctness.
  static Future<void> delete(String id) async {
    final directory = _directory;
    if (directory == null || !isSoundId(id)) return;
    try {
      final file = File('${directory.path}/$id');
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // Ignored, as above.
    }
  }
}
