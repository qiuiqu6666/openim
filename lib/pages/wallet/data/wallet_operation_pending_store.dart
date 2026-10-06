import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';

import '../../../services/fund_api.dart';

enum WalletOperationKind { withdraw, swap }

/// The reviewed request is immutable. Passwords never enter this model.
class WalletOperationDraft {
  const WalletOperationDraft({
    required this.kind,
    required this.clientOrderID,
    required this.amount,
    this.toAddress = '',
    this.toCurrency,
    this.quoteID,
    this.expectedReceived,
    this.submitted = false,
    this.orderID = '',
    this.terminal = false,
  });

  final WalletOperationKind kind;
  final String clientOrderID;
  final FundAmount amount;
  final String toAddress;
  final FundCurrency? toCurrency;
  final String? quoteID;
  final String? expectedReceived;
  final bool submitted;
  final String orderID;
  final bool terminal;

  /// Frozen business parameters shared by check, SMS and the final write.
  /// Neither the payment PIN nor the SMS proof is persisted here.
  Map<String, dynamic> get withdrawalRequest {
    if (kind != WalletOperationKind.withdraw) {
      throw StateError('该交易不是链上提现');
    }
    return {
      'clientOrderID': clientOrderID,
      'mode': 'chain',
      'network': 'TRON',
      'currency': amount.currency.code,
      'amount': amount.decimal,
      'toAddress': toAddress,
    };
  }

  Map<String, dynamic> get request => {
        'kind': kind.name,
        'clientOrderID': clientOrderID,
        'currency': amount.currency.code,
        'amount': amount.decimal,
        if (kind == WalletOperationKind.withdraw) 'toAddress': toAddress,
        if (kind == WalletOperationKind.swap) 'toCurrency': toCurrency!.code,
        if (kind == WalletOperationKind.swap && quoteID != null)
          'quoteID': quoteID,
      };

  Map<String, dynamic> toJson() => {
        ...request,
        if (expectedReceived != null) 'expectedReceived': expectedReceived,
        'submitted': submitted,
        'orderID': orderID,
        'terminal': terminal,
      };

  factory WalletOperationDraft.fromJson(Map<String, dynamic> json) {
    final kind = WalletOperationKind.values.byName(json['kind'] as String);
    final draft = WalletOperationDraft(
      kind: kind,
      clientOrderID: json['clientOrderID'] as String,
      amount: FundAmount.parse(json['amount'] as String,
          FundCurrency.parse(json['currency'] as String)),
      toAddress: json['toAddress'] as String? ?? '',
      toCurrency: json['toCurrency'] == null
          ? null
          : FundCurrency.parse(json['toCurrency'] as String),
      quoteID: json['quoteID'] as String?,
      expectedReceived: json['expectedReceived'] as String?,
      submitted: json['submitted'] == true,
      orderID: json['orderID'] as String? ?? '',
      terminal: json['terminal'] == true,
    );
    if (draft.clientOrderID.isEmpty ||
        !draft.amount.isPositive ||
        (kind == WalletOperationKind.withdraw && draft.toAddress.isEmpty) ||
        (kind == WalletOperationKind.swap &&
            (draft.toCurrency == null ||
                draft.toCurrency == draft.amount.currency))) {
      throw const FormatException('Invalid pending wallet operation');
    }
    if (draft.quoteID != null &&
        (kind != WalletOperationKind.swap ||
            draft.quoteID!.trim().isEmpty ||
            draft.quoteID!.trim() != draft.quoteID)) {
      throw const FormatException('Invalid pending quote ID');
    }
    if ((draft.quoteID == null) != (draft.expectedReceived == null)) {
      throw const FormatException('Incomplete pending quote');
    }
    if (draft.expectedReceived != null &&
        (draft.toCurrency == null ||
            !FundAmount.parse(draft.expectedReceived!, draft.toCurrency!)
                .isPositive)) {
      throw const FormatException('Invalid pending quote amount');
    }
    return draft;
  }

  WalletOperationDraft withState({
    bool? submitted,
    String? orderID,
    bool? terminal,
  }) =>
      WalletOperationDraft(
        kind: kind,
        clientOrderID: clientOrderID,
        amount: amount,
        toAddress: toAddress,
        toCurrency: toCurrency,
        quoteID: quoteID,
        expectedReceived: expectedReceived,
        submitted: submitted ?? this.submitted,
        orderID: orderID ?? this.orderID,
        terminal: terminal ?? this.terminal,
      );

  bool sameRequest(WalletOperationDraft other) =>
      jsonEncode(request) == jsonEncode(other.request);
}

/// Account-scoped durable submission marker, written before HTTP starts.
/// A known service order ID can be updated without changing the original body.
class WalletOperationPendingStore {
  WalletOperationPendingStore({required this.accountKey});
  final String accountKey;
  static final _locks = <String, Lock>{};

  String _key(WalletOperationKind kind) =>
      'wallet-operation:$accountKey:${kind.name}';

  Future<WalletOperationDraft?> read(WalletOperationKind kind) async {
    final raw = (await SharedPreferences.getInstance()).getString(_key(kind));
    return raw == null
        ? null
        : WalletOperationDraft.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map));
  }

  Future<void> save(WalletOperationDraft draft) async {
    final key = _key(draft.kind);
    await (_locks[key] ??= Lock()).synchronized(() async {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(key);
      if (raw != null) {
        final previous = WalletOperationDraft.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as Map));
        if (!previous.sameRequest(draft)) {
          throw StateError('已有一笔钱包交易，请先确认原交易状态');
        }
      }
      if (!await preferences.setString(key, jsonEncode(draft.toJson()))) {
        throw StateError('无法保存交易，请重试');
      }
    });
  }

  /// Only a separately confirmed new action can discard a terminal order.
  Future<void> clearForNewAction(WalletOperationDraft draft) async {
    final key = _key(draft.kind);
    await (_locks[key] ??= Lock()).synchronized(() async {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(key);
      if (raw == null) return;
      final previous = WalletOperationDraft.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
      if (!previous.sameRequest(draft) ||
          (previous.submitted && !previous.terminal)) {
        throw StateError('请先确认原交易状态');
      }
      if (!await preferences.remove(key)) {
        throw StateError('无法创建新交易，请重试');
      }
    });
  }

  /// The server-confirmed order remains in history; only its local interaction
  /// marker is removed. An unknown write or another order can never be cleared.
  Future<void> clearConfirmedWithdrawal(WalletOperationDraft draft) async {
    if (draft.kind != WalletOperationKind.withdraw ||
        !draft.submitted ||
        draft.orderID.isEmpty) {
      throw StateError('请先确认原提现状态');
    }
    final key = _key(draft.kind);
    await (_locks[key] ??= Lock()).synchronized(() async {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(key);
      if (raw == null) return;
      final previous = WalletOperationDraft.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
      if (!previous.sameRequest(draft) ||
          !previous.submitted ||
          (previous.orderID.isNotEmpty && previous.orderID != draft.orderID)) {
        throw StateError('请先确认原提现状态');
      }
      if (!await preferences.remove(key)) {
        throw StateError('无法恢复提现输入，请重试');
      }
    });
  }
}
