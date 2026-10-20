import 'package:openim_common/localization.dart';
import 'package:openim/routes/swipe_back/app_page_route.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import '../../../../core/controller/im_controller.dart';
import '../../../../pages/mine/settings/openim_profile_service.dart';
import '../../../../pages/mine/settings/settings_service.dart';
import '../../../../pages/mine/settings/pages/trade_password_page.dart';
import '../../../../services/fund_api.dart';
import '../../../../services/fund_pending_store.dart';
import '../../../../widgets/payment/password_payment_sheet.dart';
import '../../../wallet/data/wallet_fund_api.dart';
import '../../data/group_feature_api.dart';
import '../../models/group_feature_context.dart';
import '../data/live_api.dart';
import '../data/live_permission_state.dart';
import '../models/live_errors.dart';
import '../models/live_models.dart';
import '../models/live_summary_events.dart';
import '../models/live_tip_currency.dart';
import '../widgets/live_sheet_surface.dart';
import '../tipping/live_tip_balance.dart';
import '../tipping/live_tip_form.dart';

class GroupLiveTipSheet {
  static Future<void> show(BuildContext context,
          {required GroupFeatureContext featureContext,
          required LiveSession session,
          SettingsService? security,
          WalletFundApi? walletApi,
          FundPendingStore? pendingStore}) =>
      showModalBottomSheet<void>(
          context: context,
          useSafeArea: true,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => LiveSheetSurface(
              child: _LiveTipForm(
                  featureContext: featureContext,
                  session: session,
                  security: security,
                  walletApi: walletApi,
                  pendingStore: pendingStore)));
}

class _LiveTipForm extends StatefulWidget {
  const _LiveTipForm(
      {required this.featureContext,
      required this.session,
      this.security,
      this.walletApi,
      this.pendingStore});
  final GroupFeatureContext featureContext;
  final LiveSession session;
  final SettingsService? security;
  final WalletFundApi? walletApi;
  final FundPendingStore? pendingStore;
  @override
  State<_LiveTipForm> createState() => _LiveTipFormState();
}

