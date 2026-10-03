import 'package:flutter/material.dart';
import 'host/wallet_toast.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'host/wallet_i18n.dart';
import 'host/wallet_responsive.dart';

import 'wallet_asset_record_screen.dart';
import 'wallet_share_service.dart';
import 'widgets/wallet_page_colors.dart';
import 'host/wallet_navigation.dart';

class WalletReceiveScreen extends StatefulWidget {
  final String addr;

  const WalletReceiveScreen({
    super.key,
    this.addr = '',
  });

  @override
  State<WalletReceiveScreen> createState() => _WalletReceiveScreenState();
}

class _WalletReceiveScreenState extends State<WalletReceiveScreen> {
  final GlobalKey _shotKey = GlobalKey();
  final WalletShareService _svc = WalletShareService();

  void _showMsg(String text) {
    ToastUtils.toast(text);
  }

  Future<void> _copyAddr() async {
    final i18n = AppI18n.of(context);
    final ret = await _svc.copyAddr(widget.addr);
    switch (ret) {
      case WalletCopyResult.success:
        _showMsg(i18n.t(
          zhHans: '地址已复制',
          zhHant: '地址已複製',
          en: 'Address copied',
          ja: 'アドレスをコピーしました',
          ko: '주소가 복사되었습니다',
        ));
        break;
      case WalletCopyResult.empty:
        _showMsg(i18n.t(
          zhHans: '地址暂不可用',
          zhHant: '地址暫不可用',
          en: 'Address unavailable',
          ja: 'アドレスは利用できません',
          ko: '주소를 사용할 수 없습니다',
        ));
        break;
      case WalletCopyResult.failed:
        _showMsg(i18n.t(
          zhHans: '复制失败，请重试',
          zhHant: '複製失敗，請重試',
          en: 'Copy failed. Please try again.',
          ja: 'コピーに失敗しました。もう一度お試しください。',
          ko: '복사에 실패했습니다. 다시 시도해 주세요.',
        ));
        break;
    }
  }

