import 'package:shared_preferences/shared_preferences.dart';

/// Persists which apps a user put on the deck, per host.
///
/// Keyed by the host's peripheral UUID so two hosts do not share a layout.
/// The deck is drawn from this, not from the host's catalogue, so it is
/// usable the moment the app opens rather than after the catalogue arrives.
abstract final class DeckStore {
  static String _key(String hostId) => 'deck:$hostId';

  /// Always returns a list the caller may mutate: the stored value and the
  /// empty fallback are both unmodifiable, and the session edits this in
  /// place.
  static Future<List<String>> load(String hostId) async {
    final prefs = await SharedPreferences.getInstance();
    return List.of(prefs.getStringList(_key(hostId)) ?? const []);
  }

  /// Applies a drag from [oldIndex] to [newIndex].
  ///
  /// ReorderableList reports the target as if the dragged item were still in
  /// place, so a downward drag is one too high. Pure so the off-by-one is
  /// testable without a widget tree.
  static List<T> reordered<T>(List<T> items, int oldIndex, int newIndex) {
    final copy = List.of(items);
    if (newIndex > oldIndex) newIndex -= 1;
    copy.insert(newIndex, copy.removeAt(oldIndex));
    return copy;
  }

  static Future<void> save(String hostId, List<String> appNames) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key(hostId), appNames);
  }
}
