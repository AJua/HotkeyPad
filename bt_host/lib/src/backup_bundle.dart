import 'dart:convert';
import 'dart:typed_data';

import 'package:bt_link_protocol/bt_link_protocol.dart';

/// Bumped only if the bundle's shape changes in a way an older build could
/// not read back safely. [backupBundleFromJson] already tolerates missing
/// fields on its own — the same tolerance [DeckLayout.fromJson] shows for a
/// layout written before pages existed — so this only matters for a change
/// too large for field-by-field tolerance to cover.
const backupFormatVersion = 1;

/// One self-contained snapshot of everything the host persists: the
/// [DeckTheme]/showLabels pair `settings.json` holds, the [DeckLayout]
/// `layout.json` holds, and the raw PNG bytes of every custom icon that
/// layout still points at (see [customIconIdsReferencedBy]) — small and
/// self-contained enough to hand someone as a single file, rather than the
/// folder of three independent stores it is assembled from.
class BackupBundle {
  const BackupBundle({
    required this.theme,
    required this.showLabels,
    required this.layout,
    required this.customIcons,
  });

  final DeckTheme theme;
  final bool showLabels;
  final DeckLayout layout;

  /// Keyed by the same id [DeckItem.customIconId] carries, so restoring a
  /// bundle can write each PNG back under the exact id the layout already
  /// expects, rather than minting fresh ids and having to rewrite the
  /// layout to match them.
  final Map<String, Uint8List> customIcons;
}

/// The [DeckItem.customIconId]s a layout actually needs, walked out of
/// every occupied slot — recursing into a [ComboItem]'s own steps, since
/// each step is composed from the same picker as a top-level button and can
/// carry a custom icon of its own.
///
/// A pure function of [layout], so an export ships exactly the icons the
/// layout uses rather than the whole `custom_icons/` directory, which may
/// hold files nothing points at any more (see [CustomIconStore.delete]'s
/// own doc comment on why an orphan can outlive the button that used it).
Set<String> customIconIdsReferencedBy(DeckLayout layout) {
  final ids = <String>{};
  void visit(DeckItem? item) {
    if (item == null) return;
    final id = item.customIconId;
    if (id != null) ids.add(id);
    // Steps can't nest a combo inside a combo (see ComboStep.fromJson), so
    // one extra level of recursion is always enough.
    if (item is ComboItem) {
      for (final step in item.steps) {
        visit(step.action);
      }
    }
  }

  for (final slot in layout.slots) {
    if (slot != null) visit(DeckItem.parse(slot.value));
  }
  return ids;
}

/// Renders [bundle] as the JSON map written to a backup file. Kept apart
/// from any actual file write — a pure counterpart to
/// [backupBundleFromJson] — so the exact shape on the wire can be asserted
/// in a test without touching disk.
Map<String, Object?> backupBundleToJson(BackupBundle bundle) => {
  'formatVersion': backupFormatVersion,
  'theme': bundle.theme.wire,
  'showLabels': bundle.showLabels,
  'layout': bundle.layout.toJson(),
  'customIcons': {
    for (final entry in bundle.customIcons.entries)
      entry.key: base64Encode(entry.value),
  },
};

/// Parses [json] back into a [BackupBundle], or null for anything that does
/// not look like one: a foreign file, a hand-edited one missing a required
/// field, or one written by a future, incompatible [backupFormatVersion]
/// this build does not know how to read. A malformed individual custom icon
/// is dropped rather than failing the whole import over one bad entry — the
/// same stance [DeckItem.parse] takes on a slot it cannot make sense of.
BackupBundle? backupBundleFromJson(Object? json) {
  if (json is! Map) return null;
  final version = json['formatVersion'];
  if (version is int && version > backupFormatVersion) return null;
  final layout = DeckLayout.fromJson(json['layout']);
  if (layout == null) return null;
  final icons = <String, Uint8List>{};
  final rawIcons = json['customIcons'];
  if (rawIcons is Map) {
    for (final entry in rawIcons.entries) {
      final id = entry.key;
      final data = entry.value;
      if (id is! String || data is! String) continue;
      try {
        icons[id] = base64Decode(data);
      } catch (_) {
        // Skip this one icon; the rest of the bundle is still usable.
      }
    }
  }
  return BackupBundle(
    theme: DeckTheme.fromWire(json['theme'] as String?),
    showLabels: json['showLabels'] as bool? ?? true,
    layout: layout,
    customIcons: icons,
  );
}

/// Encodes [bundle] as the bytes written to a backup file.
Uint8List encodeBackupBundle(BackupBundle bundle) =>
    Uint8List.fromList(utf8.encode(jsonEncode(backupBundleToJson(bundle))));

/// The inverse of [encodeBackupBundle]. Null for anything that is not valid
/// UTF-8 JSON shaped like a backup, so a corrupt or unrelated file is
/// reported as invalid rather than throwing.
BackupBundle? decodeBackupBundle(Uint8List bytes) {
  try {
    return backupBundleFromJson(jsonDecode(utf8.decode(bytes)));
  } catch (_) {
    return null;
  }
}

/// A default file name for the Save panel: stable and sortable so several
/// backups taken over time still list in order, and immediately
/// recognisable as this app's own.
String backupSuggestedFileName(DateTime time) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'BTLink-backup-${time.year}-${two(time.month)}-${two(time.day)}.json';
}
