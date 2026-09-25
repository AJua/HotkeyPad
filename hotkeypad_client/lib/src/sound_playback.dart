import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

/// Plays a [PlaySoundItem]'s audio on this phone's own speaker.
///
/// The bytes arrive from the host like an icon and are cached the same way
/// (see IconCache); this writes them out once more under their own name —
/// the sound id keeps its extension (`snd_123.mp3`), which the platform
/// player relies on to recognise the format — and plays that file.
///
/// Every press starts a fresh copy, overlapping whatever is already
/// playing, so hammering a soundboard button stacks up the sound the way a
/// physical one does. Each copy gets its own player, released when it
/// finishes; past [maxConcurrent] the oldest still playing is cut off, so
/// a burst of presses can't pile up players without bound.
class SoundPlayback {
  SoundPlayback._();

  static final instance = SoundPlayback._();

  static const maxConcurrent = 8;

  /// Players still sounding, oldest first.
  final _active = <AudioPlayer>[];

  /// Starts [soundId] from [bytes]. Returns false only if playback could
  /// not start.
  Future<bool> play(String soundId, Uint8List bytes) async {
    final player = AudioPlayer();
    try {
      final file = await _fileFor(soundId, bytes);
      if (_active.length >= maxConcurrent) {
        unawaited(_release(_active.first));
      }
      _active.add(player);
      player.onPlayerComplete.first.then((_) => _release(player));
      await player.play(DeviceFileSource(file.path));
      return true;
    } catch (_) {
      _active.remove(player);
      unawaited(player.dispose());
      return false;
    }
  }

  Future<void> _release(AudioPlayer player) async {
    if (!_active.remove(player)) return;
    try {
      await player.dispose();
    } catch (_) {
      // Already torn down; nothing left to release.
    }
  }

  Future<File> _fileFor(String soundId, Uint8List bytes) async {
    final directory = Directory(
      '${(await getTemporaryDirectory()).path}/sounds',
    );
    final file = File('${directory.path}/$soundId');
    // Ids are never reused for different content (the host mints a fresh
    // one per imported file), so an existing file is already right.
    if (!file.existsSync()) {
      await directory.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    }
    return file;
  }
}
