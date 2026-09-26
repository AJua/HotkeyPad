import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'update_checker.dart';

/// Downloads a newer host release and swaps it in for the running app.
///
/// The swap itself cannot happen from inside the app it replaces, so the
/// new build is staged next to the current one first — which also proves
/// the install location is writable before anything irreversible happens
/// — and a small detached script finishes the job once this process has
/// quit: it waits for the old process to exit, moves the new build into
/// place, and relaunches it.
abstract final class UpdateInstaller {
  /// Only a real release build replaces itself: a debug run lives under
  /// `build/` and has nothing sensible to be replaced with.
  static bool get supported =>
      kReleaseMode && !kIsWeb && (Platform.isMacOS || Platform.isWindows);

  /// Downloads and stages [release], then starts the swap script and quits
  /// the app. Only returns by throwing — [UpdateInstallException] for
  /// anything that went wrong before the app quit, which leaves the
  /// current install untouched.
  static Future<Never> install(
    LatestRelease release, {
    ValueChanged<double?>? onProgress,
  }) async {
    final url = assetUrlFor(
      release,
      isMacOS: Platform.isMacOS,
      isWindows: Platform.isWindows,
    );
    if (url == null) {
      throw const UpdateInstallException('No download for this platform');
    }
    final work = await Directory.systemTemp.createTemp('hotkeypad_update_');
    final download = File(
      '${work.path}${Platform.pathSeparator}${Uri.parse(url).pathSegments.last}',
    );
    await _download(Uri.parse(url), download, onProgress);
    onProgress?.call(null);

    final String script;
    if (Platform.isMacOS) {
      script = await _stageMacOS(download, work);
    } else {
      script = await _stageWindows(download, work);
    }
    if (Platform.isMacOS) {
      await Process.start('/bin/sh', [script], mode: ProcessStartMode.detached);
    } else {
      await Process.start('cmd', [
        '/c',
        script,
      ], mode: ProcessStartMode.detached);
    }
    exit(0);
  }

  static Future<void> _download(
    Uri url,
    File target,
    ValueChanged<double?>? onProgress,
  ) async {
    final client = http.Client();
    try {
      final response = await client.send(http.Request('GET', url));
      if (response.statusCode != 200) {
        throw UpdateInstallException(
          'Download failed (${response.statusCode})',
        );
      }
      final total = response.contentLength;
      var received = 0;
      final sink = target.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total != null && total > 0) onProgress?.call(received / total);
        }
      } finally {
        await sink.close();
      }
    } on UpdateInstallException {
      rethrow;
    } catch (error) {
      throw UpdateInstallException('Download failed: $error');
    } finally {
      client.close();
    }
  }

  /// Mounts the downloaded `.dmg`, copies its app next to the running one
  /// as a hidden `.update` sibling, and writes the swap script.
  static Future<String> _stageMacOS(File dmg, Directory work) async {
    final bundle = macAppBundlePath(Platform.resolvedExecutable);
    if (bundle == null) {
      throw const UpdateInstallException('Not running from an .app bundle');
    }
    final mount = '${work.path}/mount';
    await _run('hdiutil', [
      'attach',
      '-nobrowse',
      '-readonly',
      '-noautoopen',
      '-mountpoint',
      mount,
      dmg.path,
    ]);
    final staged = macStagedPath(bundle);
    try {
      final app = Directory(mount)
          .listSync()
          .whereType<Directory>()
          .where((entry) => entry.path.endsWith('.app'))
          .firstOrNull;
      if (app == null) {
        throw const UpdateInstallException('No app inside the download');
      }
      // Left behind by an earlier update that never finished.
      final leftover = Directory(staged);
      if (leftover.existsSync()) await leftover.delete(recursive: true);
      await _run('ditto', [app.path, staged]);
    } finally {
      await Process.run('hdiutil', ['detach', mount, '-quiet']);
    }
    final script = File('${work.path}/install.sh');
    await script.writeAsString(
      macInstallScript(
        pid: pid,
        bundle: bundle,
        staged: staged,
        workDir: work.path,
      ),
    );
    return script.path;
  }

  /// Extracts the downloaded `.zip` and writes the swap script. The copy
  /// into the install folder has to wait for this process to exit — its
  /// files are locked while it runs — so writability is checked here with
  /// a probe file instead.
  static Future<String> _stageWindows(File zip, Directory work) async {
    final executable = File(Platform.resolvedExecutable);
    final installDir = executable.parent.path;
    final probe = File('$installDir\\.hotkeypad_update_probe');
    try {
      await probe.writeAsString('');
      await probe.delete();
    } on FileSystemException {
      throw UpdateInstallException('Cannot write to $installDir');
    }
    final staged = '${work.path}\\staged';
    await _run('powershell', [
      '-NoProfile',
      '-Command',
      'Expand-Archive -LiteralPath ${powershellQuote(zip.path)} '
          '-DestinationPath ${powershellQuote(staged)} -Force',
    ]);
    final script = File('${work.path}\\install.cmd');
    await script.writeAsString(
      windowsInstallScript(
        pid: pid,
        installDir: installDir,
        executable: executable.path,
        staged: staged,
        workDir: work.path,
      ),
    );
    return script.path;
  }

  static Future<void> _run(String executable, List<String> arguments) async {
    final result = await Process.run(executable, arguments);
    if (result.exitCode != 0) {
      throw UpdateInstallException(
        '$executable failed: ${'${result.stderr}'.trim()}',
      );
    }
  }
}

