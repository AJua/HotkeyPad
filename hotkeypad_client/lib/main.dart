import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/app_localizations.dart';
import 'src/deck_page.dart';
import 'src/locale_store.dart';
import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';

/// Native bypass for Android 15+, where `SystemChrome`'s own call below
/// stops actually hiding anything on its own — see `MainActivity.kt`'s
/// `hideSystemBars`/`showSystemBars` for why. A no-op on every other
/// platform (`invokeMethod` throws `MissingPluginException` there, since
/// nothing registers this channel), which is why every call is guarded to
/// Android only rather than left to fail silently.
const _systemBarsChannel = MethodChannel('hotkeypad/systembars');

/// Hides the status bar and (on Android) the navigation bar, and lets the
/// deck draw edge-to-edge underneath both — a deck button in the corner is
/// worth more than the sliver of screen a system bar would otherwise keep
/// for itself. `immersiveSticky` over plain `immersive`: swiping from an
/// edge still reveals the bars temporarily (so the system gestures/
/// notifications a user actually needs stay reachable), but the swipe
/// itself does not also land on whatever button was underneath it.
///
/// Matches YouTube's own landscape-fullscreen convention (see
/// `EdgeBarScaffold`, which hides its own app bar the same way): landscape
/// hides every bar, portrait — [showSystemBars] — brings them all back.
void hideSystemBars() {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  if (defaultTargetPlatform == TargetPlatform.android) {
    unawaited(_systemBarsChannel.invokeMethod('setHidden', true));
  }
}

/// The portrait counterpart to [hideSystemBars] — restores the normal
/// edge-to-edge mode (bars shown, content still allowed to draw behind
/// them) rather than plain `manual` with no overlays, so this still
/// matches what the app already looked like before any of this landscape
/// handling existed.
void showSystemBars() {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  if (defaultTargetPlatform == TargetPlatform.android) {
    unawaited(_systemBarsChannel.invokeMethod('setHidden', false));
  }
}

void main() {
  runApp(const HotkeyPadClientApp());
}

class HotkeyPadClientApp extends StatefulWidget {
  const HotkeyPadClientApp({super.key});

  @override
  State<HotkeyPadClientApp> createState() => _HotkeyPadClientAppState();
}

class _HotkeyPadClientAppState extends State<HotkeyPadClientApp>
    with WidgetsBindingObserver {
  /// Set by the host, which owns configuration here as it owns the grid.
  DeckTheme _theme = DeckTheme.system;

  /// The user's own manual language choice — entirely client-side, never
  /// sent to or learned from the host (unlike [_theme]): the host has no
  /// business deciding what language the *person holding the phone*
  /// reads, and a host possibly controlling several different clients
  /// could not pick one language for all of them anyway. Null follows
  /// the system language, same as [MaterialApp.locale]'s own null does.
  Locale? _locale;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Not called from bare main(), before runApp: that is early enough
    // the platform channel this rides on can still silently drop the
    // call. Here, once the binding backing this widget is actually live,
    // is the first point it reliably takes effect.
    _applySystemBarsForCurrentOrientation();
    unawaited(_loadLocale());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // The standard place Flutter itself recommends reacting to a rotation
  // from — fires as soon as the new physical size is known, well before
  // any particular screen's own build gets a chance to react to it.
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _applySystemBarsForCurrentOrientation();
  }

  // Returning to the foreground — from the recents screen, or after the
  // user's own swipe-to-reveal in immersiveSticky's landscape mode expired
  // on its own — leaves Android showing the system bars again rather than
  // restoring them by itself, in whichever state the current orientation
  // calls for.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _applySystemBarsForCurrentOrientation();
    }
  }

  void _applySystemBarsForCurrentOrientation() {
    final size =
        WidgetsBinding.instance.platformDispatcher.views.first.physicalSize;
    if (size.height >= size.width) {
      showSystemBars();
    } else {
      hideSystemBars();
    }
  }

  Future<void> _loadLocale() async {
    final tag = await LocaleStore.load();
    if (mounted) setState(() => _locale = localeFromTag(tag));
  }

  Future<void> _setLocale(Locale? locale) async {
    setState(() => _locale = locale);
    await LocaleStore.save(tagFromLocale(locale));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      themeMode: switch (_theme) {
        DeckTheme.system => ThemeMode.system,
        DeckTheme.light => ThemeMode.light,
        DeckTheme.dark => ThemeMode.dark,
      },
      title: 'HotkeyPad',
      debugShowCheckedModeBanner: false,
      locale: _locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        colorSchemeSeed: HotkeyPad.themeSeedColor,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: HotkeyPad.themeSeedColor,
        brightness: Brightness.dark,
      ),
      home: DeckPage(
        onTheme: (theme) => setState(() => _theme = theme),
        locale: _locale,
        onLocale: _setLocale,
      ),
    );
  }
}
