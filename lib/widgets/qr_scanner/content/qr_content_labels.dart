import '../qr_scanner_labels.dart';
import 'qr_content.dart';

extension QrContentLabels on QrScannerLabels {
  String titleFor(QrContentKind kind) => switch (kind) {
        QrContentKind.url =>
          t(zhHans: '链接', zhHant: '連結', en: 'Link', ja: 'リンク', ko: '링크'),
        QrContentKind.text =>
          t(zhHans: '文本', zhHant: '文字', en: 'Text', ja: 'テキスト', ko: '텍스트'),
        QrContentKind.wifi => 'Wi-Fi',
        QrContentKind.contact =>
          t(zhHans: '联系人', zhHant: '聯絡人', en: 'Contact', ja: '連絡先', ko: '연락처'),
        QrContentKind.unknown => t(
            zhHans: '二维码内容',
            zhHant: '二維碼內容',
            en: 'QR contents',
            ja: 'QRコードの内容',
            ko: 'QR 내용'),
      };
  String get openBrowser => t(
      zhHans: '在应用内打开',
      zhHant: '在應用程式內開啟',
      en: 'Open in app',
      ja: 'アプリ内で開く',
      ko: '앱 내에서 열기');
  String get copyRaw => t(
      zhHans: '复制原文',
      zhHant: '複製原文',
      en: 'Copy original text',
      ja: '原文をコピー',
      ko: '원문 복사');
  String get copySsid => t(
      zhHans: '复制网络名称',
      zhHant: '複製網路名稱',
      en: 'Copy network name',
      ja: 'ネットワーク名をコピー',
      ko: '네트워크 이름 복사');
  String get copyPassword => t(
      zhHans: '复制密码',
      zhHant: '複製密碼',
      en: 'Copy password',
      ja: 'パスワードをコピー',
      ko: '비밀번호 복사');
  String get wifiHint => t(
      zhHans: '复制后可前往系统 Wi-Fi 设置连接',
      zhHant: '複製後可前往系統 Wi-Fi 設定連線',
      en: 'Copy details, then connect in system Wi-Fi settings.',
      ja: 'コピー後、システムのWi-Fi設定から接続してください。',
      ko: '복사 후 시스템 Wi-Fi 설정에서 연결하세요.');
  String get saveContact => t(
      zhHans: '导出联系人',
      zhHant: '匯出聯絡人',
      en: 'Export contact',
      ja: '連絡先をエクスポート',
      ko: '연락처 내보내기');
  String get copyDone =>
      t(zhHans: '已复制', zhHant: '已複製', en: 'Copied', ja: 'コピーしました', ko: '복사됨');
  String get unknownHint => t(
      zhHans: '暂不支持此内容的快捷操作，可查看或复制原文',
      zhHant: '暫不支援此內容的快捷操作，可查看或複製原文',
      en: 'No action is available for this content. View or copy the original text.',
      ja: 'この内容の操作には未対応です。原文を表示・コピーできます。',
      ko: '이 내용의 작업을 지원하지 않습니다. 원문을 보거나 복사할 수 있습니다.');
  String get actionFailed => t(
      zhHans: '操作未完成，请重试或复制内容',
      zhHant: '操作未完成，請重試或複製內容',
      en: 'Action could not be completed. Retry or copy the content.',
      ja: '操作を完了できません。再試行するか内容をコピーしてください。',
      ko: '작업을 완료하지 못했습니다. 다시 시도하거나 내용을 복사하세요.');
}
