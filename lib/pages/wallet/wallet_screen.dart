import 'dart:math' as math;

import 'wallet_action_artwork.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'host/wallet_toast.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'host/wallet_i18n.dart';

import 'wallet_controller.dart';
import 'wallet_exchange_screen.dart';
import 'wallet_repository.dart';
import 'wallet_receive_screen.dart';
import 'withdraw_coin_picker_screen.dart';
import 'record/wallet_record_screen.dart';
import 'widgets/platform_coin_icon.dart';
import 'widgets/wallet_page_colors.dart';
import 'host/wallet_navigation.dart';
import 'widgets/wallet_99chat_tokens.dart';
import 'widgets/wallet_system_ui.dart';
import 'host/wallet_dialog.dart';
import 'host/wallet_network_image.dart';
import 'host/android_performance_profile.dart';
import 'host/wallet_image_cache.dart';
import 'widgets/wallet_99chat_scale.dart';

const String _walletHeaderBgAssetLight = 'assets/img/card.webp';
const String _walletHeaderBgAssetDark = 'assets/img/card2.webp';
const String _walletInviteBgAssetLight = 'assets/img/invite.webp';
const String _walletInviteBgAssetDark = 'assets/img/invite2.webp';
const double _walletHeaderBgWidth = 1024;
const double _walletHeaderBgWidthDark = 1024;
const double _walletHeaderBgHeight = 471;
const double _walletHeaderBgAspectRatio =
    _walletHeaderBgWidth / _walletHeaderBgHeight;
const double _walletInviteBgWidth = 1024;
const double _walletInviteBgWidthDark = 1829;
const double _walletInviteBgHeight = 344;
const double _walletInviteBgAspectRatio =
    _walletInviteBgWidth / _walletInviteBgHeight;
const double _walletInviteCardHeightScale = 0.76;

int walletPromoCacheWidth({
  required double logicalWidth,
  required double devicePixelRatio,
  required int sourcePx,
}) {
  final decoded = (logicalWidth * devicePixelRatio).round();
  if (decoded < 1) {
    return 1;
  }
  if (decoded > sourcePx) {
    return sourcePx;
  }
  return decoded;
}

double walletPromoDecodePixelRatio(double devicePixelRatio) {
  if (defaultTargetPlatform != TargetPlatform.android) {
    return devicePixelRatio;
  }
  return switch (AndroidPerformanceProfile.instance.tier) {
    AndroidPerformanceTier.low => math.min(devicePixelRatio, 1.5),
    AndroidPerformanceTier.medium => math.min(devicePixelRatio, 2.0),
    AndroidPerformanceTier.normal => devicePixelRatio,
  };
}

class _WalletPromoCardStyle {
  const _WalletPromoCardStyle({
    required this.headerBgAsset,
    required this.inviteBgAsset,
    required this.assetLabelColor,
    required this.assetAmountColor,
    required this.assetSubAmountColor,
    required this.assetBadgeColor,
    required this.assetBadgeBg,
    required this.inviteTitleColor,
    required this.inviteSubtitleColor,
    required this.inviteActionBg,
    required this.inviteActionIconColor,
  });

  final String headerBgAsset;
  final String inviteBgAsset;
  final Color assetLabelColor;
  final Color assetAmountColor;
  final Color assetSubAmountColor;
  final Color assetBadgeColor;
  final Color assetBadgeBg;
  final Color inviteTitleColor;
  final Color inviteSubtitleColor;
  final Color inviteActionBg;
  final Color inviteActionIconColor;

