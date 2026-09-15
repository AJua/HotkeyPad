// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get lookingForHost => '正在尋找 Host';

  @override
  String get startHostOnMac => '請在你的 Mac 上啟動 HotkeyPad host。';

  @override
  String get noHostFound => '找不到 Host';

  @override
  String get searchAgain => '重新搜尋';

  @override
  String get enterHostIpManually => '手動輸入 Host IP';

  @override
  String get scanQrCode => '掃描 QR Code';

  @override
  String get debugConsole => '除錯主控台';

  @override
  String get previousHosts => '過去連線過的 Host';

  @override
  String get forgetHost => '移除';

  @override
  String get enterHostIpTitle => '輸入 Host IP';

  @override
  String get enterHostIpHint => '在 host 本身的狀態卡片、WiFi 欄位下可以看到。';

  @override
  String get ipAddressLabel => 'IP 位址';

  @override
  String get advancedCustomPort => '進階:自訂連接埠';

  @override
  String get portLabel => '連接埠';

  @override
  String get cancel => '取消';

  @override
  String get connectAction => '連線';

  @override
  String connectingTo(String name) {
    return '正在連線到 $name';
  }

  @override
  String reconnectingTo(String name) {
    return '正在重新連線到 $name';
  }

  @override
  String get discoveringServices => '正在探索服務';

  @override
  String get subscribingStage => '正在訂閱';

  @override
  String enterCodeShownOn(String name) {
    return '請輸入 $name 上顯示的代碼';
  }

  @override
  String get disconnectedStage => '已中斷連線';

  @override
  String get couldNotConnect => '無法連線';

  @override
  String linkLostTo(String name) {
    return '與 $name 的連線已中斷。';
  }

  @override
  String get retryingNow => '正在重試...';

  @override
  String retryingInSeconds(int seconds, int attempt) {
    return '$seconds 秒後重試・第 $attempt 次嘗試';
  }

  @override
  String get back => '返回';

  @override
  String get retry => '重試';

  @override
  String get retryNow => '立即重試';

  @override
  String get syncing => '同步中…';

  @override
  String get pairViaQr => '以 QR Code 配對';

  @override
  String get scanHostQrTitle => '掃描 Host QR Code';

  @override
  String get pointCameraAtQr => '將相機對準 host 上顯示的 QR Code';

  @override
  String get invalidHostQr => '這不是 HotkeyPad host 的 QR Code';

  @override
  String get cameraPermissionDenied => '需要相機權限才能掃描 QR Code';

  @override
  String get openSettings => '開啟設定';
}

/// The translations for Chinese, using the Han script (`zh_Hant`).
class AppLocalizationsZhHant extends AppLocalizationsZh {
  AppLocalizationsZhHant() : super('zh_Hant');

  @override
  String get lookingForHost => '正在尋找 Host';

  @override
  String get startHostOnMac => '請在你的 Mac 上啟動 HotkeyPad host。';

  @override
  String get noHostFound => '找不到 Host';

  @override
  String get searchAgain => '重新搜尋';

  @override
  String get enterHostIpManually => '手動輸入 Host IP';

  @override
  String get scanQrCode => '掃描 QR Code';

  @override
  String get debugConsole => '除錯主控台';

  @override
  String get previousHosts => '過去連線過的 Host';

  @override
  String get forgetHost => '移除';

  @override
  String get enterHostIpTitle => '輸入 Host IP';

  @override
  String get enterHostIpHint => '在 host 本身的狀態卡片、WiFi 欄位下可以看到。';

  @override
  String get ipAddressLabel => 'IP 位址';

  @override
  String get advancedCustomPort => '進階:自訂連接埠';

  @override
  String get portLabel => '連接埠';

  @override
  String get cancel => '取消';

  @override
  String get connectAction => '連線';

  @override
  String connectingTo(String name) {
    return '正在連線到 $name';
  }

  @override
  String reconnectingTo(String name) {
    return '正在重新連線到 $name';
  }

  @override
  String get discoveringServices => '正在探索服務';

  @override
  String get subscribingStage => '正在訂閱';

  @override
  String enterCodeShownOn(String name) {
    return '請輸入 $name 上顯示的代碼';
  }

  @override
  String get disconnectedStage => '已中斷連線';

  @override
  String get couldNotConnect => '無法連線';

  @override
  String linkLostTo(String name) {
    return '與 $name 的連線已中斷。';
  }

  @override
  String get retryingNow => '正在重試...';

  @override
  String retryingInSeconds(int seconds, int attempt) {
    return '$seconds 秒後重試・第 $attempt 次嘗試';
  }

  @override
  String get back => '返回';

  @override
  String get retry => '重試';

  @override
  String get retryNow => '立即重試';

  @override
  String get syncing => '同步中…';

  @override
  String get pairViaQr => '以 QR Code 配對';

  @override
  String get scanHostQrTitle => '掃描 Host QR Code';

  @override
  String get pointCameraAtQr => '將相機對準 host 上顯示的 QR Code';

  @override
  String get invalidHostQr => '這不是 HotkeyPad host 的 QR Code';

  @override
  String get cameraPermissionDenied => '需要相機權限才能掃描 QR Code';

  @override
  String get openSettings => '開啟設定';
}
