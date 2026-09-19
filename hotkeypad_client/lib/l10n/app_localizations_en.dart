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
  String get ipAddressExample => 'e.g. 192.168.1.23';

  @override
  String get invalidHostAddress =>
      'Enter a valid IP address, like 192.168.1.23.';

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
  String get incorrectPinRetrying =>
      'That code was wrong. Asking the host for a new one…';

  @override
  String get couldNotFindAddress =>
      'Couldn\'t find that address. Check it and try again.';

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

  @override
  String get language => 'Language';

  @override
  String get systemDefaultLanguage => 'System default';

  @override
  String get howToUseTitle => 'How to use';

  @override
  String get connectionMethodTitle => 'Choose how to connect';

  @override
  String get connectionMethodSubtitle =>
      'You can change this later from settings.';

  @override
  String get connectionMethodBluetooth => 'Bluetooth';

  @override
  String get connectionMethodBluetoothHint =>
      'Scan for a host advertising nearby over Bluetooth.';

  @override
  String get connectionMethodWifi => 'WiFi';

  @override
  String get connectionMethodWifiHint =>
      'Find a host on the same network, or enter its address.';

  @override
  String get step1Title => 'Install HotkeyPad Host';

  @override
  String get step1Body =>
      'HotkeyPad Host runs on a computer, not this phone. Tap the address below to copy it, then open it in a browser on that computer.';

  @override
  String get urlCopiedMessage => 'Copied to clipboard';

  @override
  String get connectionMethodSettingsTitle => 'Connection method';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get done => 'Done';

  @override
  String get reportIssueTitle => 'Report an issue';

  @override
  String get reportIssueSubtitle => 'Opens the HotkeyPad GitHub repository';

  @override
  String get nearbyDevices => 'Nearby devices';

  @override
  String get notConnectedToHostYet => 'Not connected to a host yet.';

  @override
  String get noTrafficYet => 'No traffic yet.';

  @override
  String get sendRawTextHint => 'Send raw text to the host';

  @override
  String get messageFromHost => 'host';

  @override
  String get messageSent => 'sent';

  @override
  String get debugStageConnecting => 'Connecting';

  @override
  String get debugStageDiscovering => 'Discovering services';

  @override
  String get debugStageSubscribing => 'Subscribing';

  @override
  String get debugStageAwaitingPin => 'Enter the code shown on the host';

  @override
  String get debugStageReady => 'Connected';

  @override
  String get debugStageDisconnected => 'Disconnected';

  @override
  String get debugStageFailed => 'Failed';

  @override
  String mtuLabel(int mtu) {
    return 'MTU $mtu';
  }

  @override
  String get clearDeviceList => 'Clear list';

  @override
  String hotkeypadHostsCount(int count) {
    return 'HotkeyPad hosts ($count)';
  }

  @override
  String devicesShownCount(int count) {
    return '$count shown';
  }

  @override
  String get unknownDevice => 'Unknown device';

  @override
  String get hostBadge => 'HOST';

  @override
  String deviceSubtitle(String id, int rssi, int seconds) {
    return '$id\n$rssi dBm  ·  seen ${seconds}s ago';
  }

  @override
  String get turnBluetoothOnFirst => 'Turn Bluetooth on first.';

  @override
  String get bluetoothPermissionDeniedSnackbar =>
      'Bluetooth permission denied.';

  @override
  String get bluetoothOff => 'Bluetooth is turned off.';

  @override
  String get bluetoothUnauthorized =>
      'Bluetooth permission has not been granted yet.';

  @override
  String get bluetoothUnsupported =>
      'Bluetooth Low Energy is not supported on this device.';

  @override
  String get bluetoothCheckingAdapter => 'Checking Bluetooth adapter...';

  @override
  String get grantAction => 'Grant';

  @override
  String get scanningForDevices => 'Scanning for devices...';

  @override
  String get tapScanToLookForDevices => 'Tap Scan to look for nearby devices.';

  @override
  String get stopScan => 'Stop scan';

  @override
  String get scanAction => 'Scan';
}
