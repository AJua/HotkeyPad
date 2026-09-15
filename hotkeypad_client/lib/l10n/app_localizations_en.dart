// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get lookingForHost => 'Looking for a host';

  @override
  String get startHostOnMac => 'Start the HotkeyPad host on your Mac.';

  @override
  String get noHostFound => 'No host found';

  @override
  String get searchAgain => 'Search again';

  @override
  String get enterHostIpManually => 'Enter host IP manually';

  @override
  String get scanQrCode => 'Scan QR code';

  @override
  String get debugConsole => 'Debug console';

  @override
  String get previousHosts => 'Previous hosts';

  @override
  String get forgetHost => 'Forget';

  @override
  String get enterHostIpTitle => 'Enter host IP';

  @override
  String get enterHostIpHint =>
      'Shown on the host itself, under WiFi in its status card.';

  @override
  String get ipAddressLabel => 'IP address';

  @override
  String get advancedCustomPort => 'Advanced: custom port';

  @override
  String get portLabel => 'Port';

  @override
  String get cancel => 'Cancel';

  @override
  String get connectAction => 'Connect';

  @override
  String connectingTo(String name) {
    return 'Connecting to $name';
  }

  @override
  String reconnectingTo(String name) {
    return 'Reconnecting to $name';
  }

  @override
  String get discoveringServices => 'Discovering services';

  @override
  String get subscribingStage => 'Subscribing';

  @override
  String enterCodeShownOn(String name) {
    return 'Enter the code shown on $name';
  }

  @override
  String get disconnectedStage => 'Disconnected';

  @override
  String get couldNotConnect => 'Could not connect';

  @override
  String linkLostTo(String name) {
    return 'The link to $name was lost.';
  }

  @override
  String get retryingNow => 'Retrying now...';

  @override
  String retryingInSeconds(int seconds, int attempt) {
    return 'Retrying in ${seconds}s · attempt $attempt';
  }

  @override
  String get back => 'Back';

  @override
  String get retry => 'Retry';

  @override
  String get retryNow => 'Retry now';

  @override
  String get syncing => 'Syncing…';

  @override
  String get pairViaQr => 'Pair via QR';

  @override
  String get scanHostQrTitle => 'Scan host QR code';

  @override
  String get pointCameraAtQr =>
      'Point your camera at the QR code shown on the host';

  @override
  String get invalidHostQr => 'That QR code isn\'t a HotkeyPad host';

  @override
  String get cameraPermissionDenied =>
      'Camera access is needed to scan a QR code';

  @override
  String get openSettings => 'Open settings';
}
