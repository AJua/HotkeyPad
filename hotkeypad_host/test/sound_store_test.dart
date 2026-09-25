import 'package:flutter_test/flutter_test.dart';
import 'package:hotkeypad_host/src/sound_store.dart';

void main() {
  group('SoundStore.idFor', () {
    test('keeps the extension, lower-cased', () {
      expect(
        SoundStore.idFor('/Users/me/Sounds/Applause.MP3', 42),
        'snd_42.mp3',
      );
    });

    test('is null for a file without an extension', () {
      expect(SoundStore.idFor('/Users/me/Sounds/Applause', 42), isNull);
      expect(SoundStore.idFor('/Users/me/.hidden', 42), isNull);
    });

    test('is null for an extension that is not a plain short word', () {
      expect(SoundStore.idFor('/tmp/a.tar.verylong', 42), isNull);
    });
  });

  group('SoundStore.isSoundId', () {
    test('accepts what idFor hands out', () {
      expect(SoundStore.isSoundId('snd_42.mp3'), isTrue);
      expect(SoundStore.isSoundId('snd_1790000000000000.m4a'), isTrue);
    });

    test('rejects anything that could reach outside the store', () {
      // Ids arrive from the client; none of these may name a file.
      for (final id in [
        '../layout.json',
        'snd_42.mp3/../../layout.json',
        '/etc/passwd',
        'img_42',
        'snd_.mp3',
        'snd_42',
      ]) {
        expect(SoundStore.isSoundId(id), isFalse, reason: id);
      }
    });
  });

  group('SoundStore.labelFor', () {
    test('is the file name without folder or extension', () {
      expect(SoundStore.labelFor('/Users/me/Sounds/Applause.mp3'), 'Applause');
      expect(SoundStore.labelFor('Drum roll.wav'), 'Drum roll');
    });
  });
}
