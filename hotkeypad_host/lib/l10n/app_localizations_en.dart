// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get serviceTitle => 'Service';

  @override
  String get backToDeck => 'Back to the deck';

  @override
  String get language => 'Language';

  @override
  String get systemDefaultLanguage => 'System default';

  @override
  String get accessibilityNotGranted => 'Accessibility is not granted';

  @override
  String get accessibilityNotGrantedBody =>
      'Media keys and key combinations will do nothing until this app is allowed in System Settings';

  @override
  String get grant => 'Grant';

  @override
  String connectedClients(int count) {
    return 'Connected clients ($count)';
  }

  @override
  String get noClientConnected => 'No client has connected yet.';

  @override
  String notifySubscribed(int count) {
    return 'Notify $count subscribed client(s)';
  }

  @override
  String get noSubscribedClient => 'No subscribed client yet';

  @override
  String get activity => 'Activity';

  @override
  String get nothingYet => 'Nothing yet.';

  @override
  String wifiPinNewDevice(String name) {
    return '$name wants to connect over WiFi — code:';
  }

  @override
  String get newDeviceFallback => 'A new device';

  @override
  String get wifiPinReject => 'Reject — don\'t let this device connect';

  @override
  String updateAvailable(String version) {
    return 'HotkeyPad Host $version is available.';
  }

  @override
  String get viewAction => 'View';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get pairViaQr => 'Pair via QR';

  @override
  String get pairViaQrSubtitle => 'Scan with the HotkeyPad app to connect';

  @override
  String get show => 'Show';

  @override
  String get scanToConnect => 'Scan to connect';

  @override
  String get done => 'Done';
}
