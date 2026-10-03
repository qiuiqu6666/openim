import 'package:flutter/material.dart';

import 'host/wallet_i18n.dart';
import 'host/wallet_navigation.dart';
import 'order/wallet_order.dart';
import 'pay_auth_helper.dart';
import 'wallet_asset_record_screen.dart';
import 'wallet_repository.dart';
import 'widgets/wallet_page_colors.dart';
import 'withdraw_chain_review_screen.dart';

enum WithdrawTransferMode { friend, chain }

class WithdrawTransferConfirmScreen extends StatefulWidget {
  final WithdrawTransferMode mode;
  final CoinDto coin;
  final WalletPayMethodDto payMethod;
  final String targetValue;
  final String? targetName;
  final String? targetAvatar;

  const WithdrawTransferConfirmScreen({
    super.key,
    required this.mode,
    required this.coin,
    required this.payMethod,
    required this.targetValue,
    this.targetName,
    this.targetAvatar,
  });

  @override
  State<WithdrawTransferConfirmScreen> createState() =>
      _WithdrawTransferConfirmScreenState();
}

class _WithdrawTransferConfirmScreenState
    extends State<WithdrawTransferConfirmScreen> {
  final TextEditingController _amountController = TextEditingController();

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  String get _amountRaw => _amountController.text.trim();

  WalletAmount? get _amount => WalletAmount.parse(
        _amountRaw,
        coin: widget.payMethod.coin,
        scale: widget.payMethod.scale,
      );

  String get _displayAmountText => _amount?.text ?? '0';

  bool get _supportsChainWithdraw =>
      widget.payMethod.coin.toUpperCase() == 'USDT';

  bool get _canContinue =>
      _amount?.isPositive == true &&
      (widget.mode != WithdrawTransferMode.chain || _supportsChainWithdraw);

  String get _friendName {
    final value = widget.targetName?.trim() ?? '';
    return value.isEmpty ? widget.targetValue : value;
  }

  String get _shortAddress {
    final value = widget.targetValue.trim();
    if (value.length <= 16) return value;
    return '${value.substring(0, 8)}...${value.substring(value.length - 8)}';
  }

  void _setAmount(String value) {
    final clean = WalletAmount.clean(value, scale: widget.payMethod.scale);
    _amountController.value = TextEditingValue(
      text: clean,
      selection: TextSelection.collapsed(offset: clean.length),
    );
    setState(() {});
  }

  void _appendKey(String value) {
    var current = _amountRaw;
    if (value == '.') {
      if (current.contains('.')) return;
      current = current.isEmpty ? '0.' : '$current.';
    } else {
      current = '$current$value';
    }
    _setAmount(current);
  }

  void _deleteKey() {
    final current = _amountRaw;
    if (current.isEmpty) return;
    _setAmount(current.substring(0, current.length - 1));
  }

  void _applyPercent(int percent) {
    final balMinor = widget.payMethod.balMinor;
    if (balMinor <= 0) return;
    var amountMinor = (balMinor * percent) ~/ 100;
    if (widget.payMethod.scale > 2) {
      var factor = 1;
      for (var i = 0; i < widget.payMethod.scale - 2; i++) {
        factor *= 10;
      }
      amountMinor = (amountMinor ~/ factor) * factor;
    }
    _setAmount(WalletAmount.formatMinor(amountMinor, widget.payMethod.scale));
  }

  String _unavailableText(AppI18n i18n) => i18n.t(
        zhHans: '钱包服务暂不可用',
        zhHant: '錢包服務暫不可用',
        en: 'Wallet service is temporarily unavailable.',
        ja: 'ウォレットサービスは一時的に利用できません。',
        ko: '지갑 서비스를 일시적으로 사용할 수 없습니다.',
      );

  String _minWithdrawText(AppI18n i18n) => i18n.t(
        zhHans: '最小提币数量 --',
        zhHant: '最小提幣數量 --',
        en: 'Minimum withdrawal --',
        ja: '最小出金数量 --',
        ko: '최소 출금 수량 --',
      );

  String _feeText(AppI18n i18n) => i18n.t(
        zhHans: '手续费 --',
        zhHant: '手續費 --',
        en: 'Fee --',
        ja: '手数料 --',
        ko: '수수료 --',
      );

  Future<String?> _submitUnavailable(String _) async {
    try {
      throw const WalletBackendUnavailableException();
    } on WalletBackendUnavailableException {
      return _unavailableText(AppI18n.of(context));
    }
  }

  Future<void> _continue() async {
    final amount = _amount;
    if (amount == null || !amount.isPositive) return;
    if (widget.mode == WithdrawTransferMode.chain) {
      if (!_supportsChainWithdraw) return;
      await openWalletPage<void>(
        context,
        WithdrawChainReviewScreen(
          coin: widget.coin,
          payMethod: widget.payMethod,
          toAddress: widget.targetValue,
          amountMinor: amount.minor,
        ),
      );
      return;
    }

    final i18n = AppI18n.of(context);
    await PayAuthHelper.collectAndSubmit(
      context: context,
      title: i18n.t(
        zhHans: '转出给好友',
        zhHant: '轉出給好友',
        en: 'Transfer to Friend',
        ja: '友達へ送金',
        ko: '친구에게 송금',
      ),
      amountText: amount.text,
      amountCoin: widget.payMethod.coin,
      payText: '${widget.payMethod.coin} ${widget.payMethod.net}'.trim(),
      payCoinCode: widget.payMethod.code,
      payLogoUrl: widget.payMethod.logoUrl,
      receiverName: _friendName,
      receiverId: widget.targetValue,
      receiverAvatar: widget.targetAvatar,
      walletSubtitle: widget.payMethod.bal.trim().isEmpty
          ? '--'
          : '${widget.payMethod.bal} ${widget.payMethod.coin}',
      onSubmit: _submitUnavailable,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == WithdrawTransferMode.friend) {
      return _buildFriendView(context);
    }
    return _buildChainView(context);
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final i18n = AppI18n.of(context);
    final appBar = WalletAppBarColors.of(context);
    return AppBar(
      leading: const AppBackButton(),
      centerTitle: true,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      backgroundColor: appBar.background,
      foregroundColor: appBar.title,
      systemOverlayStyle: walletPageOverlayStyle(context),
      leadingWidth: 54,
      title: Text(
        i18n.format(
          zhHans: '转出 {coin}',
          zhHant: '轉出 {coin}',
          en: 'Send {coin}',
          ja: '{coin} を送金',
          ko: '{coin} 보내기',
          vars: {'coin': widget.payMethod.coin},
        ),
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: appBar.title,
        ),
      ),
      actions: [
        IconButton(
          onPressed: () => openWalletPage<void>(
            context,
            const WalletWithdrawRecordScreen(),
          ),
          icon: Icon(
            Icons.access_time_rounded,
            color: appBar.icon,
            size: 28,
          ),
        ),
      ],
    );
  }

  Widget _buildNextButton(BuildContext context) {
    final i18n = AppI18n.of(context);
    final cs = WalletPageColors.of(context);
    return ElevatedButton(
      onPressed: _canContinue ? _continue : null,
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: cs.blue,
        disabledBackgroundColor: cs.disabledButton,
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white.withValues(alpha: 0.88),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      child: Text(
        i18n.t(
          zhHans: '下一步',
          zhHant: '下一步',
          en: 'Next',
          ja: '次へ',
          ko: '다음',
        ),
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildPercentRow() {
    return Row(
      children: [
        Expanded(child: _PercentKey(label: '25%', onTap: () => _applyPercent(25))),
        const SizedBox(width: 10),
        Expanded(child: _PercentKey(label: '50%', onTap: () => _applyPercent(50))),
        const SizedBox(width: 10),
        Expanded(child: _PercentKey(label: '75%', onTap: () => _applyPercent(75))),
        const SizedBox(width: 10),
        Expanded(child: _PercentKey(label: '100%', onTap: () => _applyPercent(100))),
      ],
    );
  }

  Widget _buildFriendView(BuildContext context) {
    final i18n = AppI18n.of(context);
    final cs = WalletPageColors.of(context);
    return wrapWalletPage(
      context,
      Scaffold(
        backgroundColor: cs.bg,
        appBar: _buildAppBar(context),
        body: SafeArea(
          top: false,
          child: _WithdrawAmountEntryLayout(
            onKeyTap: _appendKey,
            onDeleteTap: _deleteKey,
            nextButton: _buildNextButton(context),
            scrollContent: Column(
              children: [
                const SizedBox(height: 12),
                _FriendBalancePill(payItem: widget.payMethod),
                const SizedBox(height: 22),
                _FriendAmountDisplay(
                  amountText: _displayAmountText,
                  coin: widget.payMethod.coin,
                  fiatText: '--',
                  empty: _amountRaw.isEmpty,
                ),
                const SizedBox(height: 32),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context, rootNavigator: true).maybePop(),
                  child: _FriendRecipientCard(
                    targetName: _friendName,
                    targetValue: widget.targetValue,
                    targetAvatar: widget.targetAvatar,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    _minWithdrawText(i18n),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF8F95A3),
                      height: 1.1,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _buildPercentRow(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChainView(BuildContext context) {
    final i18n = AppI18n.of(context);
    final cs = WalletPageColors.of(context);
    return wrapWalletPage(
      context,
      Scaffold(
        backgroundColor: cs.bg,
        appBar: _buildAppBar(context),
        body: SafeArea(
          top: false,
          child: _WithdrawAmountEntryLayout(
            onKeyTap: _appendKey,
            onDeleteTap: _deleteKey,
            nextButton: _buildNextButton(context),
            scrollContent: Column(
              children: [
                const SizedBox(height: 12),
                _FriendBalancePill(payItem: widget.payMethod),
                const SizedBox(height: 22),
                _ChainAmountDisplay(
                  amountText: _displayAmountText,
                  coin: widget.payMethod.coin,
                  fiatText: '--',
                  empty: _amountRaw.isEmpty,
                ),
                const SizedBox(height: 32),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context, rootNavigator: true).maybePop(),
                  child: _ChainAddressCard(address: _shortAddress),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    _minWithdrawText(i18n),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF8F95A3),
                      height: 1.1,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    _feeText(i18n),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF8F95A3),
                      height: 1.1,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _buildPercentRow(),
                if (!_supportsChainWithdraw) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      i18n.t(
                        zhHans: '当前仅支持 USDT 链上提现',
                        zhHant: '目前僅支援 USDT 鏈上提現',
                        en: 'Only USDT on-chain withdrawals are supported.',
                        ja: '現在はUSDTのオンチェーン出金のみサポートしています。',
                        ko: '현재 USDT 온체인 출금만 지원합니다.',
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: cs.red,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WithdrawAmountEntryLayout extends StatelessWidget {
  final Widget scrollContent;
  final Widget nextButton;
  final ValueChanged<String> onKeyTap;
  final VoidCallback onDeleteTap;

  const _WithdrawAmountEntryLayout({
    required this.scrollContent,
    required this.nextButton,
    required this.onKeyTap,
    required this.onDeleteTap,
  });

  static const _nextButtonHeight = 50.0;
  static const _nextButtonPaddingV = 8.0;
  static const _minKeypadHeight = 168.0;
  static const _maxKeypadHeight = 244.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bottomSafe = MediaQuery.paddingOf(context).bottom;
        final keypadHeight = (constraints.maxHeight * 0.30)
            .clamp(_minKeypadHeight, _maxKeypadHeight)
            .toDouble();

        return Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: scrollContent,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: SizedBox(
                width: double.infinity,
                height: _nextButtonHeight,
                child: nextButton,
              ),
            ),
            SizedBox(height: _nextButtonPaddingV),
            _FriendNumberPad(
              height: keypadHeight,
              onKeyTap: onKeyTap,
              onDeleteTap: onDeleteTap,
            ),
            SizedBox(height: bottomSafe),
          ],
        );
      },
    );
  }
}

class _FriendBalancePill extends StatelessWidget {
  final WalletPayMethodDto payItem;

  const _FriendBalancePill({required this.payItem});

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final balance = payItem.bal.trim().isEmpty ? '--' : payItem.bal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      decoration: BoxDecoration(
        color: cs.inputFill,
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TokenMark(payItem: payItem, size: 26),
          const SizedBox(width: 7),
          Text(
            '${payItem.coin}: $balance',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: cs.text,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendAmountDisplay extends StatelessWidget {
  final String amountText;
  final String coin;
  final String fiatText;
  final bool empty;

  const _FriendAmountDisplay({
    required this.amountText,
    required this.coin,
    required this.fiatText,
    required this.empty,
  });

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    return Column(
      children: [
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            children: [
              TextSpan(
                text: amountText,
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w700,
                  color: empty ? cs.disabledButton : cs.blue,
                  height: 0.9,
                ),
              ),
              TextSpan(
                text: ' $coin',
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w700,
                  color: cs.blue,
                  height: 0.9,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          fiatText,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: cs.subText,
            height: 1,
          ),
        ),
      ],
    );
  }
}

class _ChainAmountDisplay extends StatelessWidget {
  final String amountText;
  final String coin;
  final String fiatText;
  final bool empty;

  const _ChainAmountDisplay({
    required this.amountText,
    required this.coin,
    required this.fiatText,
    required this.empty,
  });

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    return Column(
      children: [
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            children: [
              TextSpan(
                text: amountText,
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w700,
                  color: empty ? cs.disabledButton : cs.blue,
                  height: 0.9,
                ),
              ),
              TextSpan(
                text: ' $coin',
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w700,
                  color: cs.blue,
                  height: 0.9,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          fiatText,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: cs.subText,
            height: 1,
          ),
        ),
      ],
    );
  }
}

class _FriendRecipientCard extends StatelessWidget {
  final String targetName;
  final String targetValue;
  final String? targetAvatar;

  const _FriendRecipientCard({
    required this.targetName,
    required this.targetValue,
    required this.targetAvatar,
  });

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final cs = WalletPageColors.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
          decoration: BoxDecoration(
            color: cs.dark ? cs.inputFill : cs.surfaceAlt,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: cs.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    i18n.t(
                      zhHans: '收款人',
                      zhHant: '收款人',
                      en: 'Recipient',
                      ja: '受取人',
                      ko: '수취인',
                    ),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: cs.text,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: cs.inputFill,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: cs.line),
                    ),
                    child: Text(
                      i18n.t(
                        zhHans: '内部地址',
                        zhHant: '內部地址',
                        en: 'Internal',
                        ja: '内部',
                        ko: '내부',
                      ),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: cs.subText,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  ClipOval(
                    child: targetAvatar == null || targetAvatar!.trim().isEmpty
                        ? Container(
                            width: 32,
                            height: 32,
                            color: cs.avatarPlaceholder,
                            child: Icon(
                              Icons.person_rounded,
                              size: 17,
                              color: cs.avatarIcon,
                            ),
                          )
                        : Image.network(
                            targetAvatar!,
                            width: 32,
                            height: 32,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 32,
                              height: 32,
                              color: cs.avatarPlaceholder,
                              child: Icon(
                                Icons.person_rounded,
                                size: 17,
                                color: cs.avatarIcon,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      targetName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: cs.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    targetValue,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: cs.subText,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: cs.subText,
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          top: -8,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFFFA01B),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              i18n.t(
                zhHans: '免手续费',
                zhHant: '免手續費',
                en: 'No Fee',
                ja: '手数料無料',
                ko: '수수료 무료',
              ),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChainAddressCard extends StatelessWidget {
  final String address;

  const _ChainAddressCard({required this.address});

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final cs = WalletPageColors.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: cs.dark ? cs.inputFill : cs.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.line),
      ),
      child: Row(
        children: [
          Text(
            i18n.t(
              zhHans: '收款地址',
              zhHant: '收款地址',
              en: 'Receiving Address',
              ja: '受取アドレス',
              ko: '수령 주소',
            ),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: cs.text,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              address,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: cs.blue,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.chevron_right_rounded,
            size: 24,
            color: cs.subText,
          ),
        ],
      ),
    );
  }
}

class _PercentKey extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _PercentKey({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.inputFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: cs.text,
          ),
        ),
      ),
    );
  }
}

class _FriendNumberPad extends StatelessWidget {
  final double height;
  final ValueChanged<String> onKeyTap;
  final VoidCallback onDeleteTap;

  const _FriendNumberPad({
    required this.height,
    required this.onKeyTap,
    required this.onDeleteTap,
  });

  @override
  Widget build(BuildContext context) {
    final keys = <String>['1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '0'];
    final keyFontSize =
        (height / _WithdrawAmountEntryLayout._maxKeypadHeight * 26)
            .clamp(20.0, 26.0);
    final deleteIconSize =
        (height / _WithdrawAmountEntryLayout._maxKeypadHeight * 32)
            .clamp(24.0, 32.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: SizedBox(
        height: height,
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: 12,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio:
                (MediaQuery.sizeOf(context).width - 32) / (3 * (height / 4)),
          ),
          itemBuilder: (_, index) {
            if (index == 11) {
              return _FriendKeyCell(
                onTap: onDeleteTap,
                child: Icon(
                  Icons.backspace_outlined,
                  size: deleteIconSize,
                  color: const Color(0xFF111111),
                ),
              );
            }
            return _FriendKeyCell(
              onTap: () => onKeyTap(keys[index]),
              child: Text(
                keys[index],
                style: TextStyle(
                  fontSize: keyFontSize,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF2B2B2B),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FriendKeyCell extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;

  const _FriendKeyCell({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Center(child: child),
    );
  }
}

class _TokenMark extends StatelessWidget {
  final WalletPayMethodDto payItem;
  final double size;

  const _TokenMark({required this.payItem, required this.size});

  @override
  Widget build(BuildContext context) {
    final isUsdt = payItem.coin.toUpperCase() == 'USDT';
    final isTrx = payItem.coin.toUpperCase() == 'TRX';
    final isPlatform = payItem.badge == '99' || payItem.coin == '99';

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: isUsdt
                  ? const Color(0xFF26A17B)
                  : (isTrx ? const Color(0xFFFF001F) : payItem.color),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: isPlatform
                  ? ClipOval(
                      child: Image.asset(
                        'assets/img/platform_99.webp',
                        width: size,
                        height: size,
                        fit: BoxFit.cover,
                      ),
                    )
                  : isTrx
                      ? Image.asset(
                          'assets/img/TRX.png',
                          width: size * 0.72,
                          height: size * 0.72,
                          fit: BoxFit.contain,
                          color: Colors.white,
                          colorBlendMode: BlendMode.srcIn,
                        )
                      : isUsdt
                          ? CustomPaint(
                              size: Size(size * 0.72, size * 0.72),
                              painter: _UsdtPainter(),
                            )
                          : Text(
                              payItem.coin.isEmpty ? '?' : payItem.coin.substring(0, 1),
                              style: TextStyle(
                                fontSize: size * 0.54,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                height: 1,
                              ),
                            ),
            ),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: size * 0.38,
              height: size * 0.38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: payItem.badgeColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFF1F1F3),
                  width: 1.6,
                ),
              ),
              child: Text(
                payItem.badge,
                style: TextStyle(
                  fontSize: size * 0.16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1,
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
      ..color = const Color(0xFF26A17B)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(w * 0.35, h * 0.43, w * 0.30, h * 0.13), cover);
    canvas.drawRRect(stem, fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
