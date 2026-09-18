import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// Set once per actual change rather than on every build (every screen using
/// [EdgeBarScaffold] rebuilds far more often than the device is rotated —
/// an icon sync alone is enough) — this is the app's only landscape side,
/// so a module-level "last value" is enough to guard it without a State.
BarSide? _lastSystemUiSide;

/// Hides the top status bar in landscape, where it sits in the same strip
/// as the side app bar and adds nothing a portrait status bar does — the
/// bottom navigation bar (Android's, or nothing on iOS) is left alone.
void _applySystemUiFor(BarSide side) {
  if (_lastSystemUiSide == side) return;
  _lastSystemUiSide = side;
  final portrait = side == BarSide.top;
  if (portrait) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  } else {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.bottom],
    );
  }
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
    this.subtitle,
  });

  final BarSide side;
  final String title;

  /// A second, smaller line under [title] — e.g. which host the deck is
  /// currently talking to, kept separate from the app's own brand name
  /// rather than replacing it (see `DeckPage`'s connected-deck app bar).
  /// Only drawn on [BarSide.top]: the side bars already drop [title]
  /// itself for lack of room, so a subtitle would have even less.
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;
  final Widget child;

  static const _thickness = 56.0;

  @override
  Widget build(BuildContext context) {
    _applySystemUiFor(side);

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

    // A step above the plain surface color Scaffold defaults to — the
    // deck's own background image (when set) still draws over this, but
    // an unconfigured deck no longer reads as flat white/black margins
    // around the grid, particularly in landscape where the grid leaves
    // the most of that space empty (see the grid's own centering logic
    // in deck_page.dart — deliberately not stretched to fill it).
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      body: body,
    );
  }

  Widget _bar(BuildContext context) {
    final theme = Theme.of(context);
    final insets = MediaQuery.viewPaddingOf(context);
    // A tinted container color rather than the plain surface the bar used
    // to share with the body — the bar is chrome, not deck, and reads as
    // its own edge in every rotation (side bars included) instead of
    // blending into whichever whitespace happens to be next to it.
    final background = theme.colorScheme.primaryContainer;
    final onBackground = theme.colorScheme.onPrimaryContainer;
    final iconTheme = IconThemeData(color: onBackground);

    if (side == BarSide.top) {
      final subtitle = this.subtitle;
      return Material(
        color: background,
        child: Padding(
          padding: EdgeInsets.only(
            top: insets.top,
            left: insets.left + 4,
            right: insets.right + 4,
          ),
          child: SizedBox(
            // A second line needs more than a single title's worth of
            // height — grown rather than shrinking the title's own font
            // to make room, since the title is the app's brand name and
            // should read the same whether or not a subtitle is present.
            height: subtitle == null ? _thickness : _thickness + 14,
            child: IconTheme.merge(
              data: iconTheme,
              child: Row(
                children: [
                  ?leading,
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: onBackground,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: onBackground.withValues(alpha: 0.75),
                            ),
                          ),
                      ],
                    ),
                  ),
                  ...actions,
                ],
              ),
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
          child: IconTheme.merge(
            data: iconTheme,
            child: Column(
              children: [?leading, const Spacer(), ...actions],
            ),
          ),
        ),
      ),
    );
  }
}
