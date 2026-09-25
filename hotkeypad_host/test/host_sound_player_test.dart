import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hotkeypad_host/src/host_sound_player.dart';

/// Stands in for an `afplay` process: never exits until killed or told to.
class _FakeProcess implements Process {
  final _exit = Completer<int>();
  bool killed = false;

  void finish() {
    if (!_exit.isCompleted) _exit.complete(0);
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    finish();
    return true;
  }

  @override
  Future<int> get exitCode => _exit.future;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late List<(String, List<String>)> started;
  late List<_FakeProcess> processes;

  HostSoundPlayer player({bool exists = true, bool supported = true}) =>
      HostSoundPlayer(
        start: (executable, arguments) async {
          started.add((executable, arguments));
          final process = _FakeProcess();
          processes.add(process);
          return process;
        },
        pathFor: (id) => '/sounds/$id',
        exists: (_) => exists,
        supported: supported,
      );

  setUp(() {
    started = [];
    processes = [];
  });

  test('plays the stored file with afplay', () async {
    final result = await player().play('snd_1.mp3');

    expect(result.ok, isTrue);
    expect(started, hasLength(1));
    expect(started.single.$1, '/usr/bin/afplay');
    expect(started.single.$2, ['/sounds/snd_1.mp3']);
  });

  test('a second press overlaps the first instead of stopping it', () async {
    final p = player();

    await p.play('snd_1.mp3');
    await p.play('snd_1.mp3');

    expect(started, hasLength(2));
    expect(processes.any((process) => process.killed), isFalse);
    expect(p.playingCount, 2);
  });

  test('past the cap, the oldest copy is cut off', () async {
    final p = player();

    for (var i = 0; i <= HostSoundPlayer.maxConcurrent; i++) {
      await p.play('snd_1.mp3');
    }

    expect(processes.first.killed, isTrue);
    expect(processes.skip(1).any((process) => process.killed), isFalse);
    expect(p.playingCount, HostSoundPlayer.maxConcurrent);
  });

  test('a copy that finishes on its own is forgotten', () async {
    final p = player();
    await p.play('snd_1.mp3');

    processes.single.finish();
    await Future<void>.delayed(Duration.zero);

    expect(p.playingCount, 0);
  });

  test('a missing file is an error, not a silent no-op', () async {
    final result = await player(exists: false).play('snd_1.mp3');

    expect(result.ok, isFalse);
    expect(started, isEmpty);
  });

  test('is an error off macOS', () async {
    final result = await player(supported: false).play('snd_1.mp3');

    expect(result.ok, isFalse);
    expect(started, isEmpty);
  });
}
