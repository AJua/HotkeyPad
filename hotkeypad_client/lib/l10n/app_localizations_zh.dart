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

  @override
  String get language => '語言';

  @override
  String get systemDefaultLanguage => '跟隨系統';

  @override
  String get connectionMethodTitle => '選擇連線方式';

  @override
  String get connectionMethodSubtitle => '之後可以在設定中變更，這個選擇只儲存在這支手機上。';

  @override
  String get connectionMethodBluetooth => '藍牙';

  @override
  String get connectionMethodBluetoothHint => '掃描附近以藍牙廣播的 host。';

  @override
  String get connectionMethodWifi => 'WiFi';

  @override
  String get connectionMethodWifiHint => '在同一網路中尋找 host，或手動輸入位址。';

  @override
  String get connectionMethodSettingsTitle => '連線方式';

  @override
  String get settingsTitle => '設定';

  @override
  String get done => '完成';

  @override
  String get nearbyDevices => '附近裝置';

  @override
  String get notConnectedToHostYet => '尚未連上 host。';

  @override
  String get noTrafficYet => '尚無任何流量。';

  @override
  String get sendRawTextHint => '傳送原始文字給 host';

  @override
  String get messageFromHost => 'host';

  @override
  String get messageSent => '已送出';

  @override
  String get debugStageConnecting => '連線中';

  @override
  String get debugStageDiscovering => '正在探索服務';

  @override
  String get debugStageSubscribing => '訂閱中';

  @override
  String get debugStageAwaitingPin => '請輸入 host 上顯示的代碼';

  @override
  String get debugStageReady => '已連線';

  @override
  String get debugStageDisconnected => '已中斷連線';

  @override
  String get debugStageFailed => '連線失敗';

  @override
  String mtuLabel(int mtu) {
    return 'MTU $mtu';
  }

  @override
  String get clearDeviceList => '清除清單';

  @override
  String hotkeypadHostsCount(int count) {
    return 'HotkeyPad host（$count）';
  }

  @override
  String devicesShownCount(int count) {
    return '顯示 $count 個';
  }

  @override
  String get unknownDevice => '未知裝置';

  @override
  String get hostBadge => 'HOST';

  @override
  String deviceSubtitle(String id, int rssi, int seconds) {
    return '$id\n$rssi dBm  ·  $seconds 秒前發現';
  }

  @override
  String get turnBluetoothOnFirst => '請先開啟藍牙。';

  @override
  String get bluetoothPermissionDeniedSnackbar => '藍牙權限被拒絕。';

  @override
  String get bluetoothOff => '藍牙已關閉。';

  @override
  String get bluetoothUnauthorized => '尚未取得藍牙權限。';

  @override
  String get bluetoothUnsupported => '這個裝置不支援低功耗藍牙。';

  @override
  String get bluetoothCheckingAdapter => '正在確認藍牙狀態...';

  @override
  String get grantAction => '授權';

  @override
  String get scanningForDevices => '正在掃描裝置...';

  @override
  String get tapScanToLookForDevices => '點選「掃描」尋找附近裝置。';

  @override
  String get stopScan => '停止掃描';

  @override
  String get scanAction => '掃描';
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

  @override
  String get language => '語言';

  @override
  String get systemDefaultLanguage => '跟隨系統';

  @override
  String get connectionMethodTitle => '選擇連線方式';

  @override
  String get connectionMethodSubtitle => '之後可以在設定中變更，這個選擇只儲存在這支手機上。';

  @override
  String get connectionMethodBluetooth => '藍牙';

  @override
  String get connectionMethodBluetoothHint => '掃描附近以藍牙廣播的 host。';

  @override
  String get connectionMethodWifi => 'WiFi';

  @override
  String get connectionMethodWifiHint => '在同一網路中尋找 host，或手動輸入位址。';

  @override
  String get connectionMethodSettingsTitle => '連線方式';

  @override
  String get settingsTitle => '設定';

  @override
  String get done => '完成';

  @override
  String get nearbyDevices => '附近裝置';

  @override
  String get notConnectedToHostYet => '尚未連上 host。';

  @override
  String get noTrafficYet => '尚無任何流量。';

  @override
  String get sendRawTextHint => '傳送原始文字給 host';

  @override
  String get messageFromHost => 'host';

  @override
  String get messageSent => '已送出';

  @override
  String get debugStageConnecting => '連線中';

  @override
  String get debugStageDiscovering => '正在探索服務';

  @override
  String get debugStageSubscribing => '訂閱中';

  @override
  String get debugStageAwaitingPin => '請輸入 host 上顯示的代碼';

  @override
  String get debugStageReady => '已連線';

  @override
  String get debugStageDisconnected => '已中斷連線';

  @override
  String get debugStageFailed => '連線失敗';

  @override
  String mtuLabel(int mtu) {
    return 'MTU $mtu';
  }

  @override
  String get clearDeviceList => '清除清單';

  @override
  String hotkeypadHostsCount(int count) {
    return 'HotkeyPad host（$count）';
  }

  @override
  String devicesShownCount(int count) {
    return '顯示 $count 個';
  }

  @override
  String get unknownDevice => '未知裝置';

  @override
  String get hostBadge => 'HOST';

  @override
  String deviceSubtitle(String id, int rssi, int seconds) {
    return '$id\n$rssi dBm  ·  $seconds 秒前發現';
  }

  @override
  String get turnBluetoothOnFirst => '請先開啟藍牙。';

  @override
  String get bluetoothPermissionDeniedSnackbar => '藍牙權限被拒絕。';

  @override
  String get bluetoothOff => '藍牙已關閉。';

  @override
  String get bluetoothUnauthorized => '尚未取得藍牙權限。';

  @override
  String get bluetoothUnsupported => '這個裝置不支援低功耗藍牙。';

  @override
  String get bluetoothCheckingAdapter => '正在確認藍牙狀態...';

  @override
  String get grantAction => '授權';

  @override
  String get scanningForDevices => '正在掃描裝置...';

  @override
  String get tapScanToLookForDevices => '點選「掃描」尋找附近裝置。';

  @override
  String get stopScan => '停止掃描';

  @override
  String get scanAction => '掃描';
}
