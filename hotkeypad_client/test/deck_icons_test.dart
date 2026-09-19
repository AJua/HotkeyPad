import 'package:hotkeypad_client/src/deck_icons.dart';
import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('iconKeyFor', () {
    test('an app with nothing custom is keyed by its own name', () {
      expect(iconKeyFor(const AppItem('Chrome')), 'Chrome');
    });

    test('a custom icon id wins over an app name', () {
      expect(
        iconKeyFor(const AppItem('Chrome', customIconId: 'img_1')),
        'img_1',
      );
    });

    test('an emoji wins over both a custom icon id and an app name', () {
      expect(
        iconKeyFor(const AppItem('Chrome', emoji: '🎉', customIconId: 'img_1')),
        'emoji:🎉',
      );
    });

    test('an action with nothing custom is keyed by its own wire id, not '
        'drawn as a local glyph any more', () {
      expect(iconKeyFor(const ActionItem(DeckAction.mute)), 'action:mute');
      expect(iconKeyFor(const ActionItem(DeckAction.volumeUp)), 'action:volup');
    });

    test('an action with a custom icon id is keyed by that instead', () {
      expect(
        iconKeyFor(
          const ActionItem(DeckAction.playPause, customIconId: 'img_2'),
        ),
        'img_2',
      );
    });

    test('an item with no icon of its own and no emoji has no key at all', () {
      expect(
        iconKeyFor(const ShellItem(command: 'echo hi', label: 'Hi')),
        isNull,
      );
    });
  });
}
