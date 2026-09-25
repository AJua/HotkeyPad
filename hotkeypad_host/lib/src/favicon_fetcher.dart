import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'custom_icon_store.dart';

/// Fetches a site's icon to use as an "open URL" button's icon, so a new
/// button shows the site's own logo instead of a generic glyph.
abstract final class FaviconFetcher {
  /// Where to look for [url]'s icon, best first, at the root of its host
  /// over the same scheme: `/apple-touch-icon.png` (usually 180px, sharp on
  /// a deck button) before `/favicon.ico` (often only 16-32px, blurry once
  /// scaled up). A bare address like `www.google.com`, which the URL dialog
  /// accepts, is taken as https. Empty when there is no host to ask, or the
  /// scheme is not a web one (`file:`, `mailto:`, ...).
  static List<Uri> iconUris(String url) {
    final root = _root(url);
    if (root == null) return const [];
    return [
      root.replace(path: '/apple-touch-icon.png'),
      root.replace(path: '/favicon.ico'),
    ];
  }

  static Uri? _root(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    // `mailto:x@y.z` names a scheme too, just without `//`; only something
    // with no scheme at all is a bare host. A colon followed by digits is a
    // port (`localhost:8080`), not a scheme.
    final hasScheme =
        trimmed.contains('://') ||
        RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:(?!\d)').hasMatch(trimmed);
    final Uri parsed;
    try {
      parsed = Uri.parse(hasScheme ? trimmed : 'https://$trimmed');
    } on FormatException {
      return null;
    }
    if (parsed.scheme != 'http' && parsed.scheme != 'https') return null;
    if (parsed.host.isEmpty) return null;
    return Uri(
      scheme: parsed.scheme,
      host: parsed.host,
      port: parsed.hasPort ? parsed.port : null,
    );
  }

  /// Downloads the first of [iconUris] that serves a decodable image and
  /// processes it the same way a picked image is (see
  /// [CustomIconStore.cropToSquarePng]) — a logo on a transparent background
  /// lands on a white plate, an opaque one fills the button. Returns the PNG
  /// ready for [CustomIconStore.save].
  ///
  /// Never throws: no host, a network error, a timeout, a non-200 response,
  /// or bytes that do not decode as an image all move on to the next
  /// candidate, and running out of them is null. A missing icon just means
  /// the button keeps its default one.
  static Future<Uint8List?> fetchIconPng(
    String url, {
    http.Client? client,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final uris = iconUris(url);
    if (uris.isEmpty) return null;
    final http.Client c = client ?? http.Client();
    try {
      for (final uri in uris) {
        try {
          final response = await c.get(uri).timeout(timeout);
          if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
            continue;
          }
          final png = await CustomIconStore.cropToSquarePng(response.bodyBytes);
          if (png != null) return png;
        } catch (_) {
          continue;
        }
      }
      return null;
    } finally {
      if (client == null) c.close();
    }
  }
}
