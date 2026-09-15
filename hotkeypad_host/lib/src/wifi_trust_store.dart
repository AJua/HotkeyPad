import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Whether a WiFi client — identified by its MAC address, see
/// `wifi_server.dart` — should be let through without asking, given what
/// the host already knows about it.
enum WifiTrust { trusted, blocked, unknown }

/// Pure lookup, pulled out of [WifiTrustStore] so the decision itself is
/// testable without touching a file — the same reason `host_page.dart`'s
/// `isPressAllowed`/`nextLockedClientId` are standalone functions.
WifiTrust wifiTrustFor(String mac, Map<String, bool> known) {
  final trusted = known[mac];
  if (trusted == null) return WifiTrust.unknown;
  return trusted ? WifiTrust.trusted : WifiTrust.blocked;
}

/// Persists every trust-on-first-use decision the host has made about a
/// WiFi client, so a device is asked about at most once.
///
/// Kept in its own file for the same reason `settings.json`/`layout.json`
/// are separate: nothing else should be able to clobber it by writing a
/// different concern back out.
abstract final class WifiTrustStore {
  static File? get _file {
    if (kIsWeb) return null;
    final home = Platform.environment['HOME'];
    if (home == null) return null;
    return File('$home/.config/HotkeyPad/wifi_trust.json');
  }

  /// mac (lowercase `xx:xx:xx:xx:xx:xx`) -> trusted (`true`) or blocked
  /// (`false`). A mac absent from the map has never been decided on.
  static Future<Map<String, bool>> load() async {
    final file = _file;
    if (file == null) return {};
    try {
      if (!file.existsSync()) return {};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return {};
      return {
        for (final entry in decoded.entries)
          if (entry.value is bool) entry.key as String: entry.value as bool,
      };
    } catch (_) {
      return {};
    }
  }

  /// Records one decision, merged into whatever is already on disk —
  /// callers keep their own in-memory copy (`_HostPageState._wifiTrust`)
  /// up to date themselves rather than re-reading after every write.
  static Future<void> setDecision(String mac, bool trusted) async {
    final file = _file;
    if (file == null) return;
    try {
      final current = await load();
      current[mac] = trusted;
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(current), flush: true);
    } on FileSystemException {
      // Losing a trust decision on disk is better than taking the app
      // down; the in-memory copy the caller keeps still has it for the
      // rest of this run.
    }
  }

  /// Removes a decision entirely, so the device is asked about again next
  /// time — the service tab's "Forget" action.
  static Future<void> forget(String mac) async {
    final file = _file;
    if (file == null) return;
    try {
      final current = await load();
      if (current.remove(mac) == null) return;
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(current), flush: true);
    } on FileSystemException {
      // As above.
    }
  }
}
