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

  /// WiFi pairing banner, before the PIN itself.
  ///
  /// In en, this message translates to:
  /// **'{name} wants to connect over WiFi — code:'**
  String wifiPinNewDevice(String name);

  /// Used in place of a name the connecting device didn't give.
  ///
  /// In en, this message translates to:
  /// **'A new device'**
  String get newDeviceFallback;

  /// Tooltip on the WiFi pairing banner's close button.
  ///
  /// In en, this message translates to:
  /// **'Reject — don\'t let this device connect'**
  String get wifiPinReject;

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

  /// QR code dialog close button.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;
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
