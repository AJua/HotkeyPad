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
}
