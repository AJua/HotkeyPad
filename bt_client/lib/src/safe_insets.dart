import 'package:flutter/material.dart';

/// Padding that keeps scrollable content clear of the notch and the home
/// indicator.
///
/// `Scaffold` insets its app bar for the display cutout but not its body, so
/// in landscape — where the cutout sits on one side — the first and last
/// columns of a grid end up underneath it.
///
/// Applied as scroll-view padding rather than by wrapping in `SafeArea` so
/// content still scrolls through the inset area instead of being clipped
/// short of it.
EdgeInsets safeScrollPadding(
  BuildContext context, {
  double horizontal = 0,
  double vertical = 0,
}) {
  final insets = MediaQuery.paddingOf(context);
  return EdgeInsets.fromLTRB(
    horizontal + insets.left,
    vertical,
    horizontal + insets.right,
    vertical + insets.bottom,
  );
}
