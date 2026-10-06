import 'package:flutter/foundation.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/fund_api.dart';
import '../order/wallet_order_events.dart';
import '../exchange/data/wallet_swap_error.dart';
import 'wallet_fund_api.dart';
import 'wallet_operation_pending_store.dart';

String walletOperationAccountKey(String serverURL, String accountID) =>
    '${serverURL.replaceFirst(RegExp(r'/+$'), '')}:$accountID';

FundCurrency walletFundCurrency(String code) {
  final value = code.trim().toUpperCase();
  return const ['99', '元', '99BI', 'BI99'].contains(value)
      ? FundCurrency.bi99
      : FundCurrency.parse(value);
}

class WalletOperationReceipt {
  const WalletOperationReceipt(
      {required this.order, this.fee, this.received, this.receivedCurrency});
  final WalletFundOrder order;
  final String? fee;
  final String? received;
  final FundCurrency? receivedCurrency;

  bool get accepted => order.biz == 'withdraw'
      ? const ['withdraw_done', 'withdraw_pending', 'withdraw_approved']
          .contains(order.status)
      : order.biz == 'swap' && order.status == 'done';
  bool get terminal => order.biz == 'withdraw'
      ? const ['withdraw_done', 'withdraw_failed'].contains(order.status)
      : const ['done', 'refunded'].contains(order.status);

  String get description {
    if (order.biz == 'withdraw') {
      switch (order.status) {
        case 'withdraw_done':
          return '已登记出款';
        case 'withdraw_pending':
          return '提现申请已提交，等待审核';
        case 'withdraw_approved':
          return '审核已通过，等待出款';
        case 'withdraw_failed':
          return '提现已退回';
      }
    } else if (order.biz == 'swap' && order.status == 'done') {
      final amount = received ?? order.targetAmount;
      final currency = order.targetCurrency ?? receivedCurrency;
      return amount == null || currency == null
          ? '闪兑已完成，实得金额请查看订单详情'
          : '闪兑成功，实得 $amount ${currency.displayName}';
    }
    if (order.status == 'refunded') return '订单已退款';
    return '订单状态待确认';
  }
}

/// One write per frozen draft. An uncertain write is never automatically POSTed
/// again: swaps can recover by their durable client ID when no order ID arrived.
class WalletOperationCoordinator extends ChangeNotifier {
  WalletOperationCoordinator({
    required this.kind,
    WalletFundApi? api,
    WalletOperationPendingStore? store,
    String? serverURL,
    String? accountID,
    bool Function()? isAccountCurrent,
  })  : api = api ?? WalletFundApi(),
        accountID = accountID ?? DataSp.userID ?? '',
        serverURL =
            (serverURL ?? Config.appAuthUrl).replaceFirst(RegExp(r'/+$'), ''),
        _isAccountCurrent = isAccountCurrent {
    this.store = store ?? WalletOperationPendingStore(accountKey: accountKey);
  }

  final WalletOperationKind kind;
  final WalletFundApi api;
  final String accountID;
  final String serverURL;
  final bool Function()? _isAccountCurrent;
  late final WalletOperationPendingStore store;
  static final _attempts = <String, Future<WalletOperationReceipt>>{};
  static final _finishing = <String>{};
  Future<void>? _loading;
  bool _loaded = false, _disposed = false, busy = false;
  WalletOperationDraft? draft;
  WalletOperationReceipt? receipt;
  String? error;
  int? errorCode;

  String get accountKey => walletOperationAccountKey(serverURL, accountID);
  String get _lockKey => '$accountKey:${kind.name}';
  bool get sameAccount =>
      accountID.isNotEmpty &&
      (_isAccountCurrent?.call() ??
          (DataSp.userID == accountID &&
              walletOperationAccountKey(Config.appAuthUrl, accountID) ==
                  accountKey));
  bool get unresolved => draft?.submitted == true && draft?.terminal != true;
  bool get canStartNew => draft != null && (!unresolved);
  bool get canSubmit =>
      !busy && sameAccount && draft?.submitted != true && receipt == null;

  void _requireActive() {
    if (_disposed || !sameAccount) throw StateError('账号已变化，请重新打开钱包');
  }

