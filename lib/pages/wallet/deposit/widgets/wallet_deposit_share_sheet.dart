import 'package:flutter/material.dart';

import '../../data/wallet_fund_api.dart';
import '../../host/wallet_i18n.dart';
import '../../host/wallet_toast.dart';
import '../../wallet_share_service.dart';
import '../../widgets/wallet_page_colors.dart';
import '../share/wallet_deposit_share_tokens.dart';
import '../wallet_deposit_controller.dart';
import 'wallet_deposit_share_preview.dart';

class WalletDepositShareSheet extends StatefulWidget {
  const WalletDepositShareSheet({
    super.key,
    required this.controller,
    required this.currency,
    required this.service,
  });
  final WalletDepositController controller;
  final FundCurrency currency;
  final WalletShareService service;

  @override
  State<WalletDepositShareSheet> createState() =>
      _WalletDepositShareSheetState();
}

class _WalletDepositShareSheetState extends State<WalletDepositShareSheet> {
  final _boundary = GlobalKey();
  final _createdAt = DateTime.now();
  bool _saving = false;
  bool _sharing = false;

  bool get _busy => _saving || _sharing;
  String get _address => widget.controller.canUseAddress &&
          widget.controller.address!.currencies.contains(widget.currency)
      ? widget.controller.address!.address
      : '';

  bool _current(String address) =>
      mounted &&
      widget.controller.isCurrentAccount &&
      address.isNotEmpty &&
      _address == address;

  Color get _imageBackground => WalletDepositShareTokens.cardColor(
      dark: WalletPageColors.of(context).dark);

  String _text(String zh, String en) {
    final (hant, ja, ko) = switch (zh) {
      '图片已保存' => ('圖片已儲存', '画像を保存しました', '이미지가 저장되었습니다'),
      '图片未保存，请检查相册权限后重试' => (
          '圖片未儲存，請檢查相簿權限後重試',
          '画像を保存できませんでした。写真のアクセス権を確認してください。',
          '이미지를 저장하지 못했습니다. 사진 접근 권한을 확인하세요.'
        ),
      '分享失败，请重试' => (
          '分享失敗，請重試',
          '共有に失敗しました。再試行してください。',
          '공유에 실패했습니다. 다시 시도하세요.'
        ),
      '当前设备暂不支持此分享方式' => (
          '目前裝置暫不支援此分享方式',
          'この端末ではこの共有方法を利用できません',
          '이 기기에서 이 공유 방식을 사용할 수 없습니다'
        ),
      '分享到' => ('分享到', '共有先', '공유 대상'),
      '保存中' => ('儲存中', '保存中', '저장 중'),
      '保存图片' => ('儲存圖片', '画像を保存', '이미지 저장'),
      '分享中' => ('分享中', '共有中', '공유 중'),
      '分享' => ('分享', '共有', '공유'),
      '取消' => ('取消', 'キャンセル', '취소'),
      _ => (en, en, en),
    };
    return AppI18n.of(context)
        .t(zhHans: zh, zhHant: hant, en: en, ja: ja, ko: ko);
  }

  Future<void> _save() async {
    final address = _address;
    if (_busy || address.isEmpty) return;
    setState(() => _saving = true);
    final result = await widget.service.saveQrImg(context, _boundary,
        isCurrent: () => _current(address), backgroundColor: _imageBackground);
    if (!mounted) return;
    setState(() => _saving = false);
    if (!_current(address)) return;
    ToastUtils.toast(result == WalletSaveImgResult.success
        ? _text('图片已保存', 'Image saved')
        : _text('图片未保存，请检查相册权限后重试',
            'Image was not saved. Check photo access and retry.'));
  }

  Future<void> _share() async {
    final address = _address;
    if (_busy || address.isEmpty) return;
    setState(() => _sharing = true);
    final result = await widget.service.shareSystemImage(context, _boundary,
        isCurrent: () => _current(address), backgroundColor: _imageBackground);
    if (!mounted) return;
    setState(() => _sharing = false);
    if (!_current(address) ||
        result == WalletSystemShareResult.success ||
        result == WalletSystemShareResult.dismissed) {
      return;
    }
    ToastUtils.toast(result == WalletSystemShareResult.unavailable
        ? _text('当前设备暂不支持此分享方式',
            'This sharing method is unavailable on this device.')
        : _text('分享失败，请重试', 'Sharing failed. Please retry.'));
  }

