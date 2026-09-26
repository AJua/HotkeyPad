import 'dart:convert';

import 'package:http/http.dart' as http;

/// Where the host looks for its own newer versions — see
/// `.github/workflows/release-host.yml`, which publishes one release per
/// host version under a `host-vX.Y.Z` tag.
///
/// The full list rather than `/releases/latest`: that endpoint skips
/// pre-releases (which every host release is published as) and cannot
/// tell a host release from a `client-v*` one sharing the same repo.
const _releasesUrl =
    'https://api.github.com/repos/AJua/HotkeyPad/releases?per_page=30';

/// The tag prefix of a host release, as opposed to a client one.
const _hostTagPrefix = 'host-v';

/// What this app cares about from a GitHub release — deliberately not the
/// raw JSON shape, so callers and tests don't need to know GitHub's field
/// names.
class LatestRelease {
  const LatestRelease({
    required this.version,
    required this.htmlUrl,
    this.macosAssetUrl,
    this.windowsAssetUrl,
  });

  /// The release's tag with its `host-v`/`v` prefix stripped, e.g. `1.2.0`.
  final String version;

  /// The release's own page, to open in a browser.
  final String htmlUrl;

  /// Download URL of the release's macOS `.dmg`, if it has one.
  final String? macosAssetUrl;

  /// Download URL of the release's Windows `.zip`, if it has one.
  final String? windowsAssetUrl;

  @override
  String toString() => 'LatestRelease($version, $htmlUrl)';
}

/// Pure — parses one release object from GitHub's releases API. No
/// network, no I/O, fully testable with a plain Map literal.
///
/// Returns null for anything that doesn't look like a real release
/// response — the same "degrade quietly" stance every other optional
/// feature in this codebase takes (see e.g. `ClientTrustStore.load`).
LatestRelease? parseLatestRelease(Map<String, dynamic> json) {
  final tag = json['tag_name'];
  final url = json['html_url'];
  if (tag is! String || tag.isEmpty) return null;
  if (url is! String || url.isEmpty) return null;
  final version = tag.startsWith(_hostTagPrefix)
      ? tag.substring(_hostTagPrefix.length)
      : tag.startsWith('v')
      ? tag.substring(1)
      : tag;
  if (version.isEmpty) return null;
  String? macos;
  String? windows;
  final assets = json['assets'];
  if (assets is List) {
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = asset['name'];
      final download = asset['browser_download_url'];
      if (name is! String || download is! String) continue;
      if (name.endsWith('.dmg')) macos ??= download;
      if (name.endsWith('-windows.zip')) windows ??= download;
    }
  }
  return LatestRelease(
    version: version,
    htmlUrl: url,
    macosAssetUrl: macos,
    windowsAssetUrl: windows,
  );
}

/// Pure — the newest host release in the body of GitHub's release list,
/// or null if there is none.
///
/// Only `host-v*` tags count: the repo also publishes `client-v*` releases,
/// whose versions have nothing to do with this app's. Drafts are skipped;
/// pre-releases are not, since every host release is published as one.
LatestRelease? parseNewestHostRelease(List<dynamic> json) {
  LatestRelease? newest;
  for (final entry in json) {
    if (entry is! Map<String, dynamic>) continue;
    if (entry['draft'] == true) continue;
    final tag = entry['tag_name'];
    if (tag is! String || !tag.startsWith(_hostTagPrefix)) continue;
    final release = parseLatestRelease(entry);
    if (release == null) continue;
    if (newest == null || isNewerVersion(newest.version, release.version)) {
      newest = release;
    }
  }
  return newest;
}

/// Pure — semver-ish comparison, tolerant of a leading 'v' on either
/// side and of mismatched segment counts (a missing trailing segment
/// counts as 0, so `1.2` is treated the same as `1.2.0`).
///
/// Malformed input (anything a segment can't parse as a non-negative
/// integer) returns false rather than throwing — an update check that
/// can't make sense of a version string should stay quiet, not crash.
bool isNewerVersion(String current, String latest) {
  final c = _segments(current);
  final l = _segments(latest);
  if (c == null || l == null) return false;
  for (var i = 0; i < c.length || i < l.length; i++) {
    final cv = i < c.length ? c[i] : 0;
    final lv = i < l.length ? l[i] : 0;
    if (lv != cv) return lv > cv;
  }
  return false;
}

List<int>? _segments(String version) {
  final stripped = version.startsWith('v') ? version.substring(1) : version;
  if (stripped.isEmpty) return null;
  final parts = stripped.split('.');
  final result = <int>[];
  for (final part in parts) {
    final n = int.tryParse(part);
    if (n == null || n < 0) return null;
    result.add(n);
  }
  return result;
}

/// Checks GitHub for the latest published `hotkeypad_host` release.
abstract final class UpdateChecker {
  /// The newest host release — see [parseNewestHostRelease].
  ///
  /// Never throws: network errors, timeouts, non-200 responses, and
  /// malformed JSON all collapse to null. An update notice is a nice-to-
  /// have — losing it silently beats surfacing a network error to
  /// someone who just wants to press a button on their deck.
  static Future<LatestRelease?> fetchLatest({
    http.Client? client,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final http.Client c = client ?? http.Client();
    try {
      final response = await c
          .get(
            Uri.parse(_releasesUrl),
            headers: const {'Accept': 'application/vnd.github+json'},
          )
          .timeout(timeout);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! List<dynamic>) return null;
      return parseNewestHostRelease(decoded);
    } catch (_) {
      return null;
    } finally {
      if (client == null) c.close();
    }
  }
}