  factory _WalletPromoCardStyle.of(bool dark) {
    if (dark) {
      return const _WalletPromoCardStyle(
        headerBgAsset: _walletHeaderBgAssetDark,
        inviteBgAsset: _walletInviteBgAssetDark,
        assetLabelColor: Color(0xFFB8C5D9),
        assetAmountColor: Color(0xFF6EA8FF),
        assetSubAmountColor: Color(0xFF8A96AB),
        assetBadgeColor: Color(0xFF93C5FD),
        assetBadgeBg: Color(0x661A3A6E),
        inviteTitleColor: Color(0xFFFFFFFF),
        inviteSubtitleColor: Color(0xFFA8B8D8),
        inviteActionBg: Color(0xE8FFFFFF),
        inviteActionIconColor: Color(0xFF1A2151),
      );
    }
    return const _WalletPromoCardStyle(
      headerBgAsset: _walletHeaderBgAssetLight,
      inviteBgAsset: _walletInviteBgAssetLight,
      assetLabelColor: Color(0xFF5E6472),
      assetAmountColor: Color(0xFF4D7BF3),
      assetSubAmountColor: Color(0xFF8A8A8A),
      assetBadgeColor: Color(0xFF4D7BF3),
      assetBadgeBg: Color(0xFFF0F4FF),
      inviteTitleColor: Color(0xFF1A2151),
      inviteSubtitleColor: Color(0xFF7B819A),
      inviteActionBg: Color(0xE6FFFFFF),
      inviteActionIconColor: Color(0xFF1A2151),
    );
  }
}

class WalletScreen extends StatefulWidget {
  const WalletScreen({
    super.key,
    this.embeddedInMainTab = false,
    this.isTabActive = true,
    this.activeTabIndexListenable,
    this.mainTabIndex = 3,
  });

  final bool embeddedInMainTab;

  final bool isTabActive;

  /// Main-tab activation is observed without rebuilding the cached wallet
  /// subtree every time the bottom navigation index changes.
  final ValueListenable<int>? activeTabIndexListenable;

  final int mainTabIndex;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => WalletController(),
      child: _WalletTabLifecycle(
        isTabActive: widget.isTabActive,
        activeTabIndexListenable: widget.activeTabIndexListenable,
        mainTabIndex: widget.mainTabIndex,
        child: _WalletView(embeddedInMainTab: widget.embeddedInMainTab),
      ),
    );
  }
}

class _WalletTabLifecycle extends StatefulWidget {
  const _WalletTabLifecycle({
    required this.isTabActive,
    required this.activeTabIndexListenable,
    required this.mainTabIndex,
    required this.child,
  });

  final bool isTabActive;
  final ValueListenable<int>? activeTabIndexListenable;
  final int mainTabIndex;
  final Widget child;

  @override
  State<_WalletTabLifecycle> createState() => _WalletTabLifecycleState();
}

class _WalletTabLifecycleState extends State<_WalletTabLifecycle> {
  DateTime? _lastReloadAt;
  bool _routeActive = true;

  @override
  void initState() {
    super.initState();
    widget.activeTabIndexListenable?.addListener(_handleTabIndexChanged);
    _reloadIfActive();
  }

