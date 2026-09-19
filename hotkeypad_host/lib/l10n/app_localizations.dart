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

  /// Service screen's app bar title.
  ///
  /// In en, this message translates to:
  /// **'Service'**
  String get serviceTitle;

  /// Tooltip on the service screen's back button.
  ///
  /// In en, this message translates to:
  /// **'Back to the deck'**
  String get backToDeck;

  /// Tooltip on the language-picker button.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// Option in the language picker that follows the OS language.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get systemDefaultLanguage;

  /// Warning card title.
  ///
  /// In en, this message translates to:
  /// **'Accessibility is not granted'**
  String get accessibilityNotGranted;

  /// Warning card body.
  ///
  /// In en, this message translates to:
  /// **'Media keys and key combinations will do nothing until this app is allowed in System Settings'**
  String get accessibilityNotGrantedBody;

  /// Button requesting the Accessibility permission.
  ///
  /// In en, this message translates to:
  /// **'Grant'**
  String get grant;

  /// Section header.
  ///
  /// In en, this message translates to:
  /// **'Connected clients ({count})'**
  String connectedClients(int count);

  /// Empty state for the connected-clients list.
  ///
  /// In en, this message translates to:
  /// **'No client has connected yet.'**
  String get noClientConnected;

  /// Broadcast message field hint, at least one client subscribed.
  ///
  /// In en, this message translates to:
  /// **'Notify {count} subscribed client(s)'**
  String notifySubscribed(int count);

  /// Broadcast message field hint, no client subscribed.
  ///
  /// In en, this message translates to:
  /// **'No subscribed client yet'**
  String get noSubscribedClient;

  /// Section header for the debug log.
  ///
  /// In en, this message translates to:
  /// **'Activity'**
  String get activity;

  /// Empty state for the activity log.
  ///
  /// In en, this message translates to:
  /// **'Nothing yet.'**
  String get nothingYet;

  /// Pairing banner, before the PIN itself. Shown for a new WiFi or Bluetooth connection alike.
  ///
  /// In en, this message translates to:
  /// **'{name} wants to connect — code:'**
  String pinChallengeNewDevice(String name);

  /// Used in place of a name the connecting device didn't give.
  ///
  /// In en, this message translates to:
  /// **'A new device'**
  String get newDeviceFallback;

  /// Tooltip on the pairing banner's close button.
  ///
  /// In en, this message translates to:
  /// **'Reject — don\'t let this device connect'**
  String get pinChallengeReject;

  /// Update banner text.
  ///
  /// In en, this message translates to:
  /// **'HotkeyPad Host {version} is available.'**
  String updateAvailable(String version);

  /// Update banner button opening the release page.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get viewAction;

  /// Tooltip on the update banner's close button.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// QR pairing card title.
  ///
  /// In en, this message translates to:
  /// **'Pair via QR'**
  String get pairViaQr;

  /// QR pairing card subtitle.
  ///
  /// In en, this message translates to:
  /// **'Scan with the HotkeyPad app to connect'**
  String get pairViaQrSubtitle;

  /// Button revealing the QR code.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get show;

  /// QR code dialog title.
  ///
  /// In en, this message translates to:
  /// **'Scan to connect'**
  String get scanToConnect;

  /// Generic dialog close button labeled 'Done'.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// Deck layout screen's heading.
  ///
  /// In en, this message translates to:
  /// **'Deck layout'**
  String get deckLayoutTitle;

  /// Deck layout screen's instructional subtitle.
  ///
  /// In en, this message translates to:
  /// **'Click a cell to choose what it does. Drag a button to move it, including onto another page.'**
  String get deckLayoutHint;

  /// Tooltip on the rotate icon that flips the deck preview between portrait and landscape when no device is locked in.
  ///
  /// In en, this message translates to:
  /// **'Preview portrait/landscape'**
  String get previewOrientationTooltip;

  /// Tooltip on the settings gear icon, and the Settings dialog's title.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Settings dialog section header.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearanceSectionHeader;

  /// Appearance option that follows the OS light/dark setting.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// Appearance option for the light theme.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// Appearance option for the dark theme.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// Settings switch title.
  ///
  /// In en, this message translates to:
  /// **'Button labels'**
  String get buttonLabelsToggleTitle;

  /// Settings switch subtitle.
  ///
  /// In en, this message translates to:
  /// **'Off makes cells square and lets the icon fill them'**
  String get buttonLabelsToggleSubtitle;

  /// Settings dialog section header.
  ///
  /// In en, this message translates to:
  /// **'Background image'**
  String get backgroundImageSectionHeader;

  /// Button that opens a file picker when no background image is set.
  ///
  /// In en, this message translates to:
  /// **'Choose image...'**
  String get chooseImageAction;

  /// Button that opens a file picker when a background image is already set.
  ///
  /// In en, this message translates to:
  /// **'Change...'**
  String get changeImageAction;

  /// Button that clears the background image.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeImageAction;

  /// Label on the background image opacity slider.
  ///
  /// In en, this message translates to:
  /// **'Opacity'**
  String get opacityLabel;

  /// Background image scaling option that crops to fill the screen.
  ///
  /// In en, this message translates to:
  /// **'Fill screen'**
  String get backgroundFitCover;

  /// Background image scaling option that shows the whole image, letterboxed.
  ///
  /// In en, this message translates to:
  /// **'Fit whole image'**
  String get backgroundFitContain;

  /// Background image scaling option that stretches to fill the screen.
  ///
  /// In en, this message translates to:
  /// **'Stretch'**
  String get backgroundFitStretch;

  /// Settings dialog section header.
  ///
  /// In en, this message translates to:
  /// **'Grid'**
  String get gridSectionHeader;

  /// Grid size stepper label.
  ///
  /// In en, this message translates to:
  /// **'Columns'**
  String get columnsLabel;

  /// Grid size stepper label.
  ///
  /// In en, this message translates to:
  /// **'Rows'**
  String get rowsLabel;

  /// Grid size stepper label.
  ///
  /// In en, this message translates to:
  /// **'Pages'**
  String get pagesLabel;

  /// Settings dialog section header.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get backupSectionHeader;

  /// Settings dialog list tile title.
  ///
  /// In en, this message translates to:
  /// **'Export settings...'**
  String get exportSettingsTitle;

  /// Settings dialog list tile subtitle.
  ///
  /// In en, this message translates to:
  /// **'Save appearance, layout, and custom icons to a file'**
  String get exportSettingsSubtitle;

  /// Settings dialog list tile title.
  ///
  /// In en, this message translates to:
  /// **'Import settings...'**
  String get importSettingsTitle;

  /// Settings dialog list tile subtitle.
  ///
  /// In en, this message translates to:
  /// **'Replace the current setup from a backup file'**
  String get importSettingsSubtitle;

  /// Settings dialog list tile title.
  ///
  /// In en, this message translates to:
  /// **'Service details'**
  String get serviceDetailsTitle;

  /// Settings dialog list tile subtitle.
  ///
  /// In en, this message translates to:
  /// **'Advertising state, connected clients, activity log'**
  String get serviceDetailsSubtitle;

  /// Settings dialog list tile title that opens the HotkeyPad GitHub issue tracker in a browser.
  ///
  /// In en, this message translates to:
  /// **'Report an issue'**
  String get reportIssueTitle;

  /// Settings dialog list tile subtitle.
  ///
  /// In en, this message translates to:
  /// **'Opens the HotkeyPad GitHub repository'**
  String get reportIssueSubtitle;
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
