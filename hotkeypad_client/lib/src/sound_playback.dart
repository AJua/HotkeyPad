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
/// Pressing a button whose sound is still playing stops it instead of
/// starting a second copy on top: a long clip needs a way to be cut short,
/// and the button that started it is the obvious one.
class SoundPlayback {
  SoundPlayback._();

  static final instance = SoundPlayback._();

  final _players = <String, AudioPlayer>{};

  /// Plays [soundId] from [bytes], or stops it if it is already playing.
  /// Returns false only if playback could not start.
  Future<bool> toggle(String soundId, Uint8List bytes) async {
    final current = _players[soundId];
    if (current != null && current.state == PlayerState.playing) {
      await current.stop();
      return true;
    }
    try {
      final file = await _fileFor(soundId, bytes);
      final player = current ?? AudioPlayer();
      _players[soundId] = player;
      await player.play(DeviceFileSource(file.path));
      return true;
    } catch (_) {
      return false;
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