  @override
  void dispose() {
    widget.activeTabIndexListenable?.removeListener(_handleTabIndexChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _WalletTabLifecycle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
      oldWidget.activeTabIndexListenable,
      widget.activeTabIndexListenable,
    )) {
      oldWidget.activeTabIndexListenable
          ?.removeListener(_handleTabIndexChanged);
      widget.activeTabIndexListenable?.addListener(_handleTabIndexChanged);
    }
    _reloadIfActive();
  }

  void _handleTabIndexChanged() => _reloadIfActive();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeActive =
        (ModalRoute.of(context)?.isCurrent ?? true) && TickerMode.of(context);
    _reloadIfActive();
  }

  bool get _isActive => widget.activeTabIndexListenable == null
      ? widget.isTabActive
      : widget.activeTabIndexListenable!.value == widget.mainTabIndex;

  void _reloadIfActive() {
    final controller = context.read<WalletController>();
    if (!_isActive || !_routeActive) {
      controller.setActive(false);
      return;
    }
    // Reactivation may notify; defer it until the inherited-widget build ends.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isActive || !_routeActive) return;
      if (controller.setActive(true)) _lastReloadAt = DateTime.now();
    });
    if (controller.hasDeferredRefresh) return;
    final now = DateTime.now();
    final last = _lastReloadAt;
    if (last != null && now.difference(last) < const Duration(seconds: 10)) {
      return;
    }
    _lastReloadAt = now;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_isActive || !_routeActive) return;
      await context.read<WalletController>().load();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _WalletView extends StatelessWidget {
  const _WalletView({required this.embeddedInMainTab});

  final bool embeddedInMainTab;

  SystemUiOverlayStyle _systemUiOverlayStyle(BuildContext context) {
    if (embeddedInMainTab) {
      final cs = WalletPageColors.of(context);
      return decorativeMainTabOverlayStyle(
        dark: cs.dark,
        navigationBarBackground: cs.bg,
      );
    }
    return walletPageOverlayStyle(context);
  }

  Widget _wrapSystemUi(BuildContext context, Widget child) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _systemUiOverlayStyle(context),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return _wrapSystemUi(
      context,
      ColoredBox(
        color: Colors.transparent,
        child: embeddedInMainTab
            ? _buildWalletScrollContent(context: context)
            : SafeArea(
                bottom: false,
                child: _buildWalletScrollContent(context: context),
              ),
      ),
    );
  }

  Widget _buildWalletScrollContent({
    required BuildContext context,
  }) {

    final cardGap = 18.h99;
    final horizontalPadding = 16.w99;
    final cardWidth = MediaQuery.sizeOf(context).width - horizontalPadding * 2;
    final actionBarHeight = (cardWidth * 0.235).clamp(90.0, 112.0);
    final headerBgHeight = cardWidth / _walletHeaderBgAspectRatio;
    final headerSectionHeight = headerBgHeight + cardGap + actionBarHeight;
    final inviteCardHeight =
        cardWidth / _walletInviteBgAspectRatio * _walletInviteCardHeightScale;
    final promoStyle = _WalletPromoCardStyle.of(_WalletCs.of(context).dark);

    final listChildren = <Widget>[
      SizedBox(height: 2.h99),
      if (!embeddedInMainTab) ...[
        Padding(
          padding: EdgeInsets.fromLTRB(16.w99, 8.h99, 16.w99, 0),
          child: const _TopBar(),
        ),
        SizedBox(height: 8.h99),
      ],
      Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: SizedBox(
          width: double.infinity,
          height: headerSectionHeight,
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: headerBgHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppTokens.rXl.r99),
                    boxShadow: [
                      BoxShadow(
                        color: _WalletCs.of(context).shadow,
                        blurRadius:
                            defaultTargetPlatform == TargetPlatform.android
                                ? 0
                                : 12.r99,
                        offset: Offset(0, 4.h99),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppTokens.rXl.r99),
                    child: Transform.scale(
                      scale: 1.08,
                      child: Image.asset(
                        promoStyle.headerBgAsset,
                        width: double.infinity,
                        height: headerBgHeight,
                        fit: BoxFit.cover,
                        alignment: Alignment.center,
                        cacheWidth: walletPromoCacheWidth(
                          logicalWidth: cardWidth,
                          devicePixelRatio: walletPromoDecodePixelRatio(
                            MediaQuery.devicePixelRatioOf(context),
                          ),
                          sourcePx: promoStyle.headerBgAsset ==
                                  _walletHeaderBgAssetDark
                              ? _walletHeaderBgWidthDark.round()
                              : _walletHeaderBgWidth.round(),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: headerBgHeight,
                child: const _AssetCard(),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: headerBgHeight + cardGap,
                height: actionBarHeight,
                child: const _ActionBar(),
              ),
            ],
          ),
        ),
      ),
      SizedBox(height: 12.h99),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: const _CoinList(),
      ),
      SizedBox(height: 12.h99),
    ];

    final inviteCard = Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: SizedBox(
        height: inviteCardHeight,
        child: _InviteFriendCard(style: promoStyle),
      ),
    );

    final refreshColor = _WalletCs.of(context).blue;
    final onRefresh = () => context.read<WalletController>().load();

    if (embeddedInMainTab) {
      return Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              color: refreshColor,
              onRefresh: onRefresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(bottom: 12.h99),
                children: listChildren,
              ),
            ),
          ),
          inviteCard,
          SizedBox(height: 8.h99),
        ],
      );
    }

    return RefreshIndicator(
      color: refreshColor,
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: 18.h99),
        children: [
          ...listChildren,
          inviteCard,
          SizedBox(height: 30.h99),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final cs = _WalletCs.of(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            i18n.t(
              zhHans: '钱包',
              zhHant: '錢包',
              en: 'Wallet',
              ja: 'ウォレット',
              ko: '지갑',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 26.sp99,
              fontWeight: FontWeight.w700,
              color: cs.text,
              height: 1.1,
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () {
                ToastUtils.toast(i18n.t(
                  zhHans: '搜索功能开发中',
                  zhHant: '搜尋功能開發中',
                  en: 'Search is coming soon',
                  ja: '検索機能は開発中です',
                  ko: '검색 기능 개발 중',
                ));
              },
              icon: Icon(
                Icons.search_rounded,
                size: 28.sp99,
                color: cs.text,
              ),
            ),
            SizedBox(width: 4.w99),
            IconButton(
              onPressed: () {
                ToastUtils.toast(i18n.t(
                  zhHans: '添加功能开发中',
                  zhHant: '新增功能開發中',
                  en: 'Add feature is coming soon',
                  ja: '追加機能は開発中です',
                  ko: '추가 기능 개발 중',
                ));
              },
              icon: Icon(
                Icons.add_circle_outline_rounded,
                size: 28.sp99,
                color: cs.text,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AssetCard extends StatelessWidget {
  const _AssetCard();

  @override
  Widget build(BuildContext context) {
    final totalBalUsd = context.select<WalletController, String>(
      (c) => c.totalBalUsd,
    );
    final showBal = context.select<WalletController, bool>((c) => c.showBal);
    final totalBal = context.select<WalletController, String>(
      (c) => c.totalBal,
    );
    final i18n = AppI18n.of(context);
    final usdText = totalBalUsd.trim().isEmpty ? '--' : totalBalUsd;
    final style = _WalletPromoCardStyle.of(_WalletCs.of(context).dark);

    // 字号层级对齐设计稿：标题 / 金额 / 美元折算 / 保障标签。
    final labelStyle = TextStyle(
      fontSize: 26.sp99,
      color: style.assetLabelColor,
      fontWeight: FontWeight.w400,
      height: 1.2,
    );
    final amountStyle = TextStyle(
      fontSize: 60.sp99,
      height: 1,
      color: style.assetAmountColor,
      fontWeight: FontWeight.w700,
      letterSpacing: showBal ? -1.w99 : 2.w99,
    );
    final currencyStyle = amountStyle.copyWith(fontSize: 44.sp99);
    final usdStyle = TextStyle(
      fontSize: 26.sp99,
      height: 1.2,
      color: style.assetSubAmountColor,
      fontWeight: FontWeight.w400,
      letterSpacing: showBal ? 0 : 1.w99,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(28.w99, 58.h99, 150.w99, 28.h99),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    i18n.format(
                      zhHans: '总资产 ({currency})',
                      zhHant: '總資產 ({currency})',
                      en: 'Total Assets ({currency})',
                      ja: '総資産 ({currency})',
                      ko: '총 자산 ({currency})',
                      vars: const {'currency': 'CNY'},
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: labelStyle,
                  ),
                ),
                SizedBox(width: 6.w99),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: context.read<WalletController>().toggleBal,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 2.w99,
                      vertical: 2.h99,
                    ),
                    child: Icon(
                      showBal
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: style.assetLabelColor,
                      size: 26.sp99,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h99),
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: double.infinity,
                child: showBal
                    ? FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: '¥', style: currencyStyle),
                              TextSpan(text: totalBal, style: amountStyle),
                            ],
                          ),
                          maxLines: 1,
                        ),
                      )
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '******',
                          maxLines: 1,
                          style: amountStyle,
                        ),
                      ),
              ),
            ),
            SizedBox(height: 6.h99),
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    showBal ? '≈ \$$usdText' : '≈ ******',
                    maxLines: 1,
                    style: usdStyle,
                  ),
                ),
              ),
            ),
            const Spacer(),
            _AssetProtectionBadge(style: style),
          ],
        ),
      ),
    );
  }
}

