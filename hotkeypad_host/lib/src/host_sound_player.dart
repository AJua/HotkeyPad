import 'dart:io';

import 'package:flutter/foundation.dart';

import 'sound_store.dart';

/// Starts a process — [Process.start] in the app, a fake in tests.
typedef ProcessStarter =
    Future<Process> Function(String executable, List<String> arguments);

/// Plays a [PlaySoundItem] whose target is [SoundTarget.host] through this
/// Mac's own speakers, with `afplay` — it ships with macOS and plays every
/// format Core Audio does.
///
/// Matches the phone's own player (the client's SoundPlayback): each press
/// starts another copy on top of whatever is already playing, and past
/// [maxConcurrent] the oldest still playing is cut off.
class HostSoundPlayer {
  HostSoundPlayer({
    ProcessStarter? start,
    String? Function(String soundId)? pathFor,
    bool Function(String path)? exists,
    bool? supported,
  }) : _start = start ?? Process.start,
       _pathFor = pathFor ?? SoundStore.pathFor,
       _exists = exists ?? ((path) => File(path).existsSync()),
       _supported = supported ?? (!kIsWeb && Platform.isMacOS);

  /// The one the app uses.
  static final instance = HostSoundPlayer();

  static const maxConcurrent = 8;

  final ProcessStarter _start;
  final String? Function(String soundId) _pathFor;
  final bool Function(String path) _exists;
  final bool _supported;

  /// Copies still playing, oldest first.
  final _playing = <Process>[];

  @visibleForTesting
  int get playingCount => _playing.length;

  Future<({bool ok, String message})> play(String soundId) async {
    if (!_supported) {
      return (ok: false, message: 'Sounds only play on macOS hosts');
    }
    final path = _pathFor(soundId);
    if (path == null || !_exists(path)) {
      return (ok: false, message: 'This sound file is missing on the host');
    }
    try {
      if (_playing.length >= maxConcurrent) {
        _playing.removeAt(0).kill();
      }
      final process = await _start('/usr/bin/afplay', [path]);
      _playing.add(process);
      process.exitCode.then((_) => _playing.remove(process));
      return (ok: true, message: 'Playing');
    } on ProcessException catch (error) {
      return (ok: false, message: error.message);
    }
  }
}
