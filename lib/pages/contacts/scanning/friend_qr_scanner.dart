import 'package:openim/routes/swipe_back/app_page_route.dart';
import 'package:flutter/material.dart';

import '../../../widgets/qr_scanner/qr_scanner_page.dart';
import 'contact_qr_result.dart';
import 'friend_qr_gallery_service.dart';

/// Returns a validated friend or group invitation. Kept as a compatible entry.
Future<Map<String, String>?> scanFriendQrCode(BuildContext context,
        {Future<void> Function()? onMyQrTap}) =>
    Navigator.of(context).push<Map<String, String>>(
      AppMaterialPageRoute(
          builder: (_) => FriendQrScanner(onMyQrTap: onMyQrTap)),
    );

/// Compatibility wrapper retains the original widget and State identity.
class FriendQrScanner extends StatefulWidget {
  const FriendQrScanner(
      {super.key,
      this.onMyQrTap,
      this.gallery = const FriendQrGalleryService()});

  final Future<void> Function()? onMyQrTap;
  final FriendQrGalleryService gallery;

  @override
  State<FriendQrScanner> createState() => _FriendQrScannerState();
}

class _FriendQrScannerState extends State<FriendQrScanner> {
  @override
  Widget build(BuildContext context) => QrScannerPage<Map<String, String>>(
        parseCode: parseContactQrResult,
        gallery: widget.gallery,
        keyPrefix: 'friend-qr',
        onMyQrTap: widget.onMyQrTap,
        invalidCodeMessage: (context) => QrScannerLabels.of(context).t(
          zhHans: '未识别到有效的好友或群二维码',
          zhHant: '未識別到有效的好友或群組二維碼',
          en: 'No valid friend or group QR code found',
          ja: '有効な友達またはグループのQRコードが見つかりません',
          ko: '유효한 친구 또는 그룹 QR 코드를 찾지 못했습니다',
        ),
      );
}