/// Anything that stopped an update before the app quit — the current
/// install is still in place and still running.
class UpdateInstallException implements Exception {
  const UpdateInstallException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Pure — the download for the platform this is running on, or null if
/// [release] has none for it.
String? assetUrlFor(
  LatestRelease release, {
  required bool isMacOS,
  required bool isWindows,
}) {
  if (isMacOS) return release.macosAssetUrl;
  if (isWindows) return release.windowsAssetUrl;
  return null;
}

/// Pure — the `.app` bundle an executable at [executable] lives in
/// (`…/X.app/Contents/MacOS/X` → `…/X.app`), or null if it is not inside
/// one.
String? macAppBundlePath(String executable) {
  const marker = '.app/Contents/MacOS/';
  final index = executable.lastIndexOf(marker);
  if (index < 0) return null;
  return executable.substring(0, index + '.app'.length);
}

/// Pure — where the new build is staged: a hidden sibling of [bundle], on
/// the same volume so the final swap is a rename rather than a copy.
String macStagedPath(String bundle) {
  final slash = bundle.lastIndexOf('/');
  return '${bundle.substring(0, slash + 1)}.${bundle.substring(slash + 1)}.update';
}

/// Pure — [value] as a single-quoted POSIX shell word.
String shellQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";

/// Pure — [value] as a single-quoted PowerShell string.
String powershellQuote(String value) => "'${value.replaceAll("'", "''")}'";

/// Pure — the script that swaps [staged] in for [bundle] once process
/// [pid] has exited, then relaunches it. The old bundle is moved aside
/// rather than deleted first, and put back if the new one cannot be moved
/// into place, so a failure never leaves no app at all.
String macInstallScript({
  required int pid,
  required String bundle,
  required String staged,
  required String workDir,
}) {
  final b = shellQuote(bundle);
  final s = shellQuote(staged);
  final old = shellQuote('$bundle.old');
  return '''
#!/bin/sh
while kill -0 $pid 2>/dev/null; do sleep 0.2; done
rm -rf $old
if mv $b $old; then
  if mv $s $b; then
    rm -rf $old
  else
    mv $old $b
  fi
fi
open $b
rm -rf ${shellQuote(workDir)}
''';
}

/// Pure — the Windows counterpart of [macInstallScript]: waits for [pid]
/// to exit, copies [staged] over [installDir], and relaunches
/// [executable]. Relaunches even if the copy failed, so a failed update
/// still leaves the old version running rather than nothing.
String windowsInstallScript({
  required int pid,
  required String installDir,
  required String executable,
  required String staged,
  required String workDir,
}) {
  return '''
@echo off
:wait
tasklist /FI "PID eq $pid" /NH | find "$pid" >NUL && (timeout /t 1 /nobreak >NUL & goto wait)
robocopy "$staged" "$installDir" /E /NFL /NDL /NJH /NJS /NP >NUL
start "" "$executable"
rmdir /S /Q "$workDir"
''';
}
