import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../services/fund_api.dart';
import '../../../widgets/payment/password_payment_sheet.dart';
import '../withdrawal_security/withdrawal_security.dart';

/// Security credentials stay in memory; the payment owner persists only the
/// immutable business request immediately before the financial write.
class FundTransferAuthorization {
  FundTransferAuthorization(this.api);
  final FundApi api;
  String? _verifiedRequest;
  FundSecurityProof? _proof;

  void invalidate() {
    _verifiedRequest = null;
    _proof = null;
  }

  Future<FundSecurityProof> authorize(BuildContext context,
      Map<String, dynamic> request, bool Function() isCurrent) async {
    if (!isCurrent()) throw const PasswordPaymentException('登录状态已变更，请重新打开页面');
    final transaction = FundSecurityRequest.transfer(request);
    final fingerprint = jsonEncode(transaction.toJson());
    if (_verifiedRequest == fingerprint &&
        _proof != null &&
        !_proof!.isExpired) {
      return _proof!;
    }
    final proof = await authorizeFundSecurity(context,
        request: transaction, api: api, isCurrent: isCurrent);
    if (!isCurrent()) throw const PasswordPaymentException('登录状态已变更，请重新打开页面');
    if (proof == null) throw const PasswordPaymentException('安全验证未完成，请重试');
    _verifiedRequest = fingerprint;
    return _proof = proof;
  }

  /// An accepted original order is recovered before SMS or another POST.
  Future<FundOrder?> recover(Map<String, dynamic> request) async {
    FundOrder order;
    try {
      order = await api.getOrderByClient(request['clientOrderID'] as String);
    } on FundApiException catch (error) {
      if (error.code == 20032 && !error.isUncertain) return null;
      rethrow;
    }
    if (!order.isTransfer ||
        order.status != 'done' ||
        order.recvID != request['recvID'] ||
        order.groupID != (request['groupID'] ?? '') ||
        order.scene.name !=
            (request['recipientType'] != null ? 'internal' : request['scene']) ||
        (order.recipientType.isNotEmpty &&
            order.recipientType != (request['recipientType'] ?? '')) ||
        (order.recipient.isNotEmpty &&
            order.recipient != (request['recipient'] ?? '')) ||
        (order.recipientAreaCode.isNotEmpty &&
            order.recipientAreaCode !=
                (request['areaCode'] ??
                    (request['recipientType'] == 'phone' ? '+86' : ''))) ||
        order.amount !=
            FundAmount.parse(request['amount'] as String,
                FundCurrency.parse(request['currency'] as String)) ||
        order.remark != (request['remark'] ?? '')) {
      throw const FundApiException(20062, '原订单参数不匹配');
    }
    invalidate();
    return order;
  }
}
