import 'dart:convert';

import 'package:http/http.dart' as http;

/// Where the host looks for its own newer versions — see the
/// `release-macos` skill, which is what actually publishes them here as
/// plain `vX.Y.Z` tags, one release per host version.
const _releasesUrl =
    'https://api.github.com/repos/AJua/HotkeyPad/releases/latest';

/// What this app cares about from a GitHub release — deliberately not the
/// raw JSON shape, so callers and tests don't need to know GitHub's field
/// names.
class LatestRelease {
  const LatestRelease({required this.version, required this.htmlUrl});

  /// The release's tag with any leading 'v' stripped, e.g. `1.2.0`.
  final String version;

  /// The release's own page, to open in a browser.
  final String htmlUrl;

  @override
  String toString() => 'LatestRelease($version, $htmlUrl)';
}

/// Pure — parses the body of GitHub's "latest release" response. No
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
  final version = tag.startsWith('v') ? tag.substring(1) : tag;
  if (version.isEmpty) return null;
  return LatestRelease(version: version, htmlUrl: url);
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
      if (decoded is! Map<String, dynamic>) return null;
      return parseLatestRelease(decoded);
    } catch (_) {
      return null;
    } finally {
      if (client == null) c.close();
    }
  }
}
