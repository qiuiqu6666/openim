import 'package:flutter/material.dart';

import '../../../../widgets/qr_scanner/qr_scanner_overlay.dart';

export '../../../../widgets/qr_scanner/qr_scanner_overlay.dart';

/// Compatibility for callers using the original two-language helper.
String scannerText(BuildContext context, String zh, String en) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

typedef FriendQrScannerLayout = QrScannerLayout;

/// Existing overlay imports retain their original action keys.
class FriendQrScannerOverlay extends QrScannerOverlay {
  const FriendQrScannerOverlay({
    super.key,
    required super.layout,
    required super.animation,
    required super.onBack,
    required super.onAlbum,
    required super.onFlash,
    required super.onMyQr,
    required super.flashOn,
  }) : super(keyPrefix: 'friend-qr');
}
