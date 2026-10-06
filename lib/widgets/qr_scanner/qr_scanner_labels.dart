import 'package:flutter/widgets.dart';

/// Scanner UI language selection, independent of any business module.
class QrScannerLabels {
  const QrScannerLabels(this.locale);

  final Locale locale;

  static QrScannerLabels of(BuildContext context) =>
      QrScannerLabels(Localizations.localeOf(context));

  String t({
    required String zhHans,
    required String zhHant,
    required String en,
    required String ja,
    required String ko,
  }) {
    final language = locale.languageCode.toLowerCase();
    if (language == 'ja') return ja;
    if (language == 'ko') return ko;
    if (language == 'zh') {
      final script = locale.scriptCode?.toLowerCase();
      final country = locale.countryCode?.toUpperCase();
      if (script == 'hant' ||
          country == 'TW' ||
          country == 'HK' ||
          country == 'MO') {
        return zhHant;
      }
      return zhHans;
    }
    return en;
  }

  String get title =>
      t(zhHans: '扫一扫', zhHant: '掃一掃', en: 'Scan', ja: 'スキャン', ko: '스캔');
  String get album =>
      t(zhHans: '相册', zhHant: '相簿', en: 'Album', ja: 'アルバム', ko: '앨범');
  String get instruction => t(
      zhHans: '请将镜头对准二维码进行扫描',
      zhHant: '請將鏡頭對準二維碼進行掃描',
      en: 'Point the camera at a QR code',
      ja: 'カメラをQRコードに向けてください',
      ko: '카메라를 QR 코드에 맞춰 주세요');
  String get myQr => t(
      zhHans: '我的二维码',
      zhHant: '我的二維碼',
      en: 'My QR Code',
      ja: '自分のQRコード',
      ko: '내 QR 코드');
  String get flashOn => t(
      zhHans: '打开闪光灯',
      zhHant: '開啟閃光燈',
      en: 'Turn On Flash',
      ja: 'ライトをオン',
      ko: '플래시 켜기');
  String get flashOff => t(
      zhHans: '关闭闪光灯',
      zhHant: '關閉閃光燈',
      en: 'Turn Off Flash',
      ja: 'ライトをオフ',
      ko: '플래시 끄기');
  String get flashUnavailable => t(
      zhHans: '闪光灯暂时无法使用',
      zhHant: '閃光燈暫時無法使用',
      en: 'Flash is unavailable',
      ja: 'ライトを使用できません',
      ko: '플래시를 사용할 수 없습니다');
  String get invalidCode => t(
      zhHans: '未识别到有效的二维码',
      zhHant: '未識別到有效的二維碼',
      en: 'No valid QR code found',
      ja: '有効なQRコードが見つかりません',
      ko: '유효한 QR 코드를 찾지 못했습니다');
  String get readImageFailed => t(
      zhHans: '无法读取图片，请检查相册权限后重试',
      zhHant: '無法讀取圖片，請檢查相簿權限後重試',
      en: 'Unable to read image. Check photo permission and try again.',
      ja: '画像を読み込めません。写真へのアクセス許可を確認して再試行してください。',
      ko: '이미지를 읽을 수 없습니다. 사진 접근 권한을 확인한 후 다시 시도해 주세요.');
  String get cameraDenied => t(
      zhHans: '请允许使用相机，或从相册选择二维码',
      zhHant: '請允許使用相機，或從相簿選擇二維碼',
      en: 'Allow camera access or choose a QR image from Album',
      ja: 'カメラへのアクセスを許可するか、アルバムからQRコードを選択してください',
      ko: '카메라 접근을 허용하거나 앨범에서 QR 이미지를 선택해 주세요');
  String get cameraFailed => t(
      zhHans: '相机启动失败，请重试或从相册选择',
      zhHant: '相機啟動失敗，請重試或從相簿選擇',
      en: 'Unable to start camera. Retry or choose an image.',
      ja: 'カメラを起動できません。再試行するか、画像を選択してください。',
      ko: '카메라를 시작할 수 없습니다. 다시 시도하거나 이미지를 선택해 주세요.');
  String get openSettings => t(
      zhHans: '前往设置',
      zhHant: '前往設定',
      en: 'Open Settings',
      ja: '設定を開く',
      ko: '설정 열기');
  String get retry =>
      t(zhHans: '重试', zhHant: '重試', en: 'Retry', ja: '再試行', ko: '다시 시도');
}
