import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/controller/im_controller.dart';
import '../../../widgets/qr_scanner/qr_scanner_page.dart';
import '../../mine/settings/pages/qr_profile_page.dart';
import '../host/wallet_navigation.dart';

/// Shares the friend scanner's camera, album recognition and presentation.
/// Callers keep ownership of address validation and subsequent wallet actions.
class WalletQrScannerPage extends StatelessWidget {
  const WalletQrScannerPage({
    super.key,
    this.gallery = const QrGalleryService(),
    this.onMyQrTap,
  });

  final QrGalleryService gallery;
  final Future<void> Function()? onMyQrTap;

  static String? _readCode(String code) {
    final value = code.trim();
    return value.isEmpty ? null : value;
  }

  @override
  Widget build(BuildContext context) => QrScannerPage<String>(
        parseCode: _readCode,
        gallery: gallery,
        keyPrefix: 'wallet-qr',
        onMyQrTap: onMyQrTap ??
            (Get.isRegistered<IMController>()
                ? () async {
                    final user = Get.find<IMController>().userInfo.value;
                    await openWalletPage<void>(
                      context,
                      QrProfilePage(
                        nickname: user.nickname ?? '',
                        userId: user.userID ?? '',
                        account: user.account?.trim() ?? '',
                        avatarUrl: user.faceURL ?? '',
                      ),
                    );
                  }
                : null),
      );
}
