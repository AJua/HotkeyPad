import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'custom_icon_store.dart';
import 'image_decode.dart';

/// A custom background image the user has picked for the deck screen
/// itself, as opposed to one button's own icon (see [CustomIconStore]).
///
/// Stored the same way a custom icon is — one file per generated id, read
/// back and sent over the link by id — except a background fills the whole
/// (non-square) screen, so it needs neither the crop to a centred square nor
/// the rounded-corner clip [CustomIconStore.cropToSquarePng] applies: those
/// exist only because deck buttons are square. All this does is cap the
/// resolution, so a multi-megapixel photo does not cost far more BLE frames
/// than the phone screen it is drawn on could ever show.
abstract final class BackgroundImageStore {
  /// Comfortably above any phone's screen resolution in either dimension,
  /// so downscaling never softens the image, while still keeping a huge
  /// source photo from ballooning the transfer over BLE for no visible
  /// benefit.
  static const _defaultMaxDimension = 2000;

  /// The native picker is the same one [CustomIconStore] uses, and shares
  /// its platform gap.
  static bool get supported => CustomIconStore.supported;

  static Directory? get _directory {
    if (kIsWeb) return null;
    final home = Platform.environment['HOME'];
    if (home == null) return null;
    return Directory('$home/.config/HotkeyPad/backgrounds');
  }

  static String _fileName(String id) => '$id.png';

  /// Opens the native file picker (shared with [CustomIconStore]) and, if
  /// the user picked something, downscales it. Returns null if the user
  /// cancelled, the platform is unsupported, or the file could not be
  /// decoded as an image.
  static Future<Uint8List?> pickAndProcess() async {
    final picked = await CustomIconStore.pickRaw();
    if (picked == null) return null;
    return downscale(picked);
  }

  /// Decodes [bytes] (see [ImageDecode]) and, if either dimension exceeds
  /// [maxDimension], scales it down preserving aspect ratio; re-encodes as
  /// PNG either way, so the stored file is always in a format [read]'s
  /// callers can hand straight to `Image.memory`. Returns null if [bytes]
  /// cannot be decoded.
  ///
  /// Public, not an implementation detail of [pickAndProcess], so it can be
  /// tested directly against synthetic images without a real file picker —
  /// the same reason [CustomIconStore.cropToSquarePng] is public.
  static Future<Uint8List?> downscale(
    Uint8List bytes, {
    int maxDimension = _defaultMaxDimension,
  }) async {
    final Image source;
    try {
      source = await ImageDecode.decodeAny(bytes);
    } catch (_) {
      return null;
    }
    try {
      final largest = source.width > source.height
          ? source.width
          : source.height;
      final scale = largest > maxDimension ? maxDimension / largest : 1.0;
      final width = (source.width * scale).round().clamp(1, maxDimension);
      final height = (source.height * scale).round().clamp(1, maxDimension);

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        source,
        Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final picture = recorder.endRecording();
      try {
        final output = await picture.toImage(width, height);
        try {
          final data = await output.toByteData(format: ImageByteFormat.png);
          return data?.buffer.asUint8List();
        } finally {
          output.dispose();
        }
      } finally {
        picture.dispose();
      }
    } finally {
      source.dispose();
    }
  }

  /// Saves [png] under a freshly generated id and returns it, or null if it
  /// could not be written. Prefixed distinctly from [CustomIconStore]'s
  /// `img_` ids purely for readability in logs and on disk — both id
  /// spaces are already namespaced into separate directories, so nothing
  /// depends on the prefix to avoid a collision.
  static Future<String?> save(Uint8List png) async {
    final directory = _directory;
    if (directory == null) return null;
    final id = 'bg_${DateTime.now().microsecondsSinceEpoch}';
    try {
      await directory.create(recursive: true);
      await File(
        '${directory.path}/${_fileName(id)}',
      ).writeAsBytes(png, flush: true);
      return id;
    } on FileSystemException {
      return null;
    }
  }

  static Future<Uint8List?> read(String id) async {
    final directory = _directory;
    if (directory == null) return null;
    final file = File('${directory.path}/${_fileName(id)}');
    try {
      if (!file.existsSync()) return null;
      return await file.readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  /// Best-effort: a file that fails to delete just outlives the setting
  /// that used it, which costs disk space rather than correctness.
  static Future<void> delete(String id) async {
    final directory = _directory;
    if (directory == null) return;
    try {
      final file = File('${directory.path}/${_fileName(id)}');
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // Ignored, as above.
    }
  }
}