class _AssetProtectionBadge extends StatelessWidget {
  const _AssetProtectionBadge({required this.style});

  final _WalletPromoCardStyle style;

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          AppDialog.alert(
            title: i18n.t(
              zhHans: '资产保障',
              zhHant: '資產保障',
              en: 'Asset Protection',
              ja: '資産保護',
              ko: '자산 보호',
            ),
            message: i18n.t(
              zhHans: '您的资产已受到安全保障。',
              zhHant: '您的資產已受到安全保障。',
              en: 'Your assets are under protection.',
              ja: 'お客様の資産は保護されています。',
              ko: '자산이 보호되고 있습니다.',
            ),
            buttonText: i18n.t(
              zhHans: '知道了',
              zhHant: '知道了',
              en: 'Got it',
              ja: '了解',
              ko: '확인',
            ),
          );
        },
        child: Ink(
          decoration: BoxDecoration(
            color: style.assetBadgeBg,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(12.w99, 6.h99, 8.w99, 6.h99),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.shield_rounded,
                  size: 18.sp99,
                  color: style.assetBadgeColor,
                ),
                SizedBox(width: 4.w99),
                Text(
                  i18n.t(
                    zhHans: '资产保障中',
                    zhHant: '資產保障中',
                    en: 'Protected',
                    ja: '資産保護中',
                    ko: '자산 보호 중',
                  ),
                  style: TextStyle(
                    fontSize: 22.sp99,
                    height: 1.1,
                    color: style.assetBadgeColor,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                SizedBox(width: 2.w99),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18.sp99,
                  color: style.assetBadgeColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar();

  @override
  Widget build(BuildContext context) {
    final cs = _WalletCs.of(context);
    final i18n = AppI18n.of(context);
    final items = [
      _ActItem(
        action: _WalletHomeAction.receive,
        hint: i18n.t(
          zhHans: '充币到账',
          zhHant: '充幣到帳',
          en: 'Deposit',
          ja: '入金',
          ko: '입금',
        ),
        txt: i18n.t(
          zhHans: '收款',
          zhHant: '收款',
          en: 'Receive',
          ja: '受取',
          ko: '받기',
        ),
      ),
      _ActItem(
        action: _WalletHomeAction.transfer,
        hint: i18n.t(
          zhHans: '提现转出',
          zhHant: '提現轉出',
          en: 'Withdraw',
          ja: '出金',
          ko: '출금',
        ),
        txt: i18n.t(
          zhHans: '转账',
          zhHant: '轉帳',
          en: 'Transfer',
          ja: '送金',
          ko: '이체',
        ),
      ),
      _ActItem(
        action: _WalletHomeAction.swap,
        hint: i18n.t(zhHans: '币种兑换', zhHant: '幣種兌換', en: 'Exchange coins', ja: '通貨交換', ko: '코인 교환'),
        txt: i18n.t(
          zhHans: '闪兑',
          zhHant: '閃兌',
          en: 'Swap',
          ja: 'スワップ',
          ko: '스왑',
        ),
      ),
      _ActItem(
        action: _WalletHomeAction.record,
        hint: i18n.t(zhHans: '收支明细', zhHant: '收支明細', en: 'Transactions', ja: '入出金明細', ko: '거래 내역'),
        txt: i18n.t(
          zhHans: '记录',
          zhHant: '記錄',
          en: 'History',
          ja: '履歴',
          ko: '기록',
        ),
      ),
    ];

    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: cs.dark ? cs.card : const Color(0xFFFFFEFC),
        borderRadius: BorderRadius.circular(AppTokens.rXl.r99),
        border: Border.all(
          color: cs.dark
              ? cs.line.withValues(alpha: 0.72)
              : const Color(0xFFEEE8DF),
          width: 0.8.w99,
        ),
        boxShadow: [
          BoxShadow(
            color: cs.shadow,
            blurRadius:
                defaultTargetPlatform == TargetPlatform.android ? 0 : 10.r99,
            offset: Offset(0, 4.h99),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 2.w99),
        child: Row(
          children: items
            .map(
              (e) => Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppTokens.rLg.r99),
                  onTap: () {
                    switch (e.action) {
                      case _WalletHomeAction.receive:
                        final addr = context.read<WalletController>().trxAddr;
                        openWalletPage<void>(
                          context,
                          WalletReceiveScreen(addr: addr.trim()),
                        );
                        return;
                      case _WalletHomeAction.transfer:
                        openWalletPage<void>(
                          context,
                          const WithdrawCoinPickerScreen(),
                        );
                        return;
                      case _WalletHomeAction.record:
                        openWalletPage<void>(
                          context,
                          const WalletRecordScreen(),
                        );
                        return;
                      case _WalletHomeAction.swap:
                        openWalletPage<void>(
                          context,
                          const WalletExchangeScreen(),
                        );
                        return;
                    }
                  },
                  child: WalletActionTile(
                    action: e.action.name,
                    title: e.txt,
                    subtitle: e.hint ?? '',
                    textColor: cs.text,
                    dark: cs.dark,
                    divider: e != items.last,
                  ),
                ),
              ),
            ).toList(),
        ),
      ),
    );
  }
}

