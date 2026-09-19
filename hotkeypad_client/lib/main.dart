import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/app_localizations.dart';
import 'src/deck_page.dart';
import 'src/locale_store.dart';
import 'package:hotkeypad_protocol/hotkeypad_protocol.dart';

/// Hides the status bar and (on Android) the navigation bar, and lets the
/// deck draw edge-to-edge underneath both — a deck button in the corner
/// is worth more than the sliver of screen a system bar would otherwise
/// keep for itself. `immersiveSticky` over plain `immersive`: swiping
/// from an edge still reveals the bars temporarily (so the system
/// gestures/notifications a user actually needs stay reachable), but the
/// swipe itself does not also land on whatever button was underneath it.
/// Independent of orientation — Android does not need this reapplied
/// when the device is turned.
///
/// On Android 15+ this call alone no longer actually hides anything —
/// mandatory edge-to-edge enforcement overrides the legacy system-UI-flags
/// API it is built on (see the Flutter team's own breaking-change note:
/// https://docs.flutter.dev/release/breaking-changes/default-systemuimode-edge-to-edge).
/// `MainActivity.kt`'s `hideSystemBars` drives the modern
/// `WindowInsetsControllerCompat` API natively instead for that case; this
/// call stays for iOS (which that native code cannot reach) and for
/// pre-15 Android, where it still works fine on its own.
void _hideSystemBars() {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
    _hideSystemBars();
    unawaited(_loadLocale());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Returning to the foreground — from the recents screen, or after the
  // user's own swipe-to-reveal in _hideSystemBars's sticky mode expired
  // on its own — leaves Android showing the system bars again rather
  // than restoring them to hidden by itself.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _hideSystemBars();
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
