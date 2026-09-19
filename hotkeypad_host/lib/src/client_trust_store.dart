import 'dart:convert';
import 'dart:io';

import 'config_dir.dart';

/// Whether a client — identified by its `Hello.clientId`, which survives a
/// reconnect on either transport — should be let through without asking,
/// given what the host already knows about it.
enum ClientTrust { trusted, blocked, unknown }

/// Pure lookup, pulled out of [ClientTrustStore] so the decision itself is
/// testable without touching a file — the same reason `host_page.dart`'s
/// `isPressAllowed`/`nextLockedClientId` are standalone functions.
ClientTrust trustFor(String clientId, Map<String, bool> known) {
  final trusted = known[clientId];
  if (trusted == null) return ClientTrust.unknown;
  return trusted ? ClientTrust.trusted : ClientTrust.blocked;
}

/// Persists every trust-on-first-use decision the host has made about a
/// client, so a device is asked about at most once — regardless of whether
/// it reached the host over WiFi or Bluetooth. Both transports funnel
/// through the same PIN challenge (see `host_page.dart`'s `_onHello`), so
/// there is exactly one file and one decision per `Hello.clientId`, not a
/// separate copy per transport.
///
/// Kept in its own file for the same reason `settings.json`/`layout.json`
/// are separate: nothing else should be able to clobber it by writing a
/// different concern back out.
abstract final class ClientTrustStore {
  static File? get _file {
    final dir = ConfigDir.path;
    if (dir == null) return null;
    // Still named after WiFi, which is all this covered before Bluetooth
    // grew the same PIN challenge — renaming the on-disk file would just
    // orphan everyone's existing trust decisions for no benefit, since
    // nothing outside this class reads the filename itself.
    return File('$dir/wifi_trust.json');
  }

  /// clientId -> trusted (`true`) or blocked (`false`). An id absent from
  /// the map has never been decided on.
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
  /// callers keep their own in-memory copy (`_HostPageState._trust`) up to
  /// date themselves rather than re-reading after every write.
  static Future<void> setDecision(String clientId, bool trusted) async {
    final file = _file;
    if (file == null) return;
    try {
      final current = await load();
      current[clientId] = trusted;
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
  static Future<void> forget(String clientId) async {
    final file = _file;
    if (file == null) return;
    try {
      final current = await load();
      if (current.remove(clientId) == null) return;
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(current), flush: true);
    } on FileSystemException {
      // As above.
    }
  }
}
