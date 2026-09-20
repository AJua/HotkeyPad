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
  String pinChallengeNewDevice(String name) {
    return '$name 想要連線——代碼:';
  }

  @override
  String get newDeviceFallback => '有新裝置';

  @override
  String get pinChallengeReject => '拒絕——不允許這個裝置連線';

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

  @override
  String get deckLayoutTitle => '面板配置';

  @override
  String get deckLayoutHint => '點擊按鈕格以選擇它的功能。拖曳按鈕可以移動它,也可以拖到其他頁面。';

  @override
  String get previewOrientationTooltip => '預覽直向／橫向';

  @override
  String get settingsTitle => '設定';

  @override
  String get appearanceSectionHeader => '外觀';

  @override
  String get themeSystem => '自動';

  @override
  String get themeLight => '淺色';

  @override
  String get themeDark => '深色';

  @override
  String get buttonLabelsToggleTitle => '按鈕文字標籤';

  @override
  String get buttonLabelsToggleSubtitle => '關閉後按鈕格會變成正方形,並讓圖示填滿整個格子';

  @override
  String get backgroundImageSectionHeader => '背景圖片';

  @override
  String get chooseImageAction => '選擇圖片…';

  @override
  String get noBackgroundOption => '無';

  @override
  String get backgroundSpring => '春天';

  @override
  String get backgroundSummer => '夏天';

  @override
  String get backgroundAutumn => '秋天';

  @override
  String get backgroundWinter => '冬天';

  @override
  String get backgroundSunny => '晴天';

  @override
  String get backgroundCloudy => '多雲';

  @override
  String get backgroundRainy => '雨天';

  @override
  String get backgroundSnowy => '下雪';

  @override
  String get backgroundMountains => '山巒';

  @override
  String get opacityLabel => '不透明度';

  @override
  String get backgroundFitCover => '填滿螢幕';

  @override
  String get backgroundFitContain => '完整顯示圖片';

  @override
  String get backgroundFitStretch => '拉伸';

  @override
  String get gridSectionHeader => '格線';

  @override
  String get columnsLabel => '欄數';

  @override
  String get rowsLabel => '列數';

  @override
  String get pagesLabel => '頁數';

  @override
  String get backupSectionHeader => '備份';

  @override
  String get exportSettingsTitle => '匯出設定…';

  @override
  String get exportSettingsSubtitle => '將外觀、版面配置與自訂圖示儲存成檔案';

  @override
  String get importSettingsTitle => '匯入設定…';

  @override
  String get importSettingsSubtitle => '以備份檔取代目前的設定';

  @override
  String get serviceDetailsTitle => '服務詳細資訊';

  @override
  String get serviceDetailsSubtitle => '廣播狀態、已連線裝置、活動紀錄';

  @override
  String get reportIssueTitle => '回報問題';

  @override
  String get reportIssueSubtitle => '開啟 HotkeyPad 的 GitHub 頁面';
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
  String pinChallengeNewDevice(String name) {
    return '$name 想要連線——代碼:';
  }

  @override
  String get newDeviceFallback => '有新裝置';

  @override
  String get pinChallengeReject => '拒絕——不允許這個裝置連線';

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

  @override
  String get deckLayoutTitle => '面板配置';

  @override
  String get deckLayoutHint => '點擊按鈕格以選擇它的功能。拖曳按鈕可以移動它,也可以拖到其他頁面。';

  @override
  String get previewOrientationTooltip => '預覽直向／橫向';

  @override
  String get settingsTitle => '設定';

  @override
  String get appearanceSectionHeader => '外觀';

  @override
  String get themeSystem => '自動';

  @override
  String get themeLight => '淺色';

  @override
  String get themeDark => '深色';

  @override
  String get buttonLabelsToggleTitle => '按鈕文字標籤';

  @override
  String get buttonLabelsToggleSubtitle => '關閉後按鈕格會變成正方形,並讓圖示填滿整個格子';

  @override
  String get backgroundImageSectionHeader => '背景圖片';

  @override
  String get chooseImageAction => '選擇圖片…';

  @override
  String get noBackgroundOption => '無';

  @override
  String get backgroundSpring => '春天';

  @override
  String get backgroundSummer => '夏天';

  @override
  String get backgroundAutumn => '秋天';

  @override
  String get backgroundWinter => '冬天';

  @override
  String get backgroundSunny => '晴天';

  @override
  String get backgroundCloudy => '多雲';

  @override
  String get backgroundRainy => '雨天';

  @override
  String get backgroundSnowy => '下雪';

  @override
  String get backgroundMountains => '山巒';

  @override
  String get opacityLabel => '不透明度';

  @override
  String get backgroundFitCover => '填滿螢幕';

  @override
  String get backgroundFitContain => '完整顯示圖片';

  @override
  String get backgroundFitStretch => '拉伸';

  @override
  String get gridSectionHeader => '格線';

  @override
  String get columnsLabel => '欄數';

  @override
  String get rowsLabel => '列數';

  @override
  String get pagesLabel => '頁數';

  @override
  String get backupSectionHeader => '備份';

  @override
  String get exportSettingsTitle => '匯出設定…';

  @override
  String get exportSettingsSubtitle => '將外觀、版面配置與自訂圖示儲存成檔案';

  @override
  String get importSettingsTitle => '匯入設定…';

  @override
  String get importSettingsSubtitle => '以備份檔取代目前的設定';

  @override
  String get serviceDetailsTitle => '服務詳細資訊';

  @override
  String get serviceDetailsSubtitle => '廣播狀態、已連線裝置、活動紀錄';

  @override
  String get reportIssueTitle => '回報問題';

  @override
  String get reportIssueSubtitle => '開啟 HotkeyPad 的 GitHub 頁面';
}
