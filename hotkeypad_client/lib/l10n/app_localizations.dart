import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
    Locale('zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
  ];

  /// Search screen heading while searching.
  ///
  /// In en, this message translates to:
  /// **'Looking for a host'**
  String get lookingForHost;

  /// Search screen subtitle while searching.
  ///
  /// In en, this message translates to:
  /// **'Start the HotkeyPad host on your Mac.'**
  String get startHostOnMac;

  /// Search screen heading after a failed search.
  ///
  /// In en, this message translates to:
  /// **'No host found'**
  String get noHostFound;

  /// Button to retry discovery.
  ///
  /// In en, this message translates to:
  /// **'Search again'**
  String get searchAgain;

  /// Button opening the manual-entry dialog.
  ///
  /// In en, this message translates to:
  /// **'Enter host IP manually'**
  String get enterHostIpManually;

  /// Button opening the QR-scan screen.
  ///
  /// In en, this message translates to:
  /// **'Scan QR code'**
  String get scanQrCode;

  /// Tooltip on the bug icon in the app bar.
  ///
  /// In en, this message translates to:
  /// **'Debug console'**
  String get debugConsole;

  /// Heading above the list of previously-connected hosts.
  ///
  /// In en, this message translates to:
  /// **'Previous hosts'**
  String get previousHosts;

  /// Action to remove one entry from the previous-hosts list.
  ///
  /// In en, this message translates to:
  /// **'Forget'**
  String get forgetHost;

  /// Manual-entry dialog title.
  ///
  /// In en, this message translates to:
  /// **'Enter host IP'**
  String get enterHostIpTitle;

  /// Manual-entry dialog helper text.
  ///
  /// In en, this message translates to:
  /// **'Shown on the host itself, under WiFi in its status card.'**
  String get enterHostIpHint;

  /// Text field label.
  ///
  /// In en, this message translates to:
  /// **'IP address'**
  String get ipAddressLabel;

  /// Button revealing the optional port field.
  ///
  /// In en, this message translates to:
  /// **'Advanced: custom port'**
  String get advancedCustomPort;

  /// Text field label.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get portLabel;

  /// Dialog cancel button.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Dialog confirm button.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connectAction;

  /// Connection overlay heading.
  ///
  /// In en, this message translates to:
  /// **'Connecting to {name}'**
  String connectingTo(String name);

  /// Connection overlay heading on a retry.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting to {name}'**
  String reconnectingTo(String name);

  /// Connection overlay heading.
  ///
  /// In en, this message translates to:
  /// **'Discovering services'**
  String get discoveringServices;

  /// Connection overlay heading.
  ///
  /// In en, this message translates to:
  /// **'Subscribing'**
  String get subscribingStage;

  /// Connection overlay heading while awaiting a PIN.
  ///
  /// In en, this message translates to:
  /// **'Enter the code shown on {name}'**
  String enterCodeShownOn(String name);

  /// Connection overlay heading.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get disconnectedStage;

  /// Connection overlay heading on failure.
  ///
  /// In en, this message translates to:
  /// **'Could not connect'**
  String get couldNotConnect;

  /// Connection overlay body text.
  ///
  /// In en, this message translates to:
  /// **'The link to {name} was lost.'**
  String linkLostTo(String name);

  /// Connection overlay status line.
  ///
  /// In en, this message translates to:
  /// **'Retrying now...'**
  String get retryingNow;

  /// Connection overlay status line.
  ///
  /// In en, this message translates to:
  /// **'Retrying in {seconds}s · attempt {attempt}'**
  String retryingInSeconds(int seconds, int attempt);

  /// Connection overlay button.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// Connection overlay button.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// Connection overlay button when a retry is already scheduled.
  ///
  /// In en, this message translates to:
  /// **'Retry now'**
  String get retryNow;

  /// Badge shown while the layout/icons are being fetched.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get syncing;

  /// Host-side button label to show a pairing QR code.
  ///
  /// In en, this message translates to:
  /// **'Pair via QR'**
  String get pairViaQr;

  /// Title of the QR-scan screen.
  ///
  /// In en, this message translates to:
  /// **'Scan host QR code'**
  String get scanHostQrTitle;

  /// Instruction on the QR-scan screen.
  ///
  /// In en, this message translates to:
  /// **'Point your camera at the QR code shown on the host'**
  String get pointCameraAtQr;

  /// Shown when a scanned code cannot be parsed.
  ///
  /// In en, this message translates to:
  /// **'That QR code isn\'t a HotkeyPad host'**
  String get invalidHostQr;

  /// Shown when camera permission is refused.
  ///
  /// In en, this message translates to:
  /// **'Camera access is needed to scan a QR code'**
  String get cameraPermissionDenied;

  /// Button to open the system settings app.
  ///
  /// In en, this message translates to:
  /// **'Open settings'**
  String get openSettings;

  /// Tooltip on the app bar's language-picker button.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// Option in the language picker that follows the phone's own language.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get systemDefaultLanguage;

  /// Heading on the first-run connection-method choice screen.
  ///
  /// In en, this message translates to:
  /// **'Choose how to connect'**
  String get connectionMethodTitle;

  /// Subtitle on the first-run connection-method choice screen.
  ///
  /// In en, this message translates to:
  /// **'You can change this later from settings.'**
  String get connectionMethodSubtitle;

  /// Bluetooth connection method option.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth'**
  String get connectionMethodBluetooth;

  /// Description of the Bluetooth connection method.
  ///
  /// In en, this message translates to:
  /// **'Scan for a host advertising nearby over Bluetooth.'**
  String get connectionMethodBluetoothHint;

  /// WiFi connection method option.
  ///
  /// In en, this message translates to:
  /// **'WiFi'**
  String get connectionMethodWifi;

  /// Description of the WiFi connection method.
  ///
  /// In en, this message translates to:
  /// **'Find a host on the same network, or enter its address.'**
  String get connectionMethodWifiHint;

  /// Section heading above the connection-method radio buttons in the settings dialog.
  ///
  /// In en, this message translates to:
  /// **'Connection method'**
  String get connectionMethodSettingsTitle;

  /// Tooltip on the gear icon, and title of the dialog it opens.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Button that closes the settings dialog.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// Settings-dialog entry opening the Bluetooth scanner diagnostic, and title of the page it opens.
  ///
  /// In en, this message translates to:
  /// **'Nearby devices'**
  String get nearbyDevices;

  /// Debug console body text before any session exists.
  ///
  /// In en, this message translates to:
  /// **'Not connected to a host yet.'**
  String get notConnectedToHostYet;

  /// Debug console body text before any message has been logged.
  ///
  /// In en, this message translates to:
  /// **'No traffic yet.'**
  String get noTrafficYet;

  /// Debug console composer field hint.
  ///
  /// In en, this message translates to:
  /// **'Send raw text to the host'**
  String get sendRawTextHint;

  /// Debug console bubble label for a message received from the host.
  ///
  /// In en, this message translates to:
  /// **'host'**
  String get messageFromHost;

  /// Debug console bubble label for a message this app sent.
  ///
  /// In en, this message translates to:
  /// **'sent'**
  String get messageSent;

  /// Compact link-stage label in the debug console's app bar.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get debugStageConnecting;

  /// Compact link-stage label in the debug console's app bar.
  ///
  /// In en, this message translates to:
  /// **'Discovering services'**
  String get debugStageDiscovering;

  /// Compact link-stage label in the debug console's app bar.
  ///
  /// In en, this message translates to:
  /// **'Subscribing'**
  String get debugStageSubscribing;

  /// Compact link-stage label in the debug console's app bar.
  ///
  /// In en, this message translates to:
  /// **'Enter the code shown on the host'**
  String get debugStageAwaitingPin;

  /// Compact link-stage label in the debug console's app bar.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get debugStageReady;

  /// Compact link-stage label in the debug console's app bar.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get debugStageDisconnected;

  /// Compact link-stage label in the debug console's app bar.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get debugStageFailed;

  /// Appended to the debug console's stage label when the negotiated MTU is known.
  ///
  /// In en, this message translates to:
  /// **'MTU {mtu}'**
  String mtuLabel(int mtu);

  /// Tooltip on the nearby-devices page's clear-list icon.
  ///
  /// In en, this message translates to:
  /// **'Clear list'**
  String get clearDeviceList;

  /// Filter chip label on the nearby-devices page.
  ///
  /// In en, this message translates to:
  /// **'HotkeyPad hosts ({count})'**
  String hotkeypadHostsCount(int count);

  /// Count of devices currently listed on the nearby-devices page.
  ///
  /// In en, this message translates to:
  /// **'{count} shown'**
  String devicesShownCount(int count);

  /// Placeholder name for a discovered device with no advertised name.
  ///
  /// In en, this message translates to:
  /// **'Unknown device'**
  String get unknownDevice;

  /// Short badge marking a discovered device as a HotkeyPad host.
  ///
  /// In en, this message translates to:
  /// **'HOST'**
  String get hostBadge;

  /// Nearby-devices list item subtitle.
  ///
  /// In en, this message translates to:
  /// **'{id}\n{rssi} dBm  ·  seen {seconds}s ago'**
  String deviceSubtitle(String id, int rssi, int seconds);

  /// Snackbar shown when scanning is attempted with Bluetooth off.
  ///
  /// In en, this message translates to:
  /// **'Turn Bluetooth on first.'**
  String get turnBluetoothOnFirst;

  /// Snackbar shown when scanning is attempted without permission.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth permission denied.'**
  String get bluetoothPermissionDeniedSnackbar;

  /// Nearby-devices adapter banner.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth is turned off.'**
  String get bluetoothOff;

  /// Nearby-devices adapter banner.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth permission has not been granted yet.'**
  String get bluetoothUnauthorized;

  /// Nearby-devices adapter banner.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth Low Energy is not supported on this device.'**
  String get bluetoothUnsupported;

  /// Nearby-devices adapter banner.
  ///
  /// In en, this message translates to:
  /// **'Checking Bluetooth adapter...'**
  String get bluetoothCheckingAdapter;

  /// Button on the nearby-devices adapter banner that requests permission.
  ///
  /// In en, this message translates to:
  /// **'Grant'**
  String get grantAction;

  /// Nearby-devices empty state while a scan is running.
  ///
  /// In en, this message translates to:
  /// **'Scanning for devices...'**
  String get scanningForDevices;

  /// Nearby-devices empty state before a scan has started.
  ///
  /// In en, this message translates to:
  /// **'Tap Scan to look for nearby devices.'**
  String get tapScanToLookForDevices;

  /// Floating action button label while scanning.
  ///
  /// In en, this message translates to:
  /// **'Stop scan'**
  String get stopScan;

  /// Floating action button label while not scanning.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get scanAction;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ja', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+script codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.scriptCode) {
          case 'Hant':
            return AppLocalizationsZhHant();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ja':
      return AppLocalizationsJa();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
