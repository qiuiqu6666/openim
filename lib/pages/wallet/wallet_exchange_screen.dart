import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'wallet_amount.dart';
import 'host/wallet_api.dart';
import 'wallet_models.dart';
import 'wallet_time.dart';
import 'host/wallet_i18n.dart';

import 'order/wallet_order.dart';
import 'order/wallet_order_events.dart';
import 'wallet_repository.dart';
import 'wallet_repository_provider.dart';
import 'wallet_store.dart';
import 'pay_auth_helper.dart';
import 'widgets/biometric_pay_enable_prompt.dart';
import 'widgets/pay_loading_overlay.dart';
import 'widgets/wallet_amount_input.dart';
import 'widgets/wallet_page_colors.dart';
import 'widgets/wallet_tip.dart';
import 'host/wallet_navigation.dart';
import 'widgets/wallet_99chat_scale.dart';

class WalletExchangeScreen extends StatefulWidget {
  const WalletExchangeScreen({super.key});

  @override
  State<WalletExchangeScreen> createState() => _WalletExchangeScreenState();
}

class _WalletExchangeScreenState extends State<WalletExchangeScreen> {
  final WalletRepository _repo = createWalletRepository();
  final TextEditingController _amountCtrl = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  String _error = '';
  WalletMe? _me;
  WalletExchangeDirection _direction = WalletExchangeDirection.usdtToPlatform;
  List<WalletExchangeOrderDto> _records = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = '';
      });
    }
    try {
      final results = await Future.wait<dynamic>([
        WalletApi.instance.getMe(),
        _repo.getExchangeRecords(),
      ]);
      if (!mounted) return;
      setState(() {
        _me = results[0] as WalletMe;
        _records = results[1] as List<WalletExchangeOrderDto>;
        _loading = false;
        _error = '';
      });
    } on WalletBackendUnavailableException {
      if (!mounted) return;
      setState(() {
        _me = null;
        _records = const [];
        _loading = false;
        _error = '';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = AppI18n.current.t(
          zhHans: '闪兑信息加载失败，请稍后重试',
          zhHant: '閃兌資訊載入失敗，請稍後重試',
          en: 'Failed to load swap info. Please try again later.',
          ja: 'スワップ情報の読み込みに失敗しました。後でもう一度お試しください。',
          ko: '스왑 정보를 불러오지 못했습니다. 나중에 다시 시도해 주세요.',
        );
      });
    }
  }

  /// 闪兑成交预估汇率：仅用 `/wallet/me` → `usdtPrice` 买卖价，不再叠客户端加价。
  double? get _quotedCnyPerUsdt {
    final price = _me?.usdtPrice;
    if (price == null) return null;
    return price.dealCnyPerUsdt(
      usdtToPlatform: _direction == WalletExchangeDirection.usdtToPlatform,
    );
  }

  bool get _rateAvailable {
    final quoted = _quotedCnyPerUsdt;
    return quoted != null && quoted > 0;
  }

  int get _availableMinor {
    final me = _me;
    if (me == null) return 0;
    return _direction == WalletExchangeDirection.usdtToPlatform
        ? me.usdtMicro
        : me.platformFen;
  }

  String get _availableText {
    return '${WalletAmount.formatMinor(_availableMinor, _direction.inputScale)} ${_direction.inputCoin}';
  }

  WalletAmount? get _parsedAmount {
    return WalletAmount.parse(
      _amountCtrl.text,
      coin: _direction.inputCoin,
      scale: _direction.inputScale,
    );
  }

  WalletAmount? get _parsedStrictAmount {
    return WalletAmount.parseStrict(
      _amountCtrl.text,
      coin: _direction.inputCoin,
      scale: _direction.inputScale,
    );
  }

  int? get _estimatedOutputMinor {
    final amount = _parsedAmount;
    final quoted = _quotedCnyPerUsdt;
    if (amount == null || amount.minor <= 0 || quoted == null || quoted <= 0) {
      return null;
    }
    // 与文档一致：向下取整（少给用户）。
    if (_direction == WalletExchangeDirection.usdtToPlatform) {
      return (((amount.minor / 1000000.0) * quoted) * 100).floor();
    }
    return (((amount.minor / 100.0) / quoted) * 1000000).floor();
  }

  String get _outputAmountDisplay {
    final minor = _estimatedOutputMinor;
    if (minor == null || minor <= 0) return '0.00';
    return _formatDisplayAmount(minor, _direction.outputScale);
  }

  String get _availableNumberText {
    if (_me == null) return '--';
    return WalletAmount.formatMinor(_availableMinor, _direction.inputScale);
  }

  String get _inputFiatText => _me == null
      ? '≈ --'
      : _fiatText(
          _parsedAmount?.minor ?? 0,
          _direction.inputCoin,
          _direction.inputScale,
        );

  String get _outputFiatText => _me == null
      ? '≈ --'
      : _fiatText(
          _estimatedOutputMinor,
          _direction.outputCoin,
          _direction.outputScale,
        );

  String get _rateText {
    final quoted = _quotedCnyPerUsdt;
    if (quoted == null || quoted <= 0) {
      return AppI18n.current.t(
        zhHans: '汇率暂不可用',
        zhHant: '匯率暫不可用',
        en: 'Rate unavailable',
        ja: 'レート利用不可',
        ko: '환율 이용 불가',
      );
    }
    final rate = quoted.toStringAsFixed(4);
    // 文档建议两侧都展示「1 USDT ≈ x 元」；保留币种代码 99。
    return '1 USDT ≈ $rate 99';
  }

  String _formatDisplayAmount(int minor, int scale) {
    if (scale <= 0) return minor.toString();
    final value = minor / _pow10(scale);
    return value.toStringAsFixed(2);
  }

  String _fiatText(int? minor, String coin, int scale) {
    if (minor == null) return '--';
    if (minor <= 0) return '≈ ¥0.00';
    if (coin.trim() == '99' || scale == WalletCurrency.platformScale) {
      return '≈ ¥${(minor / 100.0).toStringAsFixed(2)}';
    }
    final rate = _quotedCnyPerUsdt ?? 0;
    if (rate <= 0) return '--';
    final yuan = (minor / 1000000.0) * rate;
    return '≈ ¥${yuan.toStringAsFixed(2)}';
  }

  int _pow10(int n) {
    var v = 1;
    for (var i = 0; i < n; i++) {
      v *= 10;
    }
    return v;
  }

  String? _validate() {
    final i18n = AppI18n.current;
    if (!_rateAvailable) {
      return i18n.t(
        zhHans: '汇率暂不可用，请稍后再试',
        zhHant: '匯率暫不可用，請稍後再試',
        en: 'Exchange rate unavailable. Try again later.',
        ja: '為替レートが利用できません。しばらくしてから再試行してください。',
        ko: '환율을 사용할 수 없습니다. 나중에 다시 시도해 주세요.',
      );
    }
    final amount = _parsedStrictAmount;
    if (amount == null) {
      return i18n.t(
        zhHans: '请输入正确金额',
        zhHant: '請輸入正確金額',
        en: 'Enter a valid amount.',
        ja: '正しい金額を入力してください。',
        ko: '올바른 금액을 입력해 주세요.',
      );
    }
    if (amount.minor <= 0) {
      return i18n.t(
        zhHans: '请输入正确金额',
        zhHant: '請輸入正確金額',
        en: 'Enter a valid amount.',
        ja: '正しい金額を入力してください。',
        ko: '올바른 금액을 입력해 주세요.',
      );
    }
    if (amount.minor > _availableMinor) {
      return i18n.t(
        zhHans: '余额不足',
        zhHant: '餘額不足',
        en: 'Insufficient balance.',
        ja: '残高が不足しています。',
        ko: '잔액이 부족합니다.',
      );
    }
    final estimated = _estimatedOutputMinor;
    if (estimated == null || estimated <= 0) {
      return i18n.t(
        zhHans: '兑换金额过小',
        zhHant: '兌換金額過小',
        en: 'Swap amount is too small.',
        ja: '交換額が小さすぎます。',
        ko: '교환 금액이 너무 작습니다.',
      );
    }
    return null;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final err = _validate();
    if (err != null) {
      WalletTip.show(context, err);
      return;
    }
    final amount = _parsedStrictAmount!;
    final i18n = AppI18n.of(context);
    await PayLoadingOverlay.runBeforePayPrompt(context);
    if (!mounted) return;
    final auth = await PayAuthHelper.collectAndSubmit(
      context: context,
      title: i18n.t(
        zhHans: '闪兑',
        zhHant: '閃兌',
        en: 'Swap',
        ja: 'スワップ',
        ko: '스왑',
      ),
      amountText: '${amount.text} ${_direction.inputCoin}',
      payText: i18n.format(
        zhHans: '{coin} 钱包',
        zhHant: '{coin} 錢包',
        en: '{coin} Wallet',
        ja: '{coin} ウォレット',
        ko: '{coin} 지갑',
        vars: {'coin': _direction.inputCoin},
      ),
      walletSubtitle: i18n.format(
        zhHans: '可用 {amount}',
        zhHant: '可用 {amount}',
        en: 'Available {amount}',
        ja: '利用可能 {amount}',
        ko: '사용 가능 {amount}',
        vars: {'amount': _availableText},
      ),
      onSubmit: (pwd) async {
        setState(() => _submitting = true);
        try {
          final order = await _repo.exchange(
            WalletExchangeReq(
              direction: _direction,
              amount: amount.minor,
              payPin: pwd,
            ),
          );
          if (!mounted) return null;
          _amountCtrl.clear();
          WalletStore.instance.clear();
          WalletOrderEvents.notifyBalance();
          WalletOrderEvents.notifyRecord();
          await _load(silent: true);
          if (!mounted) return null;
          final got = WalletAmount.formatMinor(
            order.outputAmount,
            order.direction.outputScale,
          );
          WalletTip.show(
            context,
            i18n.format(
              zhHans: '闪兑成功，获得 {amount} {coin}',
              zhHant: '閃兌成功，獲得 {amount} {coin}',
              en: 'Swap successful. Received {amount} {coin}',
              ja: 'スワップ完了。{amount} {coin} を受け取りました',
              ko: '스왑 완료. {amount} {coin} 수령',
              vars: {
                'amount': got,
                'coin': order.direction.outputCoin,
              },
            ),
          );
          return null;
        } on WalletSubmitException catch (e) {
          return e.message;
        } catch (_) {
          return i18n.t(
            zhHans: '闪兑失败，请稍后重试',
            zhHant: '閃兌失敗，請稍後重試',
            en: 'Swap failed. Please try again later.',
            ja: 'スワップに失敗しました。後でもう一度お試しください。',
            ko: '스왑에 실패했습니다. 나중에 다시 시도해 주세요.',
          );
        } finally {
          if (mounted) {
            setState(() => _submitting = false);
          }
        }
      },
    );
    if (auth.success && mounted) {
      await BiometricPayEnablePrompt.maybeShowAfterPaySuccess(
        context,
        authMethod: auth.method ?? PayAuthMethod.manual,
        verifiedPayPin: auth.verifiedPayPin,
      );
      if (mounted) setState(() {});
    }
  }

  void _switchDirection(WalletExchangeDirection next) {
    if (_direction == next) return;
    setState(() {
      _direction = next;
      _amountCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final cs = WalletPageColors.of(context);
    final appBar = WalletAppBarColors.of(context);
    return wrapWalletPage(
      context,
      Scaffold(
        backgroundColor: cs.bg,
        appBar: AppBar(
          leading: const AppBackButton(),
          iconTheme: IconThemeData(color: appBar.icon),
          centerTitle: true,
          elevation: 0,
          scrolledUnderElevation: 0,
          shadowColor: Colors.transparent,
          backgroundColor: appBar.background,
          surfaceTintColor: Colors.transparent,
          foregroundColor: appBar.title,
          systemOverlayStyle: walletPageOverlayStyle(context),
          title: Text(
            i18n.t(
              zhHans: '闪兑',
              zhHant: '閃兌',
              en: 'Swap',
              ja: 'スワップ',
              ko: '스왑',
            ),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: appBar.title,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusScope.of(context).unfocus(),
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(
                      color: cs.blue,
                    ),
                  )
                : _error.isNotEmpty
                    ? _ExchangeErrorBox(text: _error, onRetry: _load)
                    : ListView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.fromLTRB(22.w99, 18.h99, 22.w99, 30.h99),
                        children: [
                          _SwapPanel(
                            direction: _direction,
                            controller: _amountCtrl,
                            inputAvailableText: _availableNumberText,
                            outputAmountText: _outputAmountDisplay,
                            inputFiatText: _inputFiatText,
                            outputFiatText: _outputFiatText,
                            onSwap: () => _switchDirection(
                              _direction ==
                                      WalletExchangeDirection.usdtToPlatform
                                  ? WalletExchangeDirection.platformToUsdt
                                  : WalletExchangeDirection.usdtToPlatform,
                            ),
                            onChanged: () => setState(() {}),
                          ),
                          SizedBox(height: 20.h99),
                          _CoinInfoHeader(direction: _direction),
                          SizedBox(height: 14.h99),
                          _RateRow(rateText: _rateText),
                          SizedBox(height: 24.h99),
                          _PrimaryButton(
                            enabled: !_submitting &&
                                _me != null &&
                                _rateAvailable &&
                                _validate() == null,
                            text: i18n.t(
                              zhHans: '闪兑',
                              zhHant: '閃兌',
                              en: 'Swap',
                              ja: 'スワップ',
                              ko: '스왑',
                            ),
                            onTap: _submit,
                          ),
                          SizedBox(height: 14.h99),
                          _RouteProviderLabel(),
                          SizedBox(height: 32.h99),
                          Text(
                            i18n.t(
                              zhHans: '交易记录',
                              zhHant: '交易記錄',
                              en: 'Transaction History',
                              ja: '取引履歴',
                              ko: '거래 내역',
                            ),
                            style: TextStyle(
                              fontSize: 28.sp99,
                              fontWeight: FontWeight.w700,
                              color: cs.text,
                            ),
                          ),
                          SizedBox(height: 16.h99),
                          if (_records.isEmpty)
                            const _EmptyExchangeBox()
                          else
                            ..._records
                                .map((e) => _ExchangeRecordCard(order: e)),
                        ],
                      ),
          ),
        ),
      ),
    );
  }
}