  Future<void> _openShareSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      builder: (_) => _SharePreviewSheet(
        svc: _svc,
        addr: widget.addr,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final i18n = AppI18n.of(context);
    final topColor = Theme.of(context).appBarTheme.foregroundColor ?? cs.text;
    final isDesktop = context.isDesktopFormFactor;

    return wrapWalletPage(
      context,
      Scaffold(
        backgroundColor: cs.bg,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final horizontal = (width * 0.06).clamp(18.0, 28.0);
            final iconSize = (width * 0.16).clamp(64.0, 86.0);
            final qrBox = (width * 0.76).clamp(260.0, 340.0);
            final qrSize = qrBox * 0.78;

            return DecoratedBox(
              decoration: BoxDecoration(
                color: cs.bg,
              ),
              child: SafeArea(
                bottom: false,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                            horizontal - 10, 4, horizontal, 0),
                        child: SizedBox(
                          height: 48,
                          child: Row(
                            children: [
                              IconButton(
                                onPressed: () => Navigator.of(
                                  context,
                                  rootNavigator: true,
                                ).maybePop(),
                                icon: Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  color: topColor,
                                  size: 24,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                onPressed: () {
                                  openWalletPage<void>(
                                    context,
                                    const WalletDepositRecordScreen(),
                                  );
                                },
                                icon: Icon(
                                  Icons.access_time_rounded,
                                  size: 24,
                                  color: topColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: RepaintBoundary(
                        key: _shotKey,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                              horizontal, 4, horizontal, 12),
                          child: Column(
                            children: [
                              SizedBox(height: width * 0.01),
                              _TokenBadge(size: iconSize),
                              SizedBox(height: width * 0.035),
                              Text(
                                i18n.t(
                                  zhHans: 'USDT 接收',
                                  zhHant: 'USDT 接收',
                                  en: 'Receive USDT',
                                  ja: 'USDT 受取',
                                  ko: 'USDT 받기',
                                ),
                                style: TextStyle(
                                  fontSize: isDesktop ? 32.0 : 28.0,
                                  fontWeight: FontWeight.w700,
                                  color: cs.text,
                                ),
                              ),
                              SizedBox(height: width * 0.018),
                              Text(
                                i18n.t(
                                  zhHans: '仅支持接收 Tron(TRC20) 网络资产',
                                  zhHant: '僅支援接收 Tron(TRC20) 網路資產',
                                  en: 'Only Tron (TRC20) network assets are supported.',
                                  ja: 'Tron（TRC20）ネットワークの資産のみ受取可能です。',
                                  ko: 'Tron(TRC20) 네트워크 자산만 받을 수 있습니다.',
                                ),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: isDesktop ? 16.0 : 15.0,
                                  fontWeight: FontWeight.w500,
                                  color: cs.subText,
                                ),
                              ),
                              SizedBox(height: width * 0.045),
                              _ReceiveQr(
                                data: widget.addr,
                                size: qrSize,
                              ),
                              SizedBox(height: width * 0.032),
                              Text(
                                i18n.t(
                                  zhHans: '最小充值数量 -- USDT',
                                  zhHant: '最小充值數量 -- USDT',
                                  en: 'Minimum deposit: -- USDT',
                                  ja: '最小入金数量 -- USDT',
                                  ko: '최소 입금 수량 -- USDT',
                                ),
                                style: TextStyle(
                                  fontSize: isDesktop ? 17.0 : 16.0,
                                  color: cs.warningText,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: width * 0.04),
                              _AddressCard(
                                addr: widget.addr,
                                onCopy: _copyAddr,
                              ),
                              const SizedBox(height: 12),
                              _WarnCard(i18n: i18n),
                              const SizedBox(height: 16),
                              _ShareButton(
                                saving: false,
                                onTap: _openShareSheet,
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ReceiveQr extends StatelessWidget {
  const _ReceiveQr({required this.data, required this.size});

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final value = data.trim();
    if (value.isEmpty) {
      return Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.qr_code_2_rounded,
              color: const Color(0xFFB9BDC5),
              size: size * .46,
            ),
            SizedBox(height: size * .035),
            Text(
              '--',
              style: const TextStyle(
                color: Color(0xFF9298A2),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    return QrImageView(
      data: value,
      version: QrVersions.auto,
      size: size,
      backgroundColor: Colors.white,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: Colors.black,
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Colors.black,
      ),
    );
  }
}

class _TokenBadge extends StatelessWidget {
  final double size;

  const _TokenBadge({
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final badge = size * 0.33;
    final iconSize = size * 0.72;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: const BoxDecoration(
              color: Color(0xFF24B47E),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: CustomPaint(
                size: Size(iconSize, iconSize),
                painter: _UsdtPainter(),
              ),
            ),
          ),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: badge,
              height: badge,
              decoration: BoxDecoration(
                color: const Color(0xFFFF2633),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Center(
                child: Text(
                  'T',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: badge * 0.42,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UsdtPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final fill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.08
      ..strokeCap = StrokeCap.round;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.08, h * 0.12, w * 0.84, h * 0.16),
        Radius.circular(w * 0.02),
      ),
      fill,
    );

    final stem = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.41, h * 0.12, w * 0.18, h * 0.76),
      Radius.circular(w * 0.02),
    );
    canvas.drawRRect(stem, fill);

    final oval = Rect.fromCenter(
      center: Offset(w / 2, h * 0.53),
      width: w * 0.92,
      height: h * 0.28,
    );
    canvas.drawArc(oval, 0.06, 6.16, false, stroke);

    final cover = Paint()
      ..color = const Color(0xFF24B47E)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(w * 0.35, h * 0.43, w * 0.30, h * 0.13),
      cover,
    );

    canvas.drawRRect(stem, fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AddressCard extends StatelessWidget {
  final String addr;
  final VoidCallback onCopy;

  const _AddressCard({
    required this.addr,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final i18n = AppI18n.of(context);
    final isDesktop = context.isDesktopFormFactor;
    final titleSize = isDesktop ? 18.0 : 17.0;
    final addrSize = isDesktop ? 15.0 : 14.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: cs.surfaceAlt,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            i18n.t(
              zhHans: '我的接收地址',
              zhHant: '我的接收地址',
              en: 'My Receive Address',
              ja: '我的受取アドレス',
              ko: '내 받기 주소',
            ),
            style: TextStyle(
              fontSize: titleSize,
              color: cs.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 9),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _AddressRichText(
                  addr: addr,
                  fontSize: addrSize,
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: onCopy,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.content_copy_rounded,
                    size: 26,
                    color: cs.subText,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 26,
                  color: cs.subText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddressRichText extends StatelessWidget {
  final String addr;
  final double fontSize;

  const _AddressRichText({
    required this.addr,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final highlights = {'8', '2', '5'};
    final spans = <TextSpan>[];
    for (final rune in addr.runes) {
      final ch = String.fromCharCode(rune);
      spans.add(
        TextSpan(
          text: ch,
          style: TextStyle(
            color: highlights.contains(ch) ? cs.blue : cs.subText,
            fontWeight:
                highlights.contains(ch) ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      );
    }
    return Text.rich(
      TextSpan(children: spans),
      style: TextStyle(
        fontSize: fontSize,
        height: 1.55,
      ),
    );
  }
}

class _WarnCard extends StatelessWidget {
  final AppI18n i18n;

  const _WarnCard({required this.i18n});

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final isDesktop = context.isDesktopFormFactor;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: cs.warningBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: cs.warningIconBg,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(
                Icons.error_outline_rounded,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              i18n.t(
                zhHans: '请仔细核查转账地址，错误币种接收地址，会导致资产无法找回',
                zhHant: '請仔細核查轉帳地址，錯誤幣種接收地址，會導致資產無法找回',
                en: 'Double-check the address. Wrong token or network may make funds unrecoverable.',
                ja: '送金先を必ずご確認ください。通貨やネットワークの誤りは資産の回収不能につながる場合があります。',
                ko: '주소를 꼼꼼히 확인하세요. 잘못된 코인·네트워크는 자산을 복구할 수 없게 할 수 있습니다.',
              ),
              style: TextStyle(
                fontSize: isDesktop ? 15.0 : 14.0,
                height: 1.45,
                color: cs.warningText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareButton extends StatelessWidget {
  final bool saving;
  final VoidCallback? onTap;

  const _ShareButton({
    required this.saving,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final i18n = AppI18n.of(context);
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: cs.blue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: cs.disabledButton,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Text(
          saving
              ? i18n.t(
                  zhHans: '保存中',
                  zhHant: '儲存中',
                  en: 'Saving...',
                  ja: '保存中...',
                  ko: '저장 중...',
                )
              : i18n.t(
                  zhHans: '分享',
                  zhHant: '分享',
                  en: 'Share',
                  ja: '共有',
                  ko: '공유',
                ),
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _SharePreviewSheet extends StatefulWidget {
  final WalletShareService svc;
  final String addr;

  const _SharePreviewSheet({
    required this.svc,
    required this.addr,
  });

  @override
  State<_SharePreviewSheet> createState() => _SharePreviewSheetState();
}

class _SharePreviewSheetState extends State<_SharePreviewSheet> {
  final GlobalKey _previewShotKey = GlobalKey();
  bool _saving = false;
  String _inlineMsg = '';

  void _showInlineMsg(String text) {
    if (!mounted) return;
    setState(() => _inlineMsg = text);
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      if (_inlineMsg == text) {
        setState(() => _inlineMsg = '');
      }
    });
  }

  Future<void> _copyAddr() async {
    final i18n = AppI18n.of(context);
    final ret = await widget.svc.copyAddr(widget.addr);
    switch (ret) {
      case WalletCopyResult.success:
        _showInlineMsg(i18n.t(
          zhHans: '地址已复制',
          zhHant: '地址已複製',
          en: 'Address copied',
          ja: 'アドレスをコピーしました',
          ko: '주소가 복사되었습니다',
        ));
        break;
      case WalletCopyResult.empty:
        _showInlineMsg(i18n.t(
          zhHans: '地址暂不可用',
          zhHant: '地址暫不可用',
          en: 'Address unavailable',
          ja: 'アドレスは利用できません',
          ko: '주소를 사용할 수 없습니다',
        ));
        break;
      case WalletCopyResult.failed:
        _showInlineMsg(i18n.t(
          zhHans: '复制失败，请重试',
          zhHant: '複製失敗，請重試',
          en: 'Copy failed. Please try again.',
          ja: 'コピーに失敗しました。もう一度お試しください。',
          ko: '복사에 실패했습니다. 다시 시도해 주세요.',
        ));
        break;
    }
  }

  Future<void> _savePreview() async {
    if (_saving) return;
    final i18n = AppI18n.of(context);
    setState(() => _saving = true);
    final ret = await widget.svc.saveQrImg(context, _previewShotKey);
    if (!mounted) return;
    setState(() => _saving = false);
    switch (ret) {
      case WalletSaveImgResult.success:
        _showInlineMsg(i18n.t(
          zhHans: '保存成功',
          zhHant: '儲存成功',
          en: 'Saved successfully',
          ja: '保存しました',
          ko: '저장되었습니다',
        ));
        break;
      case WalletSaveImgResult.permissionDenied:
        _showInlineMsg(i18n.t(
          zhHans: '未获得相册权限',
          zhHant: '未獲得相簿權限',
          en: 'Photo library permission denied',
          ja: '写真ライブラリへのアクセスが許可されていません',
          ko: '앨범 권한이 없습니다',
        ));
        break;
      case WalletSaveImgResult.permanentlyDenied:
        _showInlineMsg(i18n.t(
          zhHans: '请到系统设置开启相册权限',
          zhHant: '請到系統設定開啟相簿權限',
          en: 'Enable photo library access in Settings',
          ja: '設定で写真ライブラリへのアクセスを許可してください',
          ko: '설정에서 앨범 권한을 허용해 주세요',
        ));
        break;
      case WalletSaveImgResult.renderFailed:
        _showInlineMsg(i18n.t(
          zhHans: '二维码生成失败，请重试',
          zhHant: 'QR 碼產生失敗，請重試',
          en: 'Failed to generate QR code. Please try again.',
          ja: 'QRコードの生成に失敗しました。もう一度お試しください。',
          ko: 'QR 코드 생성에 실패했습니다. 다시 시도해 주세요.',
        ));
        break;
      case WalletSaveImgResult.saveFailed:
        _showInlineMsg(i18n.t(
          zhHans: '保存失败，请检查存储空间',
          zhHant: '儲存失敗，請檢查儲存空間',
          en: 'Save failed. Check available storage.',
          ja: '保存に失敗しました。ストレージ容量を確認してください。',
          ko: '저장에 실패했습니다. 저장 공간을 확인해 주세요.',
        ));
        break;
      case WalletSaveImgResult.unsupported:
        _showInlineMsg(i18n.t(
          zhHans: '当前设备暂不支持保存图片',
          zhHant: '目前裝置暫不支援儲存圖片',
          en: 'Saving images is not supported on this device.',
          ja: 'このデバイスでは画像の保存に対応していません。',
          ko: '이 기기에서는 이미지 저장을 지원하지 않습니다.',
        ));
        break;
      case WalletSaveImgResult.unknown:
        _showInlineMsg(i18n.t(
          zhHans: '保存失败，请稍后重试',
          zhHant: '儲存失敗，請稍後重試',
          en: 'Save failed. Please try again later.',
          ja: '保存に失敗しました。しばらくしてからもう一度お試しください。',
          ko: '저장에 실패했습니다. 잠시 후 다시 시도해 주세요.',
        ));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final i18n = AppI18n.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final previewWidth = (width - 32).clamp(280.0, 420.0);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.82;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: cs.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          left: false,
          right: false,
          bottom: true,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 48,
                height: 6,
                decoration: BoxDecoration(
                  color: cs.line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    i18n.t(
                      zhHans: '分享预览',
                      zhHant: '分享預覽',
                      en: 'Share Preview',
                      ja: '共有プレビュー',
                      ko: '공유 미리보기',
                    ),
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                      color: cs.text,
                    ),
                  ),
                ),
              ),
              if (_inlineMsg.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: cs.filterActiveBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _inlineMsg,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.filterActiveText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Center(
                    child: RepaintBoundary(
                      key: _previewShotKey,
                      child: Container(
                        width: previewWidth,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                        decoration: BoxDecoration(
                          color: cs.dark ? cs.card : Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: cs.shadow,
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            const _TokenBadge(size: 74),
                            const SizedBox(height: 12),
                            Text(
                              i18n.t(
                                zhHans: 'USDT 接收',
                                zhHant: 'USDT 接收',
                                en: 'Receive USDT',
                                ja: 'USDT 受取',
                                ko: 'USDT 받기',
                              ),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color:
                                    cs.dark ? cs.text : const Color(0xFF111111),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              i18n.t(
                                zhHans: '仅支持接收 Tron(TRC20) 网络资产',
                                zhHant: '僅支援接收 Tron(TRC20) 網路資產',
                                en: 'Only Tron (TRC20) network assets are supported.',
                                ja: 'Tron（TRC20）ネットワークの資産のみ受取可能です。',
                                ko: 'Tron(TRC20) 네트워크 자산만 받을 수 있습니다.',
                              ),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: cs.dark
                                    ? cs.subText
                                    : const Color(0xFF444444),
                              ),
                            ),
                            const SizedBox(height: 14),
                            _ReceiveQr(
                              data: widget.addr,
                              size: previewWidth * 0.54,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              i18n.t(
                                zhHans: '最小充值数量 -- USDT',
                                zhHant: '最小充值數量 -- USDT',
                                en: 'Minimum deposit: -- USDT',
                                ja: '最小入金数量 -- USDT',
                                ko: '최소 입금 수량 -- USDT',
                              ),
                              style: TextStyle(
                                fontSize: 14,
                                color: cs.warningText,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _AddressCard(
                              addr: widget.addr,
                              onCopy: _copyAddr,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                child: SizedBox(
                  height: 84,
                  child: Row(
                    children: [
                      _ShareAction(
                        icon: Icons.file_download_outlined,
                        label: _saving
                            ? i18n.t(
                                zhHans: '保存中',
                                zhHant: '儲存中',
                                en: 'Saving...',
                                ja: '保存中...',
                                ko: '저장 중...',
                              )
                            : i18n.t(
                                zhHans: '保存图片',
                                zhHant: '儲存圖片',
                                en: 'Save Image',
                                ja: '画像を保存',
                                ko: '이미지 저장',
                              ),
                        onTap: _saving ? () {} : _savePreview,
                      ),
                      _ShareAction(
                        icon: Icons.wechat,
                        label: i18n.t(
                          zhHans: '微信',
                          zhHant: '微信',
                          en: 'WeChat',
                          ja: 'WeChat',
                          ko: 'WeChat',
                        ),
                        onTap: () async {
                          final ret = await widget.svc.launchWechat();
                          if (ret != WalletLaunchAppResult.success) {
                            _showInlineMsg(i18n.t(
                              zhHans: '未检测到微信',
                              zhHant: '未偵測到微信',
                              en: 'WeChat is not installed',
                              ja: 'WeChatが見つかりません',
                              ko: 'WeChat이 설치되어 있지 않습니다',
                            ));
                          } else {
                            _showInlineMsg(i18n.t(
                              zhHans: '已拉起微信，请在微信中发送已保存图片',
                              zhHant: '已開啟微信，請在微信中發送已儲存圖片',
                              en: 'WeChat opened. Send the saved image there.',
                              ja: 'WeChatを起動しました。保存した画像を送信してください。',
                              ko: 'WeChat을 실행했습니다. 저장한 이미지를 보내 주세요.',
                            ));
                          }
                        },
                      ),
                      _ShareAction(
                        icon: Icons.person_rounded,
                        label: 'QQ',
                        onTap: () async {
                          final ret = await widget.svc.launchQQ();
                          if (ret != WalletLaunchAppResult.success) {
                            _showInlineMsg(i18n.t(
                              zhHans: '未检测到QQ',
                              zhHant: '未偵測到QQ',
                              en: 'QQ is not installed',
                              ja: 'QQが見つかりません',
                              ko: 'QQ가 설치되어 있지 않습니다',
                            ));
                          } else {
                            _showInlineMsg(i18n.t(
                              zhHans: '已拉起QQ，请在QQ中发送已保存图片',
                              zhHant: '已開啟QQ，請在QQ中發送已儲存圖片',
                              en: 'QQ opened. Send the saved image there.',
                              ja: 'QQを起動しました。保存した画像を送信してください。',
                              ko: 'QQ를 실행했습니다. 저장한 이미지를 보내 주세요.',
                            ));
                          }
                        },
                      ),
                      _ShareAction(
                        icon: Icons.sms_outlined,
                        label: i18n.t(
                          zhHans: '短信',
                          zhHant: '簡訊',
                          en: 'SMS',
                          ja: 'SMS',
                          ko: 'SMS',
                        ),
                        onTap: () async {
                          final ret = await widget.svc.launchSms(widget.addr);
                          switch (ret) {
                            case WalletLaunchAppResult.success:
                              break;
                            case WalletLaunchAppResult.unavailable:
                              _showInlineMsg(i18n.t(
                                zhHans: '当前设备不支持短信分享',
                                zhHant: '目前裝置不支援簡訊分享',
                                en: 'SMS sharing is not supported on this device.',
                                ja: 'このデバイスではSMS共有に対応していません。',
                                ko: '이 기기에서는 SMS 공유를 지원하지 않습니다.',
                              ));
                              break;
                            case WalletLaunchAppResult.failed:
                              _showInlineMsg(i18n.t(
                                zhHans: '短信分享失败，请重试',
                                zhHant: '簡訊分享失敗，請重試',
                                en: 'SMS sharing failed. Please try again.',
                                ja: 'SMS共有に失敗しました。もう一度お試しください。',
                                ko: 'SMS 공유에 실패했습니다. 다시 시도해 주세요.',
                              ));
                              break;
                          }
                        },
                      ),
                      _ShareAction(
                        icon: Icons.more_horiz_rounded,
                        label: i18n.t(
                          zhHans: '更多',
                          zhHant: '更多',
                          en: 'More',
                          ja: 'その他',
                          ko: '더보기',
                        ),
                        onTap: () async {
                          final ret =
                              await widget.svc.shareSystemText(widget.addr);
                          switch (ret) {
                            case WalletSystemShareResult.success:
                              break;
                            case WalletSystemShareResult.unavailable:
                              _showInlineMsg(i18n.t(
                                zhHans: '当前设备暂不支持系统分享',
                                zhHant: '目前裝置暫不支援系統分享',
                                en: 'System sharing is not supported on this device.',
                                ja: 'このデバイスではシステム共有に対応していません。',
                                ko: '이 기기에서는 시스템 공유를 지원하지 않습니다.',
                              ));
                              break;
                            case WalletSystemShareResult.failed:
                              _showInlineMsg(i18n.t(
                                zhHans: '分享失败，请重试',
                                zhHant: '分享失敗，請重試',
                                en: 'Sharing failed. Please try again.',
                                ja: '共有に失敗しました。もう一度お試しください。',
                                ko: '공유에 실패했습니다. 다시 시도해 주세요.',
                              ));
                              break;
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShareAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ShareAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cs.inputFill,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  size: 24,
                  color: cs.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: cs.subText,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