  Widget _action({
    required String key,
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    required WalletPageColors colors,
  }) =>
      SizedBox(
        width: WalletDepositShareTokens.actionItemWidth,
        child: Semantics(
          button: true,
          enabled: onPressed != null,
          child: InkWell(
            key: ValueKey(key),
            onTap: onPressed,
            borderRadius:
                BorderRadius.circular(WalletDepositShareTokens.sheetRadius),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  vertical: WalletDepositShareTokens.actionVerticalPadding),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: WalletDepositShareTokens.actionCircleSize,
                  height: WalletDepositShareTokens.actionCircleSize,
                  decoration: BoxDecoration(
                      color: colors.surfaceAlt, shape: BoxShape.circle),
                  child: Icon(icon,
                      size: WalletDepositShareTokens.actionIconSize,
                      color: onPressed == null ? colors.subText : colors.text),
                ),
                const SizedBox(height: WalletDepositShareTokens.actionLabelGap),
                Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: colors.subText,
                        fontSize: WalletDepositShareTokens.actionLabelSize)),
              ]),
            ),
          ),
        ),
      );

  Widget _actions(WalletPageColors colors) => Material(
        color: colors.card,
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(WalletDepositShareTokens.sheetRadius)),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            key: const ValueKey('wallet-deposit-share-actions'),
            padding:
                const EdgeInsets.all(WalletDepositShareTokens.panelPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_text('分享到', 'Share to'),
                    style: TextStyle(
                        color: colors.text,
                        fontSize: WalletDepositShareTokens.panelTitleSize,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: WalletDepositShareTokens.panelGap),
                Wrap(spacing: WalletDepositShareTokens.panelGap, children: [
                  _action(
                      key: 'wallet-deposit-save',
                      label: _text(_saving ? '保存中' : '保存图片',
                          _saving ? 'Saving' : 'Save image'),
                      icon: Icons.file_download_outlined,
                      onPressed: !_busy && _address.isNotEmpty ? _save : null,
                      colors: colors),
                  _action(
                      key: 'wallet-deposit-system-share',
                      label: _text(_sharing ? '分享中' : '分享',
                          _sharing ? 'Sharing' : 'Share'),
                      icon: Icons.ios_share_rounded,
                      onPressed: !_busy && _address.isNotEmpty ? _share : null,
                      colors: colors),
                ]),
              ],
            ),
          ),
          ColoredBox(
              color: colors.surfaceAlt,
              child: const SizedBox(
                  height: WalletDepositShareTokens.cancelSeparatorHeight,
                  width: double.infinity)),
          SafeArea(
            top: false,
            child: SizedBox(
              width: double.infinity,
              child: TextButton(
                key: const ValueKey('wallet-deposit-share-cancel'),
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(
                    foregroundColor: colors.text,
                    minimumSize: const Size.fromHeight(
                        WalletDepositShareTokens.cancelHeight),
                    shape: const RoundedRectangleBorder()),
                child: Text(_text('取消', 'Cancel'),
                    style: const TextStyle(
                        fontSize: WalletDepositShareTokens.cancelTextSize)),
              ),
            ),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (_, __) {
          final colors = WalletPageColors.of(context);
          return LayoutBuilder(builder: (context, constraints) {
            return Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                    maxWidth: WalletDepositShareTokens.maxWidth),
                child: SizedBox(
                  key: const ValueKey('wallet-deposit-share-sheet'),
                  width: double.infinity,
                  height: constraints.maxHeight,
                  child: Column(children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                            WalletDepositShareTokens.previewHorizontalInset,
                            WalletDepositShareTokens.panelPadding,
                            WalletDepositShareTokens.previewHorizontalInset,
                            WalletDepositShareTokens.previewBottomGap),
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: SingleChildScrollView(
                            child: _address.isNotEmpty
                                ? RepaintBoundary(
                                    key: _boundary,
                                    child: WalletDepositSharePreview(
                                        address: widget.controller.address!,
                                        currency: widget.currency,
                                        createdAt: _createdAt))
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ),
                    ),
                    _actions(colors),
                  ]),
                ),
              ),
            );
          });
        },
      );
}