class _SwapPanel extends StatelessWidget {
  final WalletExchangeDirection direction;
  final TextEditingController controller;
  final String inputAvailableText;
  final String outputAmountText;
  final String inputFiatText;
  final String outputFiatText;
  final VoidCallback onSwap;
  final VoidCallback onChanged;

  const _SwapPanel({
    required this.direction,
    required this.controller,
    required this.inputAvailableText,
    required this.outputAmountText,
    required this.inputFiatText,
    required this.outputFiatText,
    required this.onSwap,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final cs = WalletPageColors.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(28.w99, 32.h99, 28.w99, 32.h99),
      decoration: BoxDecoration(
        color: cs.card,
        borderRadius: BorderRadius.circular(20.r99),
        boxShadow: [
          BoxShadow(
            color: cs.shadow,
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          _SwapRow(
            coin: direction.inputCoin,
            tag: i18n.t(
              zhHans: '转出',
              zhHant: '轉出',
              en: 'From',
              ja: '送金',
              ko: '보내기',
            ),
            balanceLabel: i18n.t(
              zhHans: '可用',
              zhHant: '可用',
              en: 'Available',
              ja: '利用可能',
              ko: '사용 가능',
            ),
            balanceText: inputAvailableText,
            fiatText: inputFiatText,
            onTapCoin: onSwap,
            amountController: controller,
            onAmountChanged: onChanged,
            amountHint: i18n.t(
              zhHans: '输入转出数量',
              zhHant: '輸入轉出數量',
              en: 'Enter amount',
              ja: '数量を入力',
              ko: '보낼 수량 입력',
            ),
          ),
          SizedBox(
            height: 88.h99,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Divider(height: 1, thickness: 1, color: cs.line),
                _SwapCenter(onTap: onSwap),
              ],
            ),
          ),
          _SwapRow(
            coin: direction.outputCoin,
            tag: i18n.t(
              zhHans: '接收',
              zhHant: '接收',
              en: 'To',
              ja: '受取',
              ko: '받기',
            ),
            balanceLabel: '',
            balanceText: '',
            amountText: outputAmountText,
            fiatText: outputFiatText,
            onTapCoin: onSwap,
          ),
        ],
      ),
    );
  }
}

