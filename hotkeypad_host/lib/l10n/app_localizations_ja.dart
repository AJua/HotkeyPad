// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get serviceTitle => 'サービス';

  @override
  String get backToDeck => 'デッキに戻る';

  @override
  String get language => '言語';

  @override
  String get systemDefaultLanguage => 'システム標準';

  @override
  String get accessibilityNotGranted => 'アクセシビリティが許可されていません';

  @override
  String get accessibilityNotGrantedBody =>
      'システム設定でこの App を許可するまで、メディアキーとキーの組み合わせは機能しません';

  @override
  String get grant => '許可する';

  @override
  String connectedClients(int count) {
    return '接続中のデバイス($count)';
  }

  @override
  String get noClientConnected => 'まだデバイスが接続されていません。';

  @override
  String notifySubscribed(int count) {
    return '購読中のデバイス $count 台に通知';
  }

  @override
  String get noSubscribedClient => '購読中のデバイスはまだありません';

  @override
  String get activity => 'アクティビティ';

  @override
  String get nothingYet => 'まだ何もありません。';

  @override
  String wifiPinNewDevice(String name) {
    return '$name が WiFi で接続しようとしています — コード:';
  }

  @override
  String get newDeviceFallback => '新しいデバイス';

  @override
  String get wifiPinReject => '拒否 — このデバイスの接続を許可しない';

  @override
  String updateAvailable(String version) {
    return 'HotkeyPad Host $version が利用可能です。';
  }

  @override
  String get viewAction => '表示';

  @override
  String get dismiss => '閉じる';

  @override
  String get pairViaQr => 'QR コードでペアリング';

  @override
  String get pairViaQrSubtitle => 'HotkeyPad アプリでスキャンすると接続できます';

  @override
  String get show => '表示';

  @override
  String get scanToConnect => 'スキャンして接続';

  @override
  String get done => '完了';
}
