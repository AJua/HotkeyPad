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

  @override
  String get deckLayoutTitle => 'デッキレイアウト';

  @override
  String get deckLayoutHint =>
      'セルをクリックして機能を選択します。ボタンをドラッグすると移動できます(別のページへの移動も可能です)。';

  @override
  String get settingsTitle => '設定';

  @override
  String get appearanceSectionHeader => '外観';

  @override
  String get themeSystem => '自動';

  @override
  String get themeLight => 'ライト';

  @override
  String get themeDark => 'ダーク';

  @override
  String get appBarToggleTitle => 'アプリバー';

  @override
  String get appBarToggleSubtitle =>
      'オフにするとタイトルとデバッグコンソールボタンが非表示になり、画面全体がデッキに使われます';

  @override
  String get buttonLabelsToggleTitle => 'ボタンラベル';

  @override
  String get buttonLabelsToggleSubtitle => 'オフにするとセルが正方形になり、アイコンがセル全体を埋めます';

  @override
  String get pageDotsToggleTitle => 'ページドット';

  @override
  String get pageDotsToggleSubtitle =>
      'オフにすると複数ページのデッキ下部のページインジケーターが非表示になります(ページ間のスワイプは引き続き機能します)';

  @override
  String get backgroundImageSectionHeader => '背景画像';

  @override
  String get chooseImageAction => '画像を選択…';

  @override
  String get changeImageAction => '変更…';

  @override
  String get removeImageAction => '削除';

  @override
  String get opacityLabel => '不透明度';

  @override
  String get backgroundFitCover => '画面いっぱいに表示';

  @override
  String get backgroundFitContain => '画像全体を表示';

  @override
  String get backgroundFitStretch => '引き伸ばす';

  @override
  String get gridSectionHeader => 'グリッド';

  @override
  String get columnsLabel => '列';

  @override
  String get rowsLabel => '行';

  @override
  String get pagesLabel => 'ページ数';

  @override
  String get backupSectionHeader => 'バックアップ';

  @override
  String get exportSettingsTitle => '設定をエクスポート…';

  @override
  String get exportSettingsSubtitle => '外観、レイアウト、カスタムアイコンをファイルに保存します';

  @override
  String get importSettingsTitle => '設定をインポート…';

  @override
  String get importSettingsSubtitle => 'バックアップファイルで現在の設定を置き換えます';

  @override
  String get serviceDetailsTitle => 'サービスの詳細';

  @override
  String get serviceDetailsSubtitle => 'アドバタイズ状態、接続中のデバイス、アクティビティログ';
}