  void _changed() {
    if (!_disposed && sameAccount) notifyListeners();
  }

  Future<void> load() {
    if (_loaded) return Future.value();
    return _loading ??= _restore().whenComplete(() => _loading = null);
  }

  Future<void> _restore() async {
    _requireActive();
    draft = await store.read(kind);
    _requireActive();
    _loaded = true;
    _changed();
  }

  /// Durably binds security verification to the exact original business ID.
  Future<WalletOperationDraft> prepareWithdrawal({
    required FundAmount amount,
    required String toAddress,
  }) async {
    _requireActive();
    if (kind != WalletOperationKind.withdraw ||
        busy ||
        _attempts.containsKey(_lockKey) ||
        _finishing.contains(_lockKey)) {
      throw StateError('交易正在处理中，请稍后重试');
    }
    if (!amount.isPositive ||
        amount.currency == FundCurrency.bi99 ||
        amount.units > BigInt.parse('9223372036854775807') ||
        !RegExp(r'^T[1-9A-HJ-NP-Za-km-z]{33}$').hasMatch(toAddress.trim())) {
      throw const FormatException('请选择 USDT/TRX 并输入有效提现金额和地址');
    }
    busy = true;
    _changed();
    try {
      await load();
      _requireActive();
      if (draft?.submitted == true || receipt != null) {
        throw StateError('请先确认原提现状态');
      }
      final next = WalletOperationDraft(
        kind: kind,
        clientOrderID: draft?.clientOrderID ?? FundApi.createClientOrderID(),
        amount: amount,
        toAddress: toAddress.trim(),
      );
      if (draft != null && !draft!.sameRequest(next)) {
        throw StateError('原交易参数已冻结，请先创建新交易');
      }
      await store.save(next);
      _requireActive();
      draft = next;
      return next;
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<WalletOperationReceipt> submit({
    required FundAmount amount,
    required String payPassword,
    String toAddress = '',
    FundCurrency? toCurrency,
    WalletSwapQuote? quote,
    String? verifyChallengeID,
    String? verifyCode,
  }) {
    _requireActive();
    final existing = _attempts[_lockKey];
    if (existing != null || _finishing.contains(_lockKey)) {
      return Future.error(StateError('交易正在提交，请勿重复操作'));
    }
    final attempt = _submit(amount, payPassword, toAddress.trim(), toCurrency,
        quote, verifyChallengeID, verifyCode);
    _attempts[_lockKey] = attempt;
    return attempt.whenComplete(() {
      if (identical(_attempts[_lockKey], attempt)) _attempts.remove(_lockKey);
    });
  }

  Future<WalletOperationReceipt> _submit(
      FundAmount amount,
      String password,
      String toAddress,
      FundCurrency? toCurrency,
      WalletSwapQuote? quote,
      String? verifyChallengeID,
      String? verifyCode) async {
    if (!amount.isPositive || !RegExp(r'^\d{6}$').hasMatch(password)) {
      throw const FormatException('请输入有效金额和六位支付密码');
    }
    if (amount.units > BigInt.parse('9223372036854775807')) {
      throw const FormatException('金额超出支持范围');
    }
    if (kind == WalletOperationKind.withdraw &&
        (amount.currency == FundCurrency.bi99 ||
            !RegExp(r'^T[1-9A-HJ-NP-Za-km-z]{33}$').hasMatch(toAddress))) {
      throw const FormatException('请选择 USDT/TRX 并输入有效 TRON 地址');
    }
    if (kind == WalletOperationKind.swap &&
        (toCurrency == null || toCurrency == amount.currency)) {
      throw const FormatException('请选择不同的兑换币种');
    }
    if (quote != null &&
        (kind != WalletOperationKind.swap ||
            !quote.matches(amount, toCurrency!) ||
            quote.isExpired(DateTime.now()))) {
      throw const FormatException('报价已过期或与输入不一致，请重新预览');
    }
    busy = true;
    error = null;
    errorCode = null;
    _changed();
    var sent = false;
    try {
      await load();
      _requireActive();
      if (receipt != null) return receipt!;
      if (draft?.submitted == true) {
        throw StateError('原交易状态待确认，请先查询订单，勿重复提交');
      }
      final next = WalletOperationDraft(
        kind: kind,
        clientOrderID: draft?.clientOrderID ?? FundApi.createClientOrderID(),
        amount: amount,
        toAddress: toAddress,
        toCurrency: toCurrency,
        quoteID: quote?.quoteID,
        expectedReceived: quote?.estimatedReceived.decimal,
      );
      if (draft != null && !draft!.sameRequest(next)) {
        throw StateError('原交易参数已冻结，请先创建新交易');
      }
      // Persist the uncertainty marker before any network write. A crash at
      // this boundary is deliberately treated as uncertain after reopening.
      final marked = next.withState(submitted: true);
      await store.save(marked);
      draft = marked;
      _requireActive();
      sent = true;
      final WalletOperationReceipt result;
      if (kind == WalletOperationKind.withdraw) {
        final value = await api.withdraw(
          clientOrderID: next.clientOrderID,
          amount: next.amount,
          toAddress: next.toAddress,
          payPassword: password,
          verifyChallengeID: verifyChallengeID,
          verifyCode: verifyCode,
        );
        result = WalletOperationReceipt(order: value.order, fee: value.fee);
      } else {
        final value = await api.swap(
          clientOrderID: next.clientOrderID,
          amount: next.amount,
          toCurrency: next.toCurrency!,
          payPassword: password,
          quoteID: next.quoteID,
        );
        result = WalletOperationReceipt(
            order: value.order,
            received: value.received,
            receivedCurrency: next.toCurrency);
      }
      await _recordResult(result);
      _requireActive();
      return result;
    } catch (failure) {
      if (sent &&
          failure is FundApiException &&
          failure.isUncertain &&
          failure.orderID?.isNotEmpty == true) {
        final known = draft!.withState(orderID: failure.orderID);
        try {
          await store.save(known);
          draft = known;
        } catch (_) {}
      }
      // Only an explicit business refusal proves this attempt did not commit.
      // Transport/response/parse failures retain the original submitted ID.
      if (sent && failure is FundApiException && !failure.isUncertain) {
        final rejected = draft!.withState(submitted: false);
        try {
          await store.save(rejected);
          draft = rejected;
        } catch (_) {}
      }
      error = kind == WalletOperationKind.swap && !unresolved
          ? walletSwapErrorMessage(failure)
          : walletOperationError(failure, unresolved: unresolved);
      errorCode = failure is FundApiException ? failure.code : null;
      rethrow;
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<WalletOperationReceipt> refreshOrder() async {
    _requireActive();
    if (busy ||
        _attempts.containsKey(_lockKey) ||
        _finishing.contains(_lockKey)) {
      throw StateError('交易正在提交，请稍后查询');
    }
    await load();
    final orderID = draft?.orderID ?? '';
    if (orderID.isEmpty && draft?.submitted != true) {
      throw StateError('交易状态待确认，暂无服务端单号，请联系客服，勿重复提交');
    }
    busy = true;
    error = null;
    errorCode = null;
    _changed();
    try {
      final order = orderID.isNotEmpty
          ? await api.getOrder(orderID)
          : await api.getOrderByClient(draft!.clientOrderID);
      if ((orderID.isNotEmpty && order.orderID != orderID) ||
          (orderID.isEmpty && order.clientOrderID != draft!.clientOrderID)) {
        throw const FormatException('订单返回不一致');
      }
      final result = WalletOperationReceipt(
          order: order,
          fee: order.fee,
          received: order.targetAmount,
          receivedCurrency: draft?.toCurrency);
      await _recordResult(result, requireTargetCurrency: true);
      _requireActive();
      return result;
    } catch (failure) {
      error = walletOperationError(failure, unresolved: unresolved);
      errorCode = failure is FundApiException ? failure.code : null;
      rethrow;
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<void> _recordResult(WalletOperationReceipt result,
      {bool requireTargetCurrency = false}) async {
    final expected = draft!;
    final order = result.order;
    if (order.orderID.isEmpty ||
        order.biz != kind.name ||
        order.currency != expected.amount.currency ||
        FundAmount.parse(order.amount, order.currency) != expected.amount ||
        (order.clientOrderID.isNotEmpty &&
            order.clientOrderID != expected.clientOrderID) ||
        (kind == WalletOperationKind.withdraw &&
            order.toAddress != expected.toAddress) ||
        (kind == WalletOperationKind.swap &&
            (order.targetCurrency != null || requireTargetCurrency) &&
            order.targetCurrency != expected.toCurrency) ||
        (kind == WalletOperationKind.swap &&
            expected.quoteID != null &&
            (order.quoteID != expected.quoteID ||
                order.targetAmount == null ||
                (expected.expectedReceived != null &&
                    FundAmount.parse(
                            order.targetAmount!, expected.toCurrency!) !=
                        FundAmount.parse(expected.expectedReceived!,
                            expected.toCurrency!))))) {
      throw const FormatException('订单与原交易不一致，状态待确认');
    }
    // Cache confirmed responses before persistence/refresh. Cleanup failure or
    // a late response cannot cause another money write.
    receipt = result;
    draft =
        expected.withState(orderID: order.orderID, terminal: result.terminal);
    try {
      await store.save(draft!);
    } catch (_) {}
    if (result.accepted ||
        (order.biz == 'withdraw' && order.status == 'withdraw_failed')) {
      WalletOrderEvents.notifyBalance(accountKey: accountKey);
      WalletOrderEvents.notifyRecord(accountKey: accountKey);
    }
  }

  Future<void> startNewOperation() async {
    _requireActive();
    if (busy ||
        _attempts.containsKey(_lockKey) ||
        _finishing.contains(_lockKey) ||
        !canStartNew) {
      throw StateError('请先确认原交易状态');
    }
    await store.clearForNewAction(draft!);
    _requireActive();
    draft = null;
    receipt = null;
    error = null;
    errorCode = null;
    _changed();
  }

  /// Finish the closed withdrawal UI while preserving all unknown writes.
  /// Accepted orders remain server-side even while review/payment is pending.
  Future<bool> finishWithdrawalInteraction() async {
    _requireActive();
    if (kind != WalletOperationKind.withdraw ||
        busy ||
        _attempts.containsKey(_lockKey) ||
        !_finishing.add(_lockKey)) {
      throw StateError('请先确认原提现状态');
    }
    busy = true;
    _changed();
    try {
      final current = draft;
      if (current == null) return true;
      final result = receipt;
      if (result == null) {
        if (current.submitted) return false;
        await store.clearForNewAction(current);
      } else {
        final order = result.order;
        if (!(result.accepted || result.terminal) ||
            order.biz != 'withdraw' ||
            order.orderID.isEmpty ||
            (current.orderID.isNotEmpty && current.orderID != order.orderID) ||
            order.currency != current.amount.currency ||
            FundAmount.parse(order.amount, order.currency) != current.amount ||
            order.toAddress != current.toAddress ||
            (order.clientOrderID.isNotEmpty &&
                order.clientOrderID != current.clientOrderID) ||
            (order.scene.isNotEmpty && order.scene != 'chain') ||
            (order.network.isNotEmpty && order.network != 'TRON')) {
          throw StateError('请先确认原提现状态');
        }
        await store.clearConfirmedWithdrawal(current.withState(
            submitted: true,
            orderID: order.orderID,
            terminal: result.terminal));
      }
      _requireActive();
      draft = null;
      receipt = null;
      error = null;
      errorCode = null;
      _changed();
      return true;
    } finally {
      _finishing.remove(_lockKey);
      busy = false;
      _changed();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

String walletOperationError(Object failure, {bool unresolved = false}) {
  if (unresolved) return '交易状态待确认，请核对订单或联系客服，勿重复提交';
  if (failure is FundApiException || failure is FormatException) {
    return walletFundErrorMessage(failure);
  }
  if (failure is StateError &&
      RegExp(r'[\u3400-\u9FFF]').hasMatch(failure.message.toString())) {
    return failure.message.toString();
  }
  return '操作未完成，请稍后重试';
}
