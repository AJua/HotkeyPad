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

  @override
  String get deckLayoutTitle => 'Deck layout';

  @override
  String get deckLayoutHint =>
      'Click a cell to choose what it does. Drag a button to move it, including onto another page.';

  @override
  String get previewOrientationTooltip => 'Preview portrait/landscape';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get appearanceSectionHeader => 'Appearance';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get appBarToggleTitle => 'App bar';

  @override
  String get appBarToggleSubtitle =>
      'Off hides the title and debug console button, and gives the whole screen to the deck';

  @override
  String get buttonLabelsToggleTitle => 'Button labels';

  @override
  String get buttonLabelsToggleSubtitle =>
      'Off makes cells square and lets the icon fill them';

  @override
  String get pageDotsToggleTitle => 'Page dots';

  @override
  String get pageDotsToggleSubtitle =>
      'Off hides the page indicator below a multi-page deck — swiping between pages still works';

  @override
  String get backgroundImageSectionHeader => 'Background image';

  @override
  String get chooseImageAction => 'Choose image...';

  @override
  String get changeImageAction => 'Change...';

  @override
  String get removeImageAction => 'Remove';

  @override
  String get opacityLabel => 'Opacity';

  @override
  String get backgroundFitCover => 'Fill screen';

  @override
  String get backgroundFitContain => 'Fit whole image';

  @override
  String get backgroundFitStretch => 'Stretch';

  @override
  String get gridSectionHeader => 'Grid';

  @override
  String get columnsLabel => 'Columns';

  @override
  String get rowsLabel => 'Rows';

  @override
  String get pagesLabel => 'Pages';

  @override
  String get backupSectionHeader => 'Backup';

  @override
  String get exportSettingsTitle => 'Export settings...';

  @override
  String get exportSettingsSubtitle =>
      'Save appearance, layout, and custom icons to a file';

  @override
  String get importSettingsTitle => 'Import settings...';

  @override
  String get importSettingsSubtitle =>
      'Replace the current setup from a backup file';

  @override
  String get serviceDetailsTitle => 'Service details';

  @override
  String get serviceDetailsSubtitle =>
      'Advertising state, connected clients, activity log';

  @override
  String get reportIssueTitle => 'Report an issue';

  @override
  String get reportIssueSubtitle => 'Opens the HotkeyPad GitHub repository';
}
