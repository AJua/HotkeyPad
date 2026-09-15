import 'package:flutter/widgets.dart' show BoxFit;

import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';

/// Maps the wire-level [BackgroundFit] to Flutter's own [BoxFit].
///
/// Kept out of hotkeypad_protocol, which otherwise depends only on
/// `dart:convert`/`dart:typed_data` and the BLE plugin, not on Flutter's
/// widget library — the host never paints anything with this value, only
/// the client does.
BoxFit boxFitFor(BackgroundFit fit) => switch (fit) {
  BackgroundFit.cover => BoxFit.cover,
  BackgroundFit.contain => BoxFit.contain,
  BackgroundFit.stretch => BoxFit.fill,
};
