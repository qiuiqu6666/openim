import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../host/wallet_i18n.dart';
import '../../host/wallet_navigation.dart';
import '../../host/wallet_toast.dart';
import '../../wallet_controller.dart';
import '../../wallet_receive_screen.dart';
import '../../wallet_repository.dart';
import '../../widgets/wallet_99chat_tokens.dart';
import '../../widgets/wallet_page_colors.dart';
import '../wallet_home_tokens.dart';
import '../../widgets/wallet_coin_logo.dart';

/// Compact access to the account's shared TRON receiving address.
class WalletTronAddressRow extends StatelessWidget {
  const WalletTronAddressRow({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<WalletController>();
    CoinDto? usdt;
    for (final coin in controller.coins) {
      if (coin.type == CoinType.usdt) {
        usdt = coin;
        break;
      }
    }
    final address = controller.trxAddr.trim();
    final colors = WalletPageColors.of(context);
    final i18n = AppI18n.of(context);
    final title = i18n.t(
        zhHans: '我的USDT地址',
        zhHant: '我的USDT地址',
        en: 'My USDT address',
        ja: '自分のUSDTアドレス',
        ko: '내 USDT 주소');
    final copy = i18n.t(
        zhHans: '复制地址',
        zhHant: '複製地址',
        en: 'Copy address',
        ja: 'アドレスをコピー',
        ko: '주소 복사');
    final status = controller.addressLoading
        ? i18n.t(
            zhHans: '加载中…',
            zhHant: '載入中…',
            en: 'Loading…',
            ja: '読み込み中…',
            ko: '불러오는 중…')
        : controller.addressFailed
            ? i18n.t(
                zhHans: '地址暂不可用，点击重试',
                zhHant: '地址暫不可用，點擊重試',
                en: 'Address unavailable. Tap to retry',
                ja: '取得できません。タップして再試行',
                ko: '주소를 불러올 수 없습니다. 탭하여 재시도')
            : i18n.t(
                zhHans: '查看收款地址',
                zhHant: '查看收款地址',
                en: 'View receiving address',
                ja: '受取アドレスを表示',
                ko: '수신 주소 보기');
    return Padding(
      padding: EdgeInsets.zero,
      child: Row(children: [
        Expanded(
          child: Semantics(
            button: true,
            child: InkWell(
              key: const ValueKey('wallet-tron-address-open'),
              borderRadius: BorderRadius.circular(AppTokens.rMd),
              onTap: () => openWalletPage<void>(
                  context, const WalletReceiveScreen(),
                  activityPage: 'wallet_receive'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppTokens.s4),
                child: Row(children: [
                  WalletCoinLogo(
                      type: CoinType.usdt,
                      logoUrl: usdt?.logoUrl,
                      size: WalletHomeTokens.addressLogo),
                  const SizedBox(width: AppTokens.s4),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: TextStyle(
                                color: colors.subText,
                                fontSize: WalletHomeTokens.caption)),
                        const SizedBox(height: AppTokens.s2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(address.isEmpty ? status : address,
                              maxLines: 1,
                              softWrap: false,
                              key: const ValueKey('wallet-tron-address'),
                              textDirection:
                                  address.isEmpty ? null : TextDirection.ltr,
                              style: TextStyle(
                                  color: colors.text,
                                  fontSize: WalletHomeTokens.body,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                  if (address.isNotEmpty)
                    Transform.translate(
                      offset: const Offset(0, WalletHomeTokens.caption / 2),
                      child: IconButton(
                        key: const ValueKey('wallet-tron-address-copy'),
                        tooltip: copy,
                        color: colors.subText,
                        iconSize: WalletHomeTokens.icon,
                        icon: const Icon(Icons.content_copy_rounded),
                        onPressed: () async {
                          try {
                            await Clipboard.setData(
                                ClipboardData(text: address));
                            if (context.mounted) {
                              ToastUtils.toast(i18n.t(
                                  zhHans: '地址已复制',
                                  zhHant: '地址已複製',
                                  en: 'Address copied',
                                  ja: 'アドレスをコピーしました',
                                  ko: '주소가 복사되었습니다'));
                            }
                          } catch (_) {
                            if (context.mounted) {
                              ToastUtils.toast(i18n.t(
                                  zhHans: '复制失败，请重试',
                                  zhHant: '複製失敗，請重試',
                                  en: 'Copy failed. Try again.',
                                  ja: 'コピーできませんでした',
                                  ko: '복사에 실패했습니다'));
                            }
                          }
                        },
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: title,
          color: colors.subText,
          icon: const Icon(Icons.chevron_right_rounded),
          onPressed: () => openWalletPage<void>(
              context, const WalletReceiveScreen(),
              activityPage: 'wallet_receive'),
        ),
      ]),
    );
  }
}
