import '../qr_scanner_labels.dart';
import 'qr_gallery_result.dart';

extension QrGalleryLabels on QrScannerLabels {
  String get chooseCode => t(
      zhHans: '选择二维码',
      zhHant: '選擇二維碼',
      en: 'Choose a QR code',
      ja: 'QRコードを選択',
      ko: 'QR 코드 선택');
  String get scanningImage => t(
      zhHans: '正在识别图片…',
      zhHant: '正在識別圖片…',
      en: 'Reading image…',
      ja: '画像を読み取り中…',
      ko: '이미지 인식 중…');
  String get cancelScan =>
      t(zhHans: '取消', zhHant: '取消', en: 'Cancel', ja: 'キャンセル', ko: '취소');
  String get partialScan => t(
      zhHans: '已显示识别到的二维码，图片中可能还有其他二维码。',
      zhHant: '已顯示識別到的二維碼，圖片中可能還有其他二維碼。',
      en: 'These codes were found. The image may contain more.',
      ja: '検出されたコードです。他にも存在する可能性があります。',
      ko: '찾은 코드입니다. 이미지에 다른 코드가 있을 수 있습니다.');
  String get loginCode => t(
      zhHans: '99Chat 登录请求（需确认）',
      zhHant: '99Chat 登入請求（需確認）',
      en: '99Chat login request (confirmation required)',
      ja: '99Chatログイン要求（確認が必要）',
      ko: '99Chat 로그인 요청 (확인 필요)');
  String failure(QrGalleryStatus status) => switch (status) {
        QrGalleryStatus.unavailable => t(
            zhHans: '识别组件暂不可用，请重新启动应用或更新版本',
            zhHant: '識別元件暫不可用，請重新啟動應用或更新版本',
            en: 'QR recognition is unavailable. Restart or update the app.',
            ja: 'QR認識を利用できません。アプリを再起動または更新してください。',
            ko: 'QR 인식을 사용할 수 없습니다. 앱을 다시 시작하거나 업데이트하세요.'),
        QrGalleryStatus.tooLarge => t(
            zhHans: '图片过大，请裁剪二维码附近区域后重试',
            zhHant: '圖片過大，請裁剪二維碼附近區域後重試',
            en: 'Image is too large. Crop around the QR code and retry.',
            ja: '画像が大きすぎます。QRコード付近を切り抜いてください。',
            ko: '이미지가 너무 큽니다. QR 코드 주변을 잘라 다시 시도하세요.'),
        QrGalleryStatus.timeout => t(
            zhHans: '识别超时，请裁剪二维码附近区域或选择更清晰的图片',
            zhHant: '識別逾時，請裁剪二維碼附近區域或選擇更清晰的圖片',
            en: 'Recognition timed out. Crop around the code or choose a clearer image.',
            ja: '時間切れです。切り抜くか、鮮明な画像を選んでください。',
            ko: '인식 시간이 초과됐습니다. 코드를 자르거나 선명한 이미지를 선택하세요.'),
        QrGalleryStatus.invalidImage => t(
            zhHans: '图片已损坏或格式暂不支持，请换一张图片',
            zhHant: '圖片已損壞或格式暫不支援，請換一張圖片',
            en: 'Image is damaged or unsupported. Choose another image.',
            ja: '画像が破損しているか未対応の形式です。',
            ko: '손상되었거나 지원하지 않는 이미지입니다.'),
        QrGalleryStatus.noCode => t(
            zhHans: '未找到二维码，请选择清晰、完整的二维码图片',
            zhHant: '未找到二維碼，請選擇清晰、完整的二維碼圖片',
            en: 'No QR code found. Choose a clear image with a complete code.',
            ja: 'QRコードが見つかりません。鮮明で欠けていない画像を選んでください。',
            ko: 'QR 코드를 찾지 못했습니다. 전체 코드가 선명한 이미지를 선택하세요.'),
        _ => readImageFailed,
      };
}
