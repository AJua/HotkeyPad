import 'dart:convert';
import 'dart:typed_data';

import 'package:bt_host/src/backup_bundle.dart';
import 'package:bt_link_protocol/bt_link_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

DeckLayout _layoutWith(List<DeckItem?> items) {
  final layout = DeckLayout.empty(columns: items.length, rows: 1, pages: 1);
  var result = layout;
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    if (item != null) result = result.withSlot(i, item.stored);
  }
  return result;
}

void main() {
  group('customIconIdsReferencedBy', () {
    test('an empty layout references nothing', () {
      expect(customIconIdsReferencedBy(DeckLayout.empty()), isEmpty);
    });

    test('collects the customIconId of a plain item', () {
      final layout = _layoutWith([
        const AppItem('Safari', customIconId: 'img_1'),
        const ActionItem(DeckAction.mute, customIconId: 'img_2'),
      ]);

      expect(customIconIdsReferencedBy(layout), {'img_1', 'img_2'});
    });

    test('ignores an item with no custom icon', () {
      final layout = _layoutWith([const AppItem('Safari')]);

      expect(customIconIdsReferencedBy(layout), isEmpty);
    });

    test('the same id used twice is reported once', () {
      final layout = _layoutWith([
        const AppItem('Safari', customIconId: 'img_1'),
        const AppItem('Chrome', customIconId: 'img_1'),
      ]);

      expect(customIconIdsReferencedBy(layout), {'img_1'});
    });

    test('recurses into a combo step to find its own custom icon', () {
      final combo = ComboItem(
        steps: const [
          ComboStep(
            action: AppItem('Safari', customIconId: 'step_icon'),
            delayMs: 0,
          ),
          ComboStep(action: AppItem('Chrome'), delayMs: 500),
        ],
        label: 'Browsers',
        customIconId: 'combo_icon',
      );
      final layout = _layoutWith([combo]);

      expect(
        customIconIdsReferencedBy(layout),
        {'combo_icon', 'step_icon'},
      );
    });

    test('a slot this build cannot parse contributes nothing', () {
      final layout = DeckLayout.empty().withSlot(0, '{not valid json');

      expect(customIconIdsReferencedBy(layout), isEmpty);
    });
  });

  group('backupBundleToJson / backupBundleFromJson', () {
    BackupBundle sample() => BackupBundle(
      theme: DeckTheme.dark,
      showLabels: false,
      layout: _layoutWith([
        const AppItem('Safari', customIconId: 'img_1'),
      ]),
      customIcons: {
        'img_1': Uint8List.fromList([1, 2, 3, 4]),
      },
    );

    test('round-trips theme, showLabels, layout and icon bytes', () {
      final json = backupBundleToJson(sample());
      final restored = backupBundleFromJson(json)!;

      expect(restored.theme, DeckTheme.dark);
      expect(restored.showLabels, isFalse);
      expect(restored.layout.columns, 1);
      expect(restored.layout.slots[0]?.value, const AppItem('Safari', customIconId: 'img_1').stored);
      expect(restored.customIcons['img_1'], [1, 2, 3, 4]);
    });

    test('encodes icon bytes as base64, not raw bytes, in the JSON map', () {
      final json = backupBundleToJson(sample());

      expect(json['customIcons'], {'img_1': base64Encode([1, 2, 3, 4])});
    });

    test('round-trips through actual JSON text via encode/decode', () {
      final bytes = encodeBackupBundle(sample());
      final restored = decodeBackupBundle(bytes)!;

      expect(restored.theme, DeckTheme.dark);
      expect(restored.customIcons['img_1'], [1, 2, 3, 4]);
    });

    test('a plain map missing layout is rejected', () {
      expect(backupBundleFromJson({'theme': 'dark'}), isNull);
    });

    test('anything that is not a map is rejected', () {
      expect(backupBundleFromJson('not a bundle'), isNull);
      expect(backupBundleFromJson(null), isNull);
    });

    test('malformed bytes are rejected rather than throwing', () {
      expect(decodeBackupBundle(Uint8List.fromList([0xff, 0xfe, 0x00])), isNull);
    });

    test('a bundle from a future format version is rejected', () {
      final json = backupBundleToJson(sample());
      json['formatVersion'] = backupFormatVersion + 1;

      expect(backupBundleFromJson(json), isNull);
    });

    test('a bundle with no formatVersion field is still accepted', () {
      final json = backupBundleToJson(sample());
      json.remove('formatVersion');

      expect(backupBundleFromJson(json), isNotNull);
    });

    test('a corrupt individual icon is dropped, not fatal to the import', () {
      final json = backupBundleToJson(sample());
      (json['customIcons'] as Map)['img_1'] = 'not valid base64!!';

      final restored = backupBundleFromJson(json)!;

      expect(restored.customIcons, isEmpty);
    });

    test('a missing customIcons map just means no icons', () {
      final json = backupBundleToJson(sample());
      json.remove('customIcons');

      final restored = backupBundleFromJson(json)!;

      expect(restored.customIcons, isEmpty);
    });

    test('an unparseable theme falls back to system', () {
      final json = backupBundleToJson(sample());
      json['theme'] = 'not-a-real-theme';

      expect(backupBundleFromJson(json)!.theme, DeckTheme.system);
    });
  });

  group('backupSuggestedFileName', () {
    test('formats as a sortable, zero-padded date', () {
      expect(
        backupSuggestedFileName(DateTime(2026, 1, 5)),
        'BTLink-backup-2026-01-05.json',
      );
    });

    test('does not pad the year', () {
      expect(
        backupSuggestedFileName(DateTime(2026, 12, 31)),
        'BTLink-backup-2026-12-31.json',
      );
    });
  });
}
