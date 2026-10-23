import 'package:flutter/material.dart';

import '../../data/wallet_fund_api.dart';
import '../../host/wallet_i18n.dart';
import '../../host/wallet_toast.dart';
import '../../wallet_share_service.dart';
import '../share/wallet_deposit_save_once.dart';
import '../wallet_deposit_controller.dart';
import '../wallet_deposit_tokens.dart';
import 'wallet_deposit_qr.dart';

/// Owns only the main-page QR save interaction and its capture boundary.
class WalletDepositSaveableQr extends StatefulWidget {
  const WalletDepositSaveableQr(
      {super.key,
      required this.controller,
      required this.address,
      required this.currency,
      required this.service});
  final WalletDepositController controller;
  final WalletDepositAddress address;
  final FundCurrency currency;
  final WalletShareService service;

  @override
  State<WalletDepositSaveableQr> createState() =>
      _WalletDepositSaveableQrState();
}

class _WalletDepositSaveableQrState extends State<WalletDepositSaveableQr> {
  final _boundary = GlobalKey();
  bool _saving = false;

  Future<void> _save() async {
    if (_saving || !widget.controller.canUseAddress) return;
    final address = widget.address;
    final currency = widget.currency;
    bool current() =>
        mounted &&
        widget.controller.canUseAddress &&
        widget.controller.address?.address == address.address &&
        widget.controller.address?.network == address.network &&
        widget.currency == currency;
    if (!current()) return;
    setState(() => _saving = true);
    final result = await WalletDepositSaveOnce.instance.save(
      currency: currency.code,
      network: address.network,
      address: address.address,
      write: () async {
        if (!current()) return WalletSaveImgResult.unknown;
        return widget.service.saveQrImg(context, _boundary,
            isCurrent: current,
            backgroundColor: WalletDepositTokens.qrBackground);
      },
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (!current()) return;
    final i18n = AppI18n.of(context);
    ToastUtils.toast(switch (result) {
      DepositSaveResult.saved => i18n.t(
          zhHans: '二维码已保存到相册',
          zhHant: '二維碼已儲存至相簿',
          en: 'QR code saved to photos',
          ja: 'QRコードを写真に保存しました',
          ko: 'QR 코드를 사진에 저장했습니다'),
      DepositSaveResult.alreadySaved => i18n.t(
          zhHans: '二维码已保存，请到相册查看',
          zhHant: '二維碼已儲存，請至相簿查看',
          en: 'QR code already saved. Check your photos.',
          ja: '保存済みです。写真をご確認ください',
          ko: '이미 저장되었습니다. 사진을 확인하세요'),
      DepositSaveResult.failed => i18n.t(
          zhHans: '保存失败，请检查相册权限后重试',
          zhHant: '儲存失敗，請檢查相簿權限後重試',
          en: 'Save failed. Check photo access and retry.',
          ja: '保存できませんでした。写真のアクセス権を確認してください',
          ko: '저장하지 못했습니다. 사진 접근 권한을 확인하세요'),
    });
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final label = _saving
        ? i18n.t(
            zhHans: '保存中', zhHant: '儲存中', en: 'Saving', ja: '保存中', ko: '저장 중')
        : i18n.t(
            zhHans: '保存二维码到相册',
            zhHant: '儲存二維碼至相簿',
            en: 'Save QR code to photos',
            ja: 'QRコードを写真に保存',
            ko: 'QR 코드를 사진에 저장');
    return Semantics(
      button: true,
      enabled: !_saving,
      label: label,
      onTap: _saving ? null : _save,
      excludeSemantics: true,
      liveRegion: _saving,
      child: Tooltip(
          message: label,
          child: InkWell(
            key: const ValueKey('wallet-deposit-tap-save-qr'),
            onTap: _saving ? null : _save,
            child: RepaintBoundary(
                key: _boundary,
                child: WalletDepositQr(
                    address: widget.address, currency: widget.currency)),
          )),
    );
  }
}