class _CoinList extends StatefulWidget {
  const _CoinList();

  @override
  State<_CoinList> createState() => _CoinListState();
}

class _CoinListState extends State<_CoinList> {
  bool _hideSmallAssets = false;

  List<CoinDto> _visibleCoins(List<CoinDto> source) {
    final coins = List<CoinDto>.from(source);
    coins.sort((a, b) {
      if (a.platformCoin == b.platformCoin) return 0;
      return a.platformCoin ? -1 : 1;
    });
    if (!_hideSmallAssets) return coins;
    return coins.where((c) => !c.isSmallAsset).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final coins = _visibleCoins(
      context.select<WalletController, List<CoinDto>>((c) => c.coins),
    );
    final cs = _WalletCs.of(context);
    final i18n = AppI18n.of(context);
    final radius = BorderRadius.circular(AppTokens.rXl.r99);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cs.dark ? cs.card : const Color(0xFFFFFEFC),
        borderRadius: radius,
        border: Border.all(
          color: cs.dark
              ? cs.line.withValues(alpha: 0.72)
              : const Color(0xFFEEE8DF),
          width: 0.8.w99,
        ),
        boxShadow: [
          BoxShadow(
            color: cs.shadow,
            blurRadius:
                defaultTargetPlatform == TargetPlatform.android ? 0 : 10.r99,
            offset: Offset(0, 4.h99),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(26.w99, 20.h99, 22.w99, 14.h99),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    i18n.t(
                      zhHans: '资产列表',
                      zhHant: '資產列表',
                      en: 'Assets',
                      ja: '資産リスト',
                      ko: '자산 목록',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 28.sp99,
                      height: 1.12,
                      color: cs.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() => _hideSmallAssets = !_hideSmallAssets);
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 20.w99,
                        height: 20.w99,
                        child: Transform.scale(
                          scale: 0.78,
                          child: Checkbox(
                            value: _hideSmallAssets,
                            onChanged: (v) {
                              setState(() => _hideSmallAssets = v ?? false);
                            },
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: const VisualDensity(
                              horizontal: -4,
                              vertical: -4,
                            ),
                            side: BorderSide(
                              color: cs.subText.withValues(alpha: 0.50),
                              width: 1.15,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4.r99),
                            ),
                            activeColor: cs.blue,
                            checkColor: Colors.white,
                            fillColor: WidgetStateProperty.resolveWith((states) {
                              if (states.contains(WidgetState.selected)) {
                                return cs.blue;
                              }
                              return Colors.transparent;
                            }),
                          ),
                        ),
                      ),
                      SizedBox(width: 6.w99),
                      Text(
                        i18n.t(
                          zhHans: '隐藏小额资产',
                          zhHant: '隱藏小額資產',
                          en: 'Hide small',
                          ja: '少額を非表示',
                          ko: '소액 숨기기',
                        ),
                        style: TextStyle(
                          fontSize: 21.sp99,
                          height: 1.15,
                          color: cs.subText,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            height: 1.w99,
            margin: EdgeInsets.symmetric(horizontal: 22.w99),
            color: cs.dark
                ? cs.line.withValues(alpha: 0.62)
                : const Color(0xFFF0ECE6),
          ),
          if (coins.isEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(26.w99, 22.h99, 26.w99, 28.h99),
              child: Text(
                i18n.t(
                  zhHans: '暂无资产',
                  zhHant: '暫無資產',
                  en: 'No assets',
                  ja: '資産がありません',
                  ko: '자산 없음',
                ),
                style: TextStyle(
                  fontSize: 24.sp99,
                  color: cs.subText,
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          else
            ...List.generate(
              coins.length,
              (i) => _CoinRow(
                item: coins[i],
                hasLine: i != coins.length - 1,
              ),
            ),
        ],
      ),
    );
  }
}

class _CoinRow extends StatelessWidget {
  final CoinDto item;
  final bool hasLine;

