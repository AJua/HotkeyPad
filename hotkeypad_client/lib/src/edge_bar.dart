import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Which edge the app bar sits on.
enum BarSide { top, left, right }

/// Where the bar belongs for the current rotation.
///
/// Flutter reports only portrait or landscape, never which way the device was
/// turned, so the side is inferred from where the system insets moved to.
/// Which edge that implies depends on what produces the inset:
///
/// * On Android the horizontal inset is the navigation bar, which lives at
///   the bottom when upright. Turning the phone anticlockwise swings the
///   bottom to the right, so the old top — and the app bar with it — is on
///   the **opposite** side.
/// * On iOS it is the notch, which lives at the top, so the app bar belongs
///   on the **same** side.
///
/// A device reporting no horizontal inset at all — gesture navigation and no
/// cutout — leaves nothing to infer from, so the bar defaults to the left.
BarSide barSideFor(BuildContext context) {
  if (MediaQuery.orientationOf(context) == Orientation.portrait) {
    return BarSide.top;
  }
  final insets = MediaQuery.viewPaddingOf(context);
  if (insets.left == insets.right) return BarSide.left;

  final insetOnRight = insets.right > insets.left;
  final topIsOnLeft = defaultTargetPlatform == TargetPlatform.iOS
      ? !insetOnRight
      : insetOnRight;
  return topIsOnLeft ? BarSide.left : BarSide.right;
}

/// An app bar that can live on any of three edges, so it stays on the same
/// physical edge of the phone as it is rotated.
class EdgeBarScaffold extends StatelessWidget {
  const EdgeBarScaffold({
    super.key,
    required this.side,
    required this.title,
    required this.actions,
    required this.child,
    this.leading,
  });

  final BarSide side;
  final String title;
  final List<Widget> actions;
  final Widget? leading;
  final Widget child;

  static const _thickness = 56.0;

  @override
  Widget build(BuildContext context) {
    // The bar consumed the inset on its edge, so the content must not
    // count it again — otherwise the deck gains a second gutter there.
    final content = Expanded(
      child: MediaQuery.removePadding(
        context: context,
        removeTop: side == BarSide.top,
        removeLeft: side == BarSide.left,
        removeRight: side == BarSide.right,
        child: child,
      ),
    );

    final body = switch (side) {
      BarSide.top => Column(children: [_bar(context), content]),
      BarSide.left => Row(children: [_bar(context), content]),
      BarSide.right => Row(children: [content, _bar(context)]),
    };

    // The bar absorbs the inset on its own edge; the content keeps the rest.
    return Scaffold(body: body);
  }

  Widget _bar(BuildContext context) {
    final theme = Theme.of(context);
    final insets = MediaQuery.viewPaddingOf(context);
    final background = theme.colorScheme.surface;

    if (side == BarSide.top) {
      return Material(
        color: background,
        child: Padding(
          padding: EdgeInsets.only(
            top: insets.top,
            left: insets.left + 4,
            right: insets.right + 4,
          ),
          child: SizedBox(
            height: _thickness,
            child: Row(
              children: [
                ?leading,
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleLarge),
                ),
                ...actions,
              ],
            ),
          ),
        ),
      );
    }

    final onLeft = side == BarSide.left;
    return Material(
      color: background,
      child: Padding(
        padding: EdgeInsets.only(
          top: insets.top + 4,
          bottom: insets.bottom + 4,
          left: onLeft ? insets.left : 0,
          right: onLeft ? 0 : insets.right,
        ),
        child: SizedBox(
          width: _thickness,
          // The title text is dropped on the side edges — there is no
          // room to spell it out at only _thickness wide without either
          // truncating it to nothing useful or crowding out the icon and
          // actions, so landscape shows just the app icon in its place.
          child: Column(
            children: [?leading, const Spacer(), ...actions],
          ),
        ),
      ),
    );
  }
}
