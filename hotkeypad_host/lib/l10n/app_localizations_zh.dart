// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get serviceTitle => '服務';

  @override
  String get backToDeck => '返回面板';

  @override
  String get language => '語言';

  @override
  String get systemDefaultLanguage => '跟隨系統';

  @override
  String get accessibilityNotGranted => '尚未授予輔助使用權限';

  @override
  String get accessibilityNotGrantedBody => '在系統設定中允許這個 App 之前,媒體鍵與組合鍵都不會有作用';

  @override
  String get grant => '授予權限';

  @override
  String connectedClients(int count) {
    return '已連線裝置($count)';
  }

  @override
  String get noClientConnected => '目前還沒有裝置連線。';

  @override
  String notifySubscribed(int count) {
    return '通知 $count 個已訂閱的裝置';
  }

  @override
  String get noSubscribedClient => '目前沒有已訂閱的裝置';

  @override
  String get activity => '活動紀錄';

  @override
  String get nothingYet => '還沒有任何紀錄。';

  @override
  String wifiPinNewDevice(String name) {
    return '$name 想要透過 WiFi 連線——代碼:';
  }

  @override
  String get newDeviceFallback => '有新裝置';

  @override
  String get wifiPinReject => '拒絕——不允許這個裝置連線';

  @override
  String updateAvailable(String version) {
    return '有新版本 HotkeyPad Host $version 可以更新。';
  }

  @override
  String get viewAction => '查看';

  @override
  String get dismiss => '關閉';

  @override
  String get pairViaQr => '以 QR Code 配對';

  @override
  String get pairViaQrSubtitle => '用 HotkeyPad App 掃描即可連線';

  @override
  String get show => '顯示';

  @override
  String get scanToConnect => '掃描以連線';

  @override
  String get done => '完成';
}

/// The translations for Chinese, using the Han script (`zh_Hant`).
class AppLocalizationsZhHant extends AppLocalizationsZh {
  AppLocalizationsZhHant() : super('zh_Hant');

  @override
  String get serviceTitle => '服務';

  @override
  String get backToDeck => '返回面板';

  @override
  String get language => '語言';

  @override
  String get systemDefaultLanguage => '跟隨系統';

  @override
  String get accessibilityNotGranted => '尚未授予輔助使用權限';

  @override
  String get accessibilityNotGrantedBody => '在系統設定中允許這個 App 之前,媒體鍵與組合鍵都不會有作用';

  @override
  String get grant => '授予權限';

  @override
  String connectedClients(int count) {
    return '已連線裝置($count)';
  }

  @override
  String get noClientConnected => '目前還沒有裝置連線。';

  @override
  String notifySubscribed(int count) {
    return '通知 $count 個已訂閱的裝置';
  }

  @override
  String get noSubscribedClient => '目前沒有已訂閱的裝置';

  @override
  String get activity => '活動紀錄';

  @override
  String get nothingYet => '還沒有任何紀錄。';

  @override
  String wifiPinNewDevice(String name) {
    return '$name 想要透過 WiFi 連線——代碼:';
  }

  @override
  String get newDeviceFallback => '有新裝置';

  @override
  String get wifiPinReject => '拒絕——不允許這個裝置連線';

  @override
  String updateAvailable(String version) {
    return '有新版本 HotkeyPad Host $version 可以更新。';
  }

  @override
  String get viewAction => '查看';

  @override
  String get dismiss => '關閉';

  @override
  String get pairViaQr => '以 QR Code 配對';

  @override
  String get pairViaQrSubtitle => '用 HotkeyPad App 掃描即可連線';

  @override
  String get show => '顯示';

  @override
  String get scanToConnect => '掃描以連線';

  @override
  String get done => '完成';
}
