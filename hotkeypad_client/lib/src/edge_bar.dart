import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A conventional app bar pinned to the top of the screen — but, matching
/// YouTube's own landscape-fullscreen convention, only in portrait.
/// Landscape hides it entirely (alongside the system status/navigation
/// bars — see `main.dart`'s `hideSystemBars`/`showSystemBars`, driven by
/// the same orientation), handing the deck grid the whole screen in
/// exactly the dimension it has the least of to begin with.
///
/// [child] is pushed down to make room for the bar in portrait, the same
/// as any ordinary app bar; in landscape there is nothing to push down
/// for, so it gets the full screen.
class EdgeBarScaffold extends StatelessWidget {
  const EdgeBarScaffold({
    super.key,
    required this.title,
    required this.actions,
    required this.child,
    this.leading,
    this.subtitle,
  });

  final String title;

  /// A second, smaller line under [title] — e.g. which host the deck is
  /// currently talking to, kept separate from the app's own brand name
  /// rather than replacing it (see `DeckPage`'s connected-deck app bar).
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;
  final Widget child;

  static const _height = 56.0;

  @override
  Widget build(BuildContext context) {
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;

    if (!portrait) {
      final viewInsets = MediaQuery.viewPaddingOf(context);
      final vertical = math.max(viewInsets.top, viewInsets.bottom);
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
        // Not a SafeArea: that pads for the home indicator's *software*
        // gesture-area convention too, which is exactly the "not really
        // edge to edge" gap this got called out for — a real, if minor,
        // area under it is still perfectly visible and tappable, unlike a
        // genuine hardware notch/Dynamic Island cutout. viewPadding
        // reflects only the latter (present regardless of whether system
        // UI is currently shown).
        //
        // Still not applied as-is, though: on iOS, viewPadding.bottom is
        // itself nonzero in landscape — the home indicator turns out to
        // claim real, unwaivable space there even by that measure — with
        // nothing matching it on top, which visibly shifted the deck grid
        // up rather than leaving it centered. Mirroring the taller of the
        // two vertical insets onto both is what actually gets a symmetric
        // result: worth a few points of unnecessary top clearance on
        // devices where it doesn't, in exchange for the grid always
        // landing dead centre instead of however far off it happens to be
        // pulled by whichever of the two the device electes to keep.
        //
        // MediaQuery.removePadding zeroes the *ambient* padding too, not
        // just this widget's own — without it, the deck grid's own
        // safeScrollPadding (deck_page.dart) reads the raw, un-consumed
        // MediaQuery.paddingOf further down the tree and adds the home
        // indicator's bottom inset a second time on top of this.
        body: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          removeBottom: true,
          removeLeft: true,
          removeRight: true,
          child: Padding(
            padding: EdgeInsets.only(
              top: vertical,
              bottom: vertical,
              left: viewInsets.left,
              right: viewInsets.right,
            ),
            child: child,
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final background = theme.colorScheme.primaryContainer;
    final onBackground = theme.colorScheme.onPrimaryContainer;
    final insets = MediaQuery.paddingOf(context);
    final subtitle = this.subtitle;

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainer,
      body: Column(
        children: [
          Material(
            color: background,
            child: Padding(
              padding: EdgeInsets.only(
                top: insets.top,
                left: insets.left + 4,
                right: insets.right + 4,
              ),
              child: SizedBox(
                // A second line needs more than a single title's worth of
                // height — grown rather than shrinking the title's own
                // font to make room, since the title is the app's brand
                // name and should read the same whether or not a subtitle
                // is present.
                height: subtitle == null ? _height : _height + 14,
                child: IconTheme.merge(
                  data: IconThemeData(color: onBackground),
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
          ),
          Expanded(
            // The bar already consumed the top inset above, so child must
            // not count it again — left/right/bottom are untouched: those
            // are exactly what SafeArea below still needs to protect.
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: SafeArea(top: false, child: child),
            ),
          ),
        ],
      ),
    );
  }
}
