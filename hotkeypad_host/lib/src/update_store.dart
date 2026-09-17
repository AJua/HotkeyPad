import 'dart:convert';
import 'dart:io';

import 'config_dir.dart';
import 'update_checker.dart';

/// How often [shouldCheckNow] allows a real network call — once a day is
/// plenty for a desktop app someone might relaunch several times a day,
/// and keeps this nowhere near GitHub's unauthenticated rate limit
/// (60/hour/IP).
const updateCheckInterval = Duration(hours: 24);

/// What the host currently knows about updates, persisted across
/// launches.
class UpdateState {
  const UpdateState({this.lastCheckedAt, this.latest, this.dismissedVersion});

  /// When a real network check last ran — null if it never has.
  final DateTime? lastCheckedAt;

  /// The most recent release GitHub reported, cached so a relaunch
  /// inside [updateCheckInterval] can still show a banner it already
  /// knows about without hitting the network again.
  final LatestRelease? latest;

  /// The version a "close" tap last dismissed, if any.
  final String? dismissedVersion;
}

/// Pure — once-a-day throttle so a normal day of relaunches doesn't
/// re-check GitHub for zero benefit.
bool shouldCheckNow(DateTime? lastCheckedAt, DateTime now) {
  if (lastCheckedAt == null) return true;
  return now.difference(lastCheckedAt) >= updateCheckInterval;
}

/// Pure — the banner's actual visibility rule: shown unless this exact
/// version was already dismissed. A version newer than whatever was
/// dismissed clears that suppression on its own, since the two strings
/// simply won't match.
bool shouldShowBanner(String? dismissedVersion, String latestVersion) =>
    dismissedVersion != latestVersion;

/// Persists what the host knows about available updates, the same
/// `~/.config/HotkeyPad/*.json` pattern as `WifiTrustStore`/
/// `SettingsStore` — one small file, static-only class, never throws
/// outward.
abstract final class UpdateStore {
  static File? get _file {
    final dir = ConfigDir.path;
    if (dir == null) return null;
    return File('$dir/update.json');
  }

  static Future<UpdateState> load() async {
    final file = _file;
    if (file == null) return const UpdateState();
    try {
      if (!file.existsSync()) return const UpdateState();
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return const UpdateState();
      final checkedAt = decoded['lastCheckedAt'];
      final version = decoded['latestVersion'];
      final url = decoded['latestUrl'];
      return UpdateState(
        lastCheckedAt: checkedAt is String
            ? DateTime.tryParse(checkedAt)
            : null,
        latest: (version is String && url is String)
            ? LatestRelease(version: version, htmlUrl: url)
            : null,
        dismissedVersion: decoded['dismissedVersion'] is String
            ? decoded['dismissedVersion'] as String
            : null,
      );
    } catch (_) {
      return const UpdateState();
    }
  }

  /// Records the result of a real check — including a failed one
  /// ([latest] null), so a check that couldn't reach GitHub still resets
  /// the throttle clock instead of retrying on every single launch.
  /// Preserves whatever [dismissedVersion] was already on disk.
  static Future<void> recordCheck(DateTime when, LatestRelease? latest) =>
      _update((state) {
        return UpdateState(
          lastCheckedAt: when,
          latest: latest ?? state.latest,
          dismissedVersion: state.dismissedVersion,
        );
      });

  /// Records that the banner for [version] was closed.
  static Future<void> dismiss(String version) =>
      _update(
        (state) => UpdateState(
          lastCheckedAt: state.lastCheckedAt,
          latest: state.latest,
          dismissedVersion: version,
        ),
      );

  static Future<void> _update(
    UpdateState Function(UpdateState current) transform,
  ) async {
    final file = _file;
    if (file == null) return;
    try {
      final next = transform(await load());
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          if (next.lastCheckedAt != null)
            'lastCheckedAt': next.lastCheckedAt!.toIso8601String(),
          if (next.latest != null) 'latestVersion': next.latest!.version,
          if (next.latest != null) 'latestUrl': next.latest!.htmlUrl,
          if (next.dismissedVersion != null)
            'dismissedVersion': next.dismissedVersion,
        }),
        flush: true,
      );
    } on FileSystemException {
      // Losing this on disk is better than taking the app down; the
      // in-memory state the caller holds still has it for the rest of
      // this run.
    }
  }
}