class _LiveTipFormState extends State<_LiveTipForm>
    with WidgetsBindingObserver {
  final _amount = TextEditingController(), _memo = TextEditingController();
  List<LiveTipCurrency> _currencies = const [];
  late final FundPendingStore _store;
  late final Future<String> _anchorNickname;
  late final LiveTipBalance _balance;
  LiveTipCurrency? _currency;
  Map<String, dynamic>? _pending;
  Object? _error;
  bool _loading = true, _busy = false;
  bool _foreground = true, _isLive = false;
  late final LivePermissionState _permissions;
  late final LiveSummaryEvents _summaries;
  StreamSubscription<Map<String, dynamic>>? _events;
  GroupFeatureContext get featureContext => _permissions.context;
  bool get sessionCurrent => mounted && _permissions.sessionCurrent;
  bool get current => sessionCurrent && _foreground && _permissions.current;
  bool get canTip =>
      current &&
      _isLive &&
      widget.session.anchorID != featureContext.currentUserID &&
      featureContext.capabilities.live.canTip &&
      (_pending == null ||
          _currencies.any((value) => value.code == _pending!['currency']));
  String get scope =>
      'group-live-tip:${widget.featureContext.groupID}:${widget.session.id}';
  bool get _pendingUnavailable =>
      _pending != null &&
      !_currencies.any((value) => value.code == _pending!['currency']);
  @override
  void initState() {
    super.initState();
    _permissions = LivePermissionState(widget.featureContext);
    _permissions.addListener(_permissionsChanged);
    _anchorNickname = _loadAnchorNickname();
    _summaries = LiveSummaryEvents(widget.featureContext.features);
    _isLive = widget.session.status == LiveStatus.live &&
        (!widget.featureContext.features.valid ||
            (widget.featureContext.features.live.isActive &&
                widget.featureContext.features.live.sessionID ==
                    widget.session.id));
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _permissions.setActive(_foreground);
    final walletToken = DataSp.chatToken;
    final walletApi = widget.walletApi ??
        WalletFundApi(api: FundApi(baseUrl: widget.featureContext.api.baseUrl));
    _balance = LiveTipBalance(
        load: walletApi.fetchBalances,
        current: () => sessionCurrent && DataSp.chatToken == walletToken);
    _balance.setActive(_foreground);
    unawaited(_balance.refresh());
    _syncCurrencies();
    _events = widget.featureContext.events.listen((event) {
      final summary = _summaries.accept(event, widget.featureContext.groupID);
      if (summary == null || !sessionCurrent) return;
      setState(() {
        // The business DTO confirms LIVE; an older same-session SDK mirror
        // must not move it back to a pre-live state. Terminal/new sessions do.
        _isLive = _isLive &&
            summary.sessionID == widget.session.id &&
            summary.isActive;
        if (!_isLive) _error = StateError(AppCopy.text('当前场次未在直播中，暂不能打赏'));
      });
    });
    _store = widget.pendingStore ??
        FundPendingStore(
            accountKey:
                '${widget.featureContext.api.baseUrl}:${widget.featureContext.currentUserID}');
    _load();
  }

  Future<String> _loadAnchorNickname() async {
    final anchorID = widget.session.anchorID;
    if (!sessionCurrent || anchorID.isEmpty) return '主播';
    try {
      final users = await OpenIM.iMManager.userManager.getUsersInfo(
          userIDList: [anchorID]).timeout(const Duration(seconds: 5));
      if (!sessionCurrent) return '主播';
      for (final user in users) {
        if (user.userID != anchorID) continue;
        final nickname = graphemeTrim(user.nickname ?? '');
        if (nickname.isNotEmpty) return nickname;
      }
    } catch (_) {
      // Optional display metadata must not interrupt or retarget the payment.
    }
    return '主播';
  }

  void _syncCurrencies() {
    _currencies =
        LiveTipCurrency.fromCapabilities(featureContext.capabilities.live.raw)
            .where((value) =>
                (value.code == 'USDT' && value.decimals == 6) ||
                (value.code == 'BI99' && value.decimals == 2))
            .toList(growable: false);
    final selected =
        _currencies.where((value) => value.code == _currency?.code);
    _currency = selected.firstOrNull ?? _currencies.firstOrNull;
  }

  void _permissionsChanged() {
    if (!mounted) return;
    _syncCurrencies();
    if (!canTip && !_loading)
      _error = StateError(AppCopy.text('当前场次或打赏权限已变化，请稍后重试'));
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _permissions.setActive(_foreground);
    _balance.setActive(_foreground);
    if (_foreground) unawaited(_balance.refresh());
    if (_foreground && !_busy) unawaited(_load());
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    if (!sessionCurrent || !_foreground) return;
    try {
      await _permissions.refresh();
      if (!current) return;
      _syncCurrencies();
      final pending = await _store.read(scope);
      if (!current) return;
      if (pending != null) {
        if (pending['liveSessionId'] != widget.session.id ||
            pending['groupID'] != widget.featureContext.groupID ||
            pending['clientOrderID'] is! String ||
            pending.containsKey('payPin')) {
          throw const FormatException('待确认打赏记录不完整，请核对账单');
        }
        // Keep even a retired-currency order locked; never replace it with a
        // new currency/order when restoring an uncertain payment.
        _pending = pending;
        final matches = _currencies.where((v) => v.code == pending['currency']);
        if (matches.isEmpty) {
          return;
        }
        _currency = matches.first;
        _amount.text = '${pending['amountText'] ?? ''}';
        _memo.text = '${pending['memo'] ?? ''}';
        if (_currency!.units(_amount.text) != pending['amount']) {
          throw const FormatException('待确认打赏金额不完整');
        }
      }
    } catch (error) {
      if (sessionCurrent && _foreground) _error = error;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _passwordReady() async {
    final service =
        widget.security ?? OpenIMProfileService(Get.find<IMController>());
    if (await service.hasTradePassword()) return current;
    if (!mounted) return false;
    if (!current) return false;
    final configure = await showAppConfirm(context,
        barrierDismissible: true,
        title: AppCopy.text('请先设置支付密码'),
        message: AppCopy.text('设置支付密码后即可打赏主播。'),
        cancelText: '取消',
        confirmText: AppCopy.text('去设置'));
    if (!mounted) return false;
    if (configure != true || !current) return false;
    await Navigator.of(context).push(AppMaterialPageRoute<void>(
        builder: (_) => TradePasswordPage(service: service)));
    return current && await service.hasTradePassword();
  }

  Future<void> _submit() async {
    if (_busy ||
        _loading ||
        !canTip ||
        _currency == null ||
        !featureContext.capabilities.live.canTip) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _permissions.refresh();
      if (!canTip) throw StateError('当前场次未在直播中或没有打赏权限');
      _syncCurrencies();
      if (_currency == null) throw const FormatException('打赏币种尚未配置');
      final units = _currency!.units(_amount.text);
      final available = _balance.forCurrency(_currency)?.available;
      // An uncertain order may already have reduced the real balance. Its
      // original idempotency key must still be allowed to resolve that result.
      if (_pending == null &&
          available != null &&
          BigInt.from(units) > available.units) {
        throw const FormatException('可用余额不足，请调整打赏金额');
      }
      if (graphemeTrim(_memo.text).characters.length > 50) {
        throw const FormatException('备注最多 50 个字');
      }
      final ready = await _passwordReady();
      if (!mounted) return;
      if (!ready || !canTip) return;
      FocusScope.of(context).unfocus();
      final draft = _pending ??
          <String, dynamic>{
            'clientOrderID': 'tip_${FundApi.createClientOrderID()}',
            'groupID': widget.featureContext.groupID,
            'liveSessionId': widget.session.id,
            'currency': _currency!.code,
            'amount': units,
            'amountText': _amount.text.trim(),
            'memo': graphemeTrim(_memo.text)
          };
      final result = await showPasswordPaymentSheet<Map<String, dynamic>>(
          context: context,
          builder: (_) => PasswordPaymentSheet<Map<String, dynamic>>(
              title: AppCopy.text('确认打赏'),
              summary: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${draft['amountText']} ${_currency!.label}',
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                FutureBuilder<String>(
                    future: _anchorNickname,
                    builder: (_, snapshot) => Text(
                        AppCopy.format('打赏给 {#0}',
                            [sessionCurrent ? snapshot.data ?? '主播' : '主播']),
                        textAlign: TextAlign.center)),
                if ('${draft['memo']}'.isNotEmpty) Text('${draft['memo']}')
              ]),
              errorMessage: liveErrorMessage,
              onPay: (pin) => _pay(draft, pin)));
      if (!mounted) return;
      if (result != null && sessionCurrent && _foreground) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (sessionCurrent && _foreground) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Map<String, dynamic>> _pay(
      Map<String, dynamic> draft, String pin) async {
    if (!canTip) throw StateError('当前场次未在直播中或没有打赏权限');
    final hadPending = _pending != null;
    var sent = false;
    try {
      await _permissions.refresh(force: true);
      if (!canTip) throw StateError('当前场次未在直播中或没有打赏权限');
      if (!_currencies.any((value) => value.code == draft['currency'])) {
        throw const FormatException('该打赏币种当前不可用，请核对原交易');
      }
      await _store.save(scope, draft);
      if (!canTip) throw StateError('当前场次未在直播中或没有打赏权限');
      setState(() => _pending = draft);
      sent = true;
      final result = await LiveApi(featureContext).tip(
          id: widget.session.id,
          currency: draft['currency'],
          amount: draft['amount'],
          password: pin,
          orderID: draft['clientOrderID'],
          memo: draft['memo']);
      // Cleanup cannot turn a confirmed transaction into a second payment.
      try {
        await _store.clear(scope, clientOrderID: draft['clientOrderID']);
      } catch (_) {}
      if (!sessionCurrent) throw StateError('登录状态已变化，请重新进入');
      setState(() => _pending = null);
      return result;
    } catch (error) {
      if (sent &&
          !hadPending &&
          error is GroupFeatureException &&
          error.code != '20062' &&
          !error.unknownResult &&
          !error.authRequired) {
        try {
          await _store.clear(scope, clientOrderID: draft['clientOrderID']);
          if (current) setState(() => _pending = null);
        } catch (_) {}
      }
      if (error is FundPendingConflict) {
        await _load();
        throw const PasswordPaymentException('已有一笔打赏待确认，请关闭支付窗口后重试原交易');
      }
      rethrow;
    } finally {
      unawaited(_balance.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_events?.cancel() ?? Future<void>.value());
    _permissions.removeListener(_permissionsChanged);
    _permissions.dispose();
    _balance.dispose();
    _amount.dispose();
    _memo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: _balance,
      builder: (_, __) => LiveTipForm(
          currencies: _currencies,
          currency: _currency,
          amount: _amount,
          memo: _memo,
          loading: _loading,
          busy: _busy,
          pending: _pending != null,
          pendingUnavailable: _pendingUnavailable,
          balance: _balance.forCurrency(_currency),
          balanceLoading: _balance.loading,
          balanceFailed: _balance.failed,
          error: _error == null ? null : liveErrorMessage(_error!),
          onRefreshBalance: _balance.refresh,
          onCurrency: (code) => setState(() {
                _currency = _currencies.firstWhere((v) => v.code == code);
                _error = null;
              }),
          onAmountChanged: () => setState(() => _error = null),
          onClose: () => Navigator.of(context).pop(),
          onSubmit: canTip &&
                  _currency != null &&
                  (_pending != null || _amount.text.trim().isNotEmpty)
              ? _submit
              : null));
}
