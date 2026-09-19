// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get lookingForHost => 'ホストを検索中';

  @override
  String get startHostOnMac => 'Mac で HotkeyPad host を起動してください。';

  @override
  String get noHostFound => 'ホストが見つかりません';

  @override
  String get searchAgain => '再検索';

  @override
  String get enterHostIpManually => 'ホストの IP を手入力';

  @override
  String get scanQrCode => 'QR コードをスキャン';

  @override
  String get debugConsole => 'デバッグコンソール';

  @override
  String get previousHosts => '接続履歴';

  @override
  String get forgetHost => '削除';

  @override
  String get enterHostIpTitle => 'ホストの IP を入力';

  @override
  String get enterHostIpHint => 'host 側のステータスカードの WiFi 欄に表示されています。';

  @override
  String get ipAddressLabel => 'IP アドレス';

  @override
  String get ipAddressExample => '例：192.168.1.23';

  @override
  String get invalidHostAddress => '192.168.1.23 のような正しい IP アドレスを入力してください。';

  @override
  String get advancedCustomPort => '詳細設定:ポート番号を指定';

  @override
  String get portLabel => 'ポート番号';

  @override
  String get cancel => 'キャンセル';

  @override
  String get connectAction => '接続';

  @override
  String connectingTo(String name) {
    return '$name に接続中';
  }

  @override
  String reconnectingTo(String name) {
    return '$name に再接続中';
  }

  @override
  String get discoveringServices => 'サービスを探索中';

  @override
  String get subscribingStage => '購読中';

  @override
  String enterCodeShownOn(String name) {
    return '$name に表示されているコードを入力してください';
  }

  @override
  String get disconnectedStage => '接続が切断されました';

  @override
  String get couldNotConnect => '接続できませんでした';

  @override
  String linkLostTo(String name) {
    return '$name との接続が失われました。';
  }

  @override
  String get incorrectPinRetrying => 'コードが間違っています。host に新しいコードを再要求しています…';

  @override
  String get couldNotFindAddress => 'その住所が見つかりませんでした。確認してもう一度お試しください。';

  @override
  String get retryingNow => '再試行しています…';

  @override
  String retryingInSeconds(int seconds, int attempt) {
    return '$seconds 秒後に再試行・$attempt 回目';
  }

  @override
  String get back => '戻る';

  @override
  String get retry => '再試行';

  @override
  String get retryNow => '今すぐ再試行';

  @override
  String get syncing => '同期中…';

  @override
  String get pairViaQr => 'QR コードでペアリング';

  @override
  String get scanHostQrTitle => 'ホストの QR コードをスキャン';

  @override
  String get pointCameraAtQr => 'host に表示されている QR コードにカメラを向けてください';

  @override
  String get invalidHostQr => 'これは HotkeyPad host の QR コードではありません';

  @override
  String get cameraPermissionDenied => 'QR コードのスキャンにはカメラへのアクセスが必要です';

  @override
  String get openSettings => '設定を開く';

  @override
  String get language => '言語';

  @override
  String get systemDefaultLanguage => 'システム標準';

  @override
  String get howToUseTitle => '使い方';

  @override
  String get connectionMethodTitle => '接続方法を選択';

  @override
  String get connectionMethodSubtitle => '後で設定から変更できます。';

  @override
  String get connectionMethodBluetooth => 'Bluetooth';

  @override
  String get connectionMethodBluetoothHint =>
      '近くで Bluetooth によりアドバタイズしている host をスキャンします。';

  @override
  String get connectionMethodWifi => 'WiFi';

  @override
  String get connectionMethodWifiHint => '同じネットワーク上の host を探すか、アドレスを直接入力します。';

  @override
  String get step1Title => 'HotkeyPad Host をインストール';

  @override
  String get step1Body =>
      'HotkeyPad Host はこのスマートフォンではなくパソコンで動作します。下のアドレスをタップしてコピーし、パソコンのブラウザで開いてください。';

  @override
  String get urlCopiedMessage => 'クリップボードにコピーしました';

  @override
  String get connectedHostLabel => '接続中の Host';

  @override
  String get connectionMethodSettingsTitle => '接続方法';

  @override
  String get settingsTitle => '設定';

  @override
  String get done => '完了';

  @override
  String get reportIssueTitle => '問題を報告';

  @override
  String get reportIssueSubtitle => 'HotkeyPad の GitHub リポジトリを開きます';

  @override
  String get nearbyDevices => '近くのデバイス';

  @override
  String get notConnectedToHostYet => 'まだ host に接続していません。';

  @override
  String get noTrafficYet => 'まだ通信がありません。';

  @override
  String get sendRawTextHint => 'host に送るテキストを入力';

  @override
  String get messageFromHost => 'host';

  @override
  String get messageSent => '送信';

  @override
  String get debugStageConnecting => '接続中';

  @override
  String get debugStageDiscovering => 'サービスを検索中';

  @override
  String get debugStageSubscribing => '購読中';

  @override
  String get debugStageAwaitingPin => 'host に表示されたコードを入力してください';

  @override
  String get debugStageReady => '接続済み';

  @override
  String get debugStageDisconnected => '切断されました';

  @override
  String get debugStageFailed => '失敗しました';

  @override
  String mtuLabel(int mtu) {
    return 'MTU $mtu';
  }

  @override
  String get clearDeviceList => 'リストをクリア';

  @override
  String hotkeypadHostsCount(int count) {
    return 'HotkeyPad host ($count)';
  }

  @override
  String devicesShownCount(int count) {
    return '$count 件表示中';
  }

  @override
  String get unknownDevice => '不明なデバイス';

  @override
  String get hostBadge => 'HOST';

  @override
  String deviceSubtitle(String id, int rssi, int seconds) {
    return '$id\n$rssi dBm  ·  $seconds秒前に検出';
  }

  @override
  String get turnBluetoothOnFirst => '先に Bluetooth をオンにしてください。';

  @override
  String get bluetoothPermissionDeniedSnackbar => 'Bluetooth の権限が拒否されました。';

  @override
  String get bluetoothOff => 'Bluetooth はオフになっています。';

  @override
  String get bluetoothUnauthorized => 'Bluetooth の権限がまだ許可されていません。';

  @override
  String get bluetoothUnsupported => 'この端末は Bluetooth Low Energy に対応していません。';

  @override
  String get bluetoothCheckingAdapter => 'Bluetooth アダプターを確認しています...';

  @override
  String get grantAction => '許可';

  @override
  String get scanningForDevices => 'デバイスをスキャン中...';

  @override
  String get tapScanToLookForDevices => 'スキャンをタップして近くのデバイスを探します。';

  @override
  String get stopScan => 'スキャン停止';

  @override
  String get scanAction => 'スキャン';
}