  const _CoinRow({
    required this.item,
    required this.hasLine,
  });

  String get _recordCoinFilter {
    if (item.code.isNotEmpty) return item.code;
    switch (item.type) {
      case CoinType.usdt:
        return 'USDT';
      case CoinType.trx:
        return 'TRX';
      case CoinType.cny:
        return '99';
    }
  }

  String get _fiatDisplay {
    final fiat = item.fiat.trim();
    if (fiat.isEmpty || fiat == '--') return '≈ --';
    if (fiat.startsWith('≈')) return fiat;
    return '≈ $fiat';
  }

  void _openCoinRecords(BuildContext context) {
    openWalletPage<void>(
      context,
      WalletRecordScreen(initialCoin: _recordCoinFilter),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = _WalletCs.of(context);
    final i18n = AppI18n.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openCoinRecords(context),
        child: Container(
          constraints: BoxConstraints(minHeight: 116.h99),
          padding: EdgeInsets.fromLTRB(24.w99, 16.h99, 16.w99, 16.h99),
          decoration: BoxDecoration(
            border: hasLine
                ? Border(
                    bottom: BorderSide(
                      color: cs.line.withValues(alpha: 0.58),
                      width: 0.8.w99,
                    ),
                  )
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _CoinLogo(type: item.type, logoUrl: item.logoUrl),
              SizedBox(width: 12.w99),
              Expanded(
                flex: 2,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 27.sp99,
                              height: 1.12,
                              color: cs.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (item.platformCoin) ...[
                          SizedBox(width: 6.w99),
                          _CoinTag(
                            text: i18n.t(
                              zhHans: '主资产',
                              zhHant: '主資產',
                              en: 'Main',
                              ja: 'メイン',
                              ko: '메인',
                            ),
                            foreground: cs.dark
                                ? const Color(0xFFD0B58E)
                                : const Color(0xFF8E6B43),
                            background: cs.dark
                                ? const Color(0xFF332C24)
                                : const Color(0xFFF5EFE6),
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: 6.h99),
                    Text(
                      item.sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 21.sp99,
                        height: 1.15,
                        color: cs.subText,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8.w99),
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            item.bal,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontSize: 27.sp99,
                              height: 1.12,
                              color: cs.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 8.h99),
                          Text(
                            _fiatDisplay,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontSize: 21.sp99,
                              height: 1.15,
                              color: cs.subText,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 2.w99),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 28.sp99,
                      color: cs.dark
                          ? cs.subText.withValues(alpha: 0.34)
                          : const Color(0xFFB8B4AE),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoinTag extends StatelessWidget {
  const _CoinTag({
    required this.text,
    required this.foreground,
    required this.background,
  });

  final String text;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9.w99, vertical: 3.h99),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppTokens.rPill.r99),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 17.sp99,
          height: 1.1,
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _InviteFriendCard extends StatelessWidget {
  const _InviteFriendCard({required this.style});

  final _WalletPromoCardStyle style;

  @override
  Widget build(BuildContext context) {
    final cs = _WalletCs.of(context);
    final radius = BorderRadius.circular(28.r99);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: radius,
        onTap: () {
          AppDialog.alert(
            title: '温馨提示',
            message: '该功能即将放出',
            buttonText: '确认',
          );
        },
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: cs.shadow,
                blurRadius:
                    defaultTargetPlatform == TargetPlatform.android ? 0 : 10.r99,
                offset: Offset(0, 4.h99),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Transform.scale(
                  scale: 1.08,
                  child: Image.asset(
                    style.inviteBgAsset,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    cacheWidth: walletPromoCacheWidth(
                      logicalWidth: MediaQuery.sizeOf(context).width - 16.w99 * 2,
                      devicePixelRatio: walletPromoDecodePixelRatio(
                        MediaQuery.devicePixelRatioOf(context),
                      ),
                      sourcePx: style.inviteBgAsset == _walletInviteBgAssetDark
                          ? _walletInviteBgWidthDark.round()
                          : _walletInviteBgWidth.round(),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18.w99),
                  child: Row(
                    children: [
                      const Spacer(),
                      Container(
                        width: 42.w99,
                        height: 42.w99,
                        decoration: BoxDecoration(
                          color: style.inviteActionBg,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          color: style.inviteActionIconColor,
                          size: 30.sp99,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CoinLogo extends StatelessWidget {
  static const double _logoSize = 78;

  final CoinType type;
  final String? logoUrl;

  const _CoinLogo({
    required this.type,
    this.logoUrl,
  });

  double get _size => _logoSize.w99;

  double get _inner => _size * 0.84;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: _buildLogo(context),
    );
  }

  Widget _buildLogo(BuildContext context) {
    final url = logoUrl?.trim() ?? '';
    if (url.isNotEmpty) {
      final cacheSize = ImageMemCacheSize.forLogicalSize(_size, context);
      return ClipOval(
        child: AppNetworkImage(
          url: url,
          width: _size,
          height: _size,
          fit: BoxFit.cover,
          memCacheWidth: cacheSize,
          memCacheHeight: cacheSize,
          errorWidget: (_, __, ___) => _buildFallbackLogo(),
        ),
      );
    }
    return _buildFallbackLogo();
  }

  Widget _buildFallbackLogo() {
    if (type == CoinType.trx) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFFFF001F),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Image.asset(
            'assets/img/TRX.png',
            width: _inner,
            height: _inner,
            fit: BoxFit.contain,
            color: Colors.white,
            colorBlendMode: BlendMode.srcIn,
          ),
        ),
      );
    }

    if (type == CoinType.usdt) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFF26A17B),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: CustomPaint(
            size: Size(_inner, _inner),
            painter: _UsdtPainter(),
          ),
        ),
      );
    }

    return PlatformCoinIcon(size: _size);
  }
}

class _WalletCs {
  final bool dark;
  final Color bg;
  final Color card;
  final Color text;
  final Color subText;
  final Color line;
  final Color shadow;
  final Color red;
  final Color blue;
  final Color warningBg;
  final Color warningText;
  final Color tagBorder;

  const _WalletCs({
    required this.dark,
    required this.bg,
    required this.card,
    required this.text,
    required this.subText,
    required this.line,
    required this.shadow,
    required this.red,
    required this.blue,
    required this.warningBg,
    required this.warningText,
    required this.tagBorder,
  });

  factory _WalletCs.of(BuildContext context) {
    final cs = WalletPageColors.of(context);
    return _WalletCs(
      dark: cs.dark,
      bg: cs.bg,
      card: cs.card,
      text: cs.text,
      subText: cs.subText,
      line: cs.line,
      shadow: cs.shadow,
      red: cs.red,
      blue: cs.blue,
      warningBg: cs.warningBg,
      warningText: cs.warningText,
      tagBorder: cs.tagBorder,
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
      ..strokeWidth = w * 0.078
      ..strokeCap = StrokeCap.round;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.07, h * 0.11, w * 0.86, h * 0.16),
        Radius.circular(w * 0.02),
      ),
      fill,
    );

    final stem = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.405, h * 0.11, w * 0.19, h * 0.78),
      Radius.circular(w * 0.02),
    );

    canvas.drawRRect(stem, fill);

    final oval = Rect.fromCenter(
      center: Offset(w / 2, h * 0.53),
      width: w * 0.93,
      height: h * 0.28,
    );

    canvas.drawArc(oval, 0.06, 6.16, false, stroke);

    final cover = Paint()
      ..color = const Color(0xFF26A17B)
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

enum _WalletHomeAction {
  receive,
  transfer,
  swap,
  record,
}

class _ActItem {
  final _WalletHomeAction action;

  final String txt;
  /// 图标下方的用途说明。
  final String? hint;

  const _ActItem({
    required this.action,

    required this.txt,
    this.hint,
  });
}