class _SwapRow extends StatelessWidget {
  final String coin;
  final String tag;
  final String balanceLabel;
  final String balanceText;
  final String amountText;
  final String fiatText;
  final VoidCallback onTapCoin;
  final TextEditingController? amountController;
  final VoidCallback? onAmountChanged;
  final String? amountHint;

  const _SwapRow({
    required this.coin,
    required this.tag,
    required this.balanceLabel,
    required this.balanceText,
    this.amountText = '0.00',
    required this.fiatText,
    required this.onTapCoin,
    this.amountController,
    this.onAmountChanged,
    this.amountHint,
  });

  bool get _editable => amountController != null;

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final isUsdt = coin.toUpperCase() == 'USDT';
    final isPlatform = coin.trim() == '99';
    final amountStyle = TextStyle(
      fontSize: 48.sp99,
      fontWeight: FontWeight.w700,
      color: cs.text,
      height: 1.1,
    );
    final hintStyle = TextStyle(
      fontSize: 40.sp99,
      fontWeight: FontWeight.w700,
      color: cs.inputHint,
      height: 1.1,
    );
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: 140.h99),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 5,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: onTapCoin,
                  borderRadius: BorderRadius.circular(12.r99),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isUsdt)
                        _UsdtCoinIcon(size: 52.w99)
                      else if (isPlatform)
                        _PlatformCoinIcon(size: 52.w99),
                      SizedBox(width: 12.w99),
                      Text(
                        coin,
                        style: TextStyle(
                          fontSize: 32.sp99,
                          fontWeight: FontWeight.w700,
                          color: cs.text,
                          height: 1.1,
                        ),
                      ),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 32.sp99,
                        color: cs.subText,
                      ),
                      SizedBox(width: 10.w99),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 12.w99,
                          vertical: 5.h99,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surfaceAlt,
                          borderRadius: BorderRadius.circular(8.r99),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            fontSize: 22.sp99,
                            fontWeight: FontWeight.w500,
                            color: cs.subText,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (balanceText.isNotEmpty) ...[
                  SizedBox(height: 16.h99),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: '$balanceLabel ',
                          style: TextStyle(
                            fontSize: 24.sp99,
                            color: cs.subText,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        TextSpan(
                          text: balanceText,
                          style: TextStyle(
                            fontSize: 24.sp99,
                            color: cs.subText,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: 16.w99),
          Expanded(
            flex: 6,
            child: SizedBox(
              height: 140.h99,
              child: Stack(
                alignment: Alignment.centerRight,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: cs.dark ? 0.14 : 0.1,
                        child: isUsdt
                            ? _UsdtCoinIcon(size: 120.w99)
                            : isPlatform
                                ? _PlatformCoinIcon(size: 120.w99)
                                : SizedBox(width: 120.w99, height: 120.w99),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (_editable)
                        walletTapInputWrapper(
                          minHeight: 64.h99,
                          alignment: Alignment.centerRight,
                          expandWidth: true,
                          child: TextField(
                            controller: amountController,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9.]'),
                              ),
                            ],
                            onChanged: (_) => onAmountChanged?.call(),
                            maxLines: 1,
                            textAlign: TextAlign.right,
                            textAlignVertical: TextAlignVertical.center,
                            cursorColor: cs.inputCursor,
                            style: amountStyle,
                            decoration: WalletAmountInput.plainDecoration(
                              hint: amountHint ?? '0',
                              hintStyle: hintStyle,
                              collapsed: true,
                            ),
                          ),
                        )
                      else
                        Text(
                          amountText,
                          textAlign: TextAlign.right,
                          style: amountStyle,
                        ),
                      SizedBox(height: 10.h99),
                      Text(
                        fiatText,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 24.sp99,
                          color: cs.subText,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwapCenter extends StatelessWidget {
  final VoidCallback onTap;

  const _SwapCenter({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final size = 80.w99;
    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: cs.blue,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: cs.blue.withValues(alpha: 0.28),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.swap_vert_rounded,
            size: 44.sp99,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _CoinInfoHeader extends StatelessWidget {
  final WalletExchangeDirection direction;

  const _CoinInfoHeader({
    required this.direction,
  });

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final cs = WalletPageColors.of(context);
    return Row(
      children: [
        Icon(
          Icons.bar_chart_rounded,
          size: 28.sp99,
          color: cs.blue,
        ),
        SizedBox(width: 6.w99),
        Text(
          i18n.t(
            zhHans: '查看币种信息',
            zhHant: '查看幣種資訊',
            en: 'View Token Info',
            ja: '通貨情報を見る',
            ko: '코인 정보 보기',
          ),
          style: TextStyle(
            fontSize: 24.sp99,
            fontWeight: FontWeight.w600,
            color: cs.text,
          ),
        ),
        const Spacer(),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: direction.inputCoin,
                style: TextStyle(
                  fontSize: 22.sp99,
                  fontWeight: FontWeight.w600,
                  color: cs.subText,
                ),
              ),
              TextSpan(
                text: ' / ',
                style: TextStyle(
                  fontSize: 22.sp99,
                  fontWeight: FontWeight.w600,
                  color: cs.subText,
                ),
              ),
              TextSpan(
                text: direction.outputCoin,
                style: TextStyle(
                  fontSize: 22.sp99,
                  fontWeight: FontWeight.w700,
                  color: cs.blue,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RateRow extends StatelessWidget {
  final String rateText;

  const _RateRow({
    required this.rateText,
  });

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final cs = WalletPageColors.of(context);
    return Container(
      height: 72.h99,
      padding: EdgeInsets.symmetric(horizontal: 24.w99),
      decoration: BoxDecoration(
        color: cs.card,
        borderRadius: BorderRadius.circular(14.r99),
      ),
      child: Row(
        children: [
          Text(
            i18n.t(
              zhHans: '汇率',
              zhHant: '匯率',
              en: 'Rate',
              ja: 'レート',
              ko: '환율',
            ),
            style: TextStyle(
              fontSize: 24.sp99,
              fontWeight: FontWeight.w600,
              color: cs.subText,
            ),
          ),
          const Spacer(),
          Text(
            rateText,
            style: TextStyle(
              fontSize: 24.sp99,
              fontWeight: FontWeight.w600,
              color: cs.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final bool enabled;
  final String text;
  final VoidCallback onTap;

  const _PrimaryButton({
    required this.enabled,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = WalletPageColors.of(context);
    final bg = enabled ? cs.blue : cs.disabledButton;
    return SizedBox(
      height: 88.h99,
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(14.r99),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14.r99),
              gradient: enabled
                  ? LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        bg,
                        Color.lerp(bg, Colors.white, 0.12) ?? bg,
                        bg,
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    )
                  : null,
              color: enabled ? null : bg,
            ),
            child: Stack(
              children: [
                if (enabled)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ButtonWavePainter(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                if (enabled)
                  Positioned(
                    right: 28.w99,
                    top: 16.h99,
                    child: Row(
                      children: [
                        _SparkDot(size: 5.w99),
                        SizedBox(width: 6.w99),
                        _SparkDot(size: 7.w99),
                        SizedBox(width: 5.w99),
                        _SparkDot(size: 4.w99),
                      ],
                    ),
                  ),
                Center(
                  child: Text(
                    text,
                    style: TextStyle(
                      fontSize: 30.sp99,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
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

class _SparkDot extends StatelessWidget {
  final double size;

  const _SparkDot({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _ButtonWavePainter extends CustomPainter {
  final Color color;

  _ButtonWavePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path();
    final midY = size.height * 0.62;
    path.moveTo(0, midY);
    path.cubicTo(
      size.width * 0.2,
      midY - 8,
      size.width * 0.35,
      midY + 10,
      size.width * 0.55,
      midY,
    );
    path.cubicTo(
      size.width * 0.72,
      midY - 8,
      size.width * 0.85,
      midY + 6,
      size.width,
      midY - 2,
    );
    canvas.drawPath(path, paint);

    final path2 = Path();
    final midY2 = size.height * 0.78;
    path2.moveTo(0, midY2);
    path2.cubicTo(
      size.width * 0.25,
      midY2 + 6,
      size.width * 0.4,
      midY2 - 8,
      size.width * 0.6,
      midY2,
    );
    path2.cubicTo(
      size.width * 0.78,
      midY2 + 6,
      size.width * 0.9,
      midY2 - 4,
      size.width,
      midY2 + 2,
    );
    canvas.drawPath(path2, paint);
  }

  @override
  bool shouldRepaint(covariant _ButtonWavePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _RouteProviderLabel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final cs = WalletPageColors.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.verified_user_outlined,
          size: 22.sp99,
          color: cs.subText,
        ),
        SizedBox(width: 6.w99),
        Text(
          i18n.t(
            zhHans: '由 SUN.io 提供路由服务',
            zhHant: '由 SUN.io 提供路由服務',
            en: 'Routing powered by SUN.io',
            ja: 'ルーティング提供: SUN.io',
            ko: '라우팅 제공: SUN.io',
          ),
          style: TextStyle(
            fontSize: 22.sp99,
            color: cs.subText,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ExchangeRecordCard extends StatelessWidget {
  final WalletExchangeOrderDto order;

  const _ExchangeRecordCard({
    required this.order,
  });

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final cs = WalletPageColors.of(context);
    final rate = _snapshotRate(i18n, order.rateSnapshot, order.direction);
    return Container(
      margin: EdgeInsets.only(bottom: 14.h99),
      padding: EdgeInsets.all(22.w99),
      decoration: BoxDecoration(
        color: cs.card,
        borderRadius: BorderRadius.circular(18.r99),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _title(i18n),
            style: TextStyle(
              fontSize: 26.sp99,
              fontWeight: FontWeight.w700,
              color: cs.text,
            ),
          ),
          SizedBox(height: 10.h99),
          Text(
            _pairText,
            style: TextStyle(
              fontSize: 26.sp99,
              fontWeight: FontWeight.w700,
              color: cs.dark ? cs.text : cs.blue,
            ),
          ),
          SizedBox(height: 12.h99),
          Text(
            _timeText,
            style: TextStyle(
              fontSize: 22.sp99,
              color: cs.dark ? cs.text : cs.subText,
            ),
          ),
          if (rate.isNotEmpty) ...[
            SizedBox(height: 6.h99),
            Text(
              rate,
              style: TextStyle(
                fontSize: 22.sp99,
                color: cs.dark ? cs.text : cs.subText,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _title(AppI18n i18n) {
    return order.direction == WalletExchangeDirection.usdtToPlatform
        ? i18n.t(
            zhHans: 'USDT 兑换 99',
            zhHant: 'USDT 兌換 99',
            en: 'USDT to 99',
            ja: 'USDT → 99',
            ko: 'USDT → 99',
          )
        : i18n.t(
            zhHans: '99 兑换 USDT',
            zhHant: '99 兌換 USDT',
            en: '99 to USDT',
            ja: '99 → USDT',
            ko: '99 → USDT',
          );
  }

  String get _pairText {
    return '${WalletAmount.formatMinor(order.inputAmount, order.direction.inputScale)} ${order.direction.inputCoin} -> ${WalletAmount.formatMinor(order.outputAmount, order.direction.outputScale)} ${order.direction.outputCoin}';
  }

  String get _timeText {
    final parsed = parseWalletApiTimeToLocal(order.createdAt);
    if (parsed == null) return order.createdAt;
    return DateFormat('yyyy-MM-dd HH:mm').format(parsed);
  }

  String _snapshotRate(
    AppI18n i18n,
    String raw,
    WalletExchangeDirection direction,
  ) {
    if (raw.trim().isEmpty) return '';
    try {
      final decoded = jsonDecode(raw);
      final rate = WalletExchangeRate.parse(decoded);
      if (rate == null) return '';
      final base = rate.usdCny * (1 + rate.markupBps / 10000.0);
      final factor = rate.floatBps / 10000.0;
      final quoted = direction == WalletExchangeDirection.usdtToPlatform
          ? base * (1 - factor)
          : base * (1 + factor);
      return i18n.format(
        zhHans: '成交参考汇率 1 USDT ≈ {rate} 99',
        zhHant: '成交參考匯率 1 USDT ≈ {rate} 99',
        en: 'Reference rate 1 USDT ≈ {rate} 99',
        ja: '参考レート 1 USDT ≈ {rate} 99',
        ko: '참고 환율 1 USDT ≈ {rate} 99',
        vars: {'rate': quoted.toStringAsFixed(4)},
      );
    } catch (_) {
      return '';
    }
  }
}

class _ExchangeErrorBox extends StatelessWidget {
  final String text;
  final Future<void> Function({bool silent}) onRetry;

  const _ExchangeErrorBox({
    required this.text,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final cs = WalletPageColors.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(color: cs.text),
          ),
          SizedBox(height: 12.h99),
          TextButton(
            onPressed: () => onRetry(),
            child: Text(
              i18n.t(
                zhHans: '重试',
                zhHant: '重試',
                en: 'Retry',
                ja: '再試行',
                ko: '다시 시도',
              ),
              style: TextStyle(color: cs.blue),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyExchangeBox extends StatelessWidget {
  const _EmptyExchangeBox();

  @override
  Widget build(BuildContext context) {
    final i18n = AppI18n.of(context);
    final cs = WalletPageColors.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 48.h99),
      decoration: BoxDecoration(
        color: cs.card,
        borderRadius: BorderRadius.circular(18.r99),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/img/empty.webp',
            width: 160.w99,
          ),
          SizedBox(height: 18.h99),
          Text(
            i18n.t(
              zhHans: '无记录',
              zhHant: '無記錄',
              en: 'No records',
              ja: '記録はありません',
              ko: '기록이 없습니다',
            ),
            style: TextStyle(
              fontSize: 26.sp99,
              fontWeight: FontWeight.w600,
              color: cs.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _UsdtCoinIcon extends StatelessWidget {
  final double size;

  const _UsdtCoinIcon({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: Container(
          color: const Color(0xFF26A17B),
          alignment: Alignment.center,
          child: CustomPaint(
            size: Size(size * 0.62, size * 0.62),
            painter: _UsdtPainter(),
          ),
        ),
      ),
    );
  }
}

class _PlatformCoinIcon extends StatelessWidget {
  final double size;

  const _PlatformCoinIcon({required this.size});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset(
        'assets/img/platform_99.webp',
        width: size,
        height: size,
        fit: BoxFit.cover,
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
    canvas.drawRect(
      Rect.fromLTWH(w * 0.35, h * 0.43, w * 0.30, h * 0.13),
      cover,
    );
    canvas.drawRRect(stem, fill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
