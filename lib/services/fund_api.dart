import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:get/get.dart' hide Response;
import 'package:openim_common/openim_common.dart';
import 'package:uuid/uuid.dart';

import 'fund_models.dart';

export 'fund_models.dart';

class FundApiException implements Exception {
  const FundApiException(this.code, this.message,
      {this.isUncertain = false, this.orderID});
  final int code;
  final String message;

  /// A write may have committed; retry only with its original clientOrderID.
  final bool isUncertain;

  /// A real service ID returned with an incomplete wallet write response.
  /// Recovery can query this ID; it never authorizes resubmitting the write.
  final String? orderID;

  @override
  String toString() => 'FundApiException($code, $message)';
}

/// Chat-service fund requests. OpenIM money cards are sent by the backend.
class FundApi {
  FundApi({
    Dio? client,
    String? baseUrl,
    String? Function()? tokenProvider,
  })  : _client = client,
        _baseUrl = baseUrl,
        _tokenProvider = tokenProvider;

  final Dio? _client;
  final String? _baseUrl;
  final String? Function()? _tokenProvider;

  static String createClientOrderID() => const Uuid().v4();

  /// Shared authenticated transport for fund modules with their own DTOs.
  Future<Map<String, dynamic>> requestData(
    String path, {
    String method = 'POST',
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
    bool mutation = false,
  }) =>
      _request(path,
          method: method,
          data: data,
          queryParameters: queryParameters,
          mutation: mutation,
          walletContract: true);

  Future<List<FundBalance>> fetchBalances() async {
    final data = await _request('/chat/fund/balances', method: 'GET');
    final values = data['balances'];
    if (values is! List) throw const FormatException('Invalid fund balances');
    final balances = values.map((value) {
      if (value is! Map) throw const FormatException('Invalid fund balance');
      return FundBalance.fromJson(Map<String, dynamic>.from(value));
    }).toList();
    // The contract always returns all three currencies. Never invent a balance.
    if (balances.length != FundCurrency.values.length ||
        balances.map((balance) => balance.currency).toSet().length !=
            FundCurrency.values.length) {
      throw const FormatException('Incomplete fund balances');
    }
    return List.unmodifiable(balances);
  }

  Future<FundOrder> getOrder(String orderID) async {
    _requiredID(orderID, 'orderID');
    final data = await _request(
      '/chat/fund/orders/${Uri.encodeComponent(orderID)}',
      method: 'GET',
    );
    final order = _parseOrder(data);
    if (order.orderID != orderID) {
      throw const FormatException('Fund order ID does not match');
    }
    return order;
  }

  Future<FundOrder> getOrderByClient(String clientOrderID) async {
    _requiredID(clientOrderID, 'clientOrderID');
    final data = await _request('/chat/fund/orders/by-client',
        method: 'GET', queryParameters: {'clientOrderID': clientOrderID});
    final order = _parseOrder(data);
    if (order.clientOrderID != clientOrderID) {
      throw const FormatException('Fund client order ID does not match');
    }
    return order;
  }

  Future<FundOrder> sendTransfer({
    required String clientOrderID,
    required FundScene scene,
    required FundAmount amount,
    required String recvID,
    String? groupID,
    required String payPassword,
    String? remark,
    String? recipientType,
    String? recipient,
    String? areaCode,
    String? verifyChallengeID,
    String? verifyCode,
  }) async {
    _validateWrite(clientOrderID, payPassword);
    _validateAmount(amount);
    _validateScene(scene, groupID);
    _requiredID(recvID, 'recvID');
    final hasRecipient = recipientType != null || recipient != null;
    if (hasRecipient &&
        (!const {'account', 'email', 'phone'}.contains(recipientType) ||
            recipient == null ||
            recipient.trim().isEmpty ||
            scene == FundScene.group)) {
      throw const FormatException('请检查收款人账号');
    }
    if (areaCode != null && recipientType != 'phone') {
      throw const FormatException('只有手机号方式可提交区号');
    }
    if ((verifyChallengeID == null) != (verifyCode == null) ||
        (verifyChallengeID != null &&
            (verifyChallengeID.trim().isEmpty ||
                !RegExp(r'^\d{6}$').hasMatch(verifyCode!)))) {
      throw const FormatException('请输入本次交易的六位短信验证码');
    }
    return _createOrder('/chat/fund/transfers', {
      'clientOrderID': clientOrderID,
      'scene': scene.name,
      'currency': amount.currency.code,
      'amount': amount.decimal,
      'recvID': recvID,
      if (scene == FundScene.group) 'groupID': groupID!,
      'payPassword': payPassword,
      if (remark != null) 'remark': FundRemark.normalize(remark),
      if (recipientType != null) 'recipientType': recipientType,
      if (recipient != null) 'recipient': recipient,
      if (areaCode != null) 'areaCode': areaCode,
      if (verifyChallengeID != null) 'verifyChallengeID': verifyChallengeID,
      if (verifyCode != null) 'verifyCode': verifyCode,
    });
  }

  Future<FundOrder> sendPacket({
    required String clientOrderID,
    required FundScene scene,
    required FundPacketBiz biz,
    required FundCurrency currency,
    FundAmount? amount,
    FundAmount? shareAmount,
    int? shareCount,
    String? recvID,
    String? groupID,
    required String payPassword,
    String? remark,
  }) async {
    _validateWrite(clientOrderID, payPassword);
    if (scene == FundScene.internal) {
      throw const FormatException('红包不支持内部提现场景');
    }
    _validateScene(scene, groupID);
    final groupNormal = scene == FundScene.group && biz == FundPacketBiz.normal;
    final groupLucky = scene == FundScene.group && biz == FundPacketBiz.lucky;
    if (biz == FundPacketBiz.lucky && scene != FundScene.group) {
      throw const FormatException('拼手气红包只能发到群聊');
    }
    if (groupNormal || groupLucky) {
      if (shareCount == null || shareCount <= 0) {
        throw const FormatException('请输入有效红包个数');
      }
      if (recvID != null && recvID.isNotEmpty) {
        throw const FormatException('普通群红包和拼手气红包不能指定收款人');
      }
    } else {
      _requiredID(recvID ?? '', 'recvID');
      if (shareCount != null || shareAmount != null) {
        throw const FormatException('直接到账红包不支持红包份数');
      }
    }
    final sendAmount = groupNormal ? shareAmount : amount;
    if (sendAmount == null || sendAmount.currency != currency) {
      throw const FormatException('请输入正确币种的红包金额');
    }
    _validateAmount(sendAmount);
    if (groupNormal) {
      _validateAmount(sendAmount.multipliedBy(shareCount!));
    }
    if (groupNormal && amount != null) {
      throw const FormatException('普通群红包应填写每份金额');
    }
    if (!groupNormal && shareAmount != null) {
      throw const FormatException('该红包应填写总金额');
    }
    if (groupLucky && sendAmount.units < BigInt.from(shareCount!)) {
      throw const FormatException('红包总金额不足以分配给所有份数');
    }
    return _createOrder('/chat/fund/packets', {
      'clientOrderID': clientOrderID,
      'scene': scene.name,
      'biz': biz.code,
      'currency': currency.code,
      if (groupNormal) 'shareAmount': sendAmount.decimal,
      if (!groupNormal) 'amount': sendAmount.decimal,
      if (groupNormal || groupLucky) 'shareCount': shareCount!,
      if (!groupNormal && !groupLucky) 'recvID': recvID!,
      if (scene == FundScene.group) 'groupID': groupID!,
      'payPassword': payPassword,
      if (remark != null) 'remark': FundRemark.normalize(remark),
    });
  }

  Future<FundClaimResult> claimPacket(String orderID) async {
    _requiredID(orderID, 'orderID');
    final data = await _request(
      '/chat/fund/packets/${Uri.encodeComponent(orderID)}/claim',
      mutation: true,
    );
    final amount = data['amount'];
    final responseID = data['orderID'] ?? data['order_id'] ?? orderID;
    if (amount is! String ||
        !RegExp(r'^\d+(?:\.\d{1,6})?$').hasMatch(amount) ||
        !FundAmount.parse(amount, FundCurrency.usdt).isPositive ||
        responseID != orderID) {
      throw const FundApiException(-1, 'Invalid fund claim response',
          isUncertain: true);
    }
    return FundClaimResult(amount: amount, orderID: orderID);
  }

  Future<FundOrder> _createOrder(String path, Map<String, dynamic> body) async {
    final Map<String, dynamic> data;
    try {
      data = await _request(path, data: body, mutation: true);
    } on FundApiException catch (error) {
      // A conflict or service failure cannot disprove an accepted original
      // transfer. Keep its ID and recover before authorizing another write.
      if (path == '/chat/fund/transfers' &&
          const {20062, 500, 503}.contains(error.code) &&
          !error.isUncertain) {
        throw FundApiException(error.code, error.message,
            isUncertain: true, orderID: error.orderID);
      }
      rethrow;
    }
    try {
      final nested = data['order'];
      final orderData =
          nested is Map ? Map<String, dynamic>.from(nested) : data;
      final orderID = orderData['orderID'] ?? orderData['order_id'];
      if (orderID is! String || orderID.trim().isEmpty) {
        throw const FormatException('Missing fund order ID');
      }
      // Some writes only acknowledge the ID. Fetch the authoritative full order.
      final order = orderData['amount'] is String &&
              orderData['currency'] is String &&
              orderData['status'] is String &&
              orderData['biz'] is String
          ? _parseOrder(data)
          : await getOrder(orderID);
      if (order.clientOrderID.isNotEmpty &&
          order.clientOrderID != body['clientOrderID']) {
        throw const FormatException('Fund client order ID does not match');
      }
      final currency = FundCurrency.parse(body['currency'] as String);
      final expectedAmount = body['shareAmount'] is String
          ? FundAmount.parse(body['shareAmount'] as String, currency)
              .multipliedBy(body['shareCount'] as int)
          : FundAmount.parse(body['amount'] as String, currency);
      final expectedBiz = body['biz'] as String?;
      if (order.currency != currency ||
          order.amount != expectedAmount ||
          order.scene.name !=
              (body['recipientType'] != null ? 'internal' : body['scene']) ||
          (expectedBiz != null && order.biz != expectedBiz) ||
          (expectedBiz == null && !order.isTransfer) ||
          (order.recipientType.isNotEmpty &&
              order.recipientType != (body['recipientType'] ?? '')) ||
          (order.recipient.isNotEmpty &&
              order.recipient != (body['recipient'] ?? '')) ||
          (order.recipientAreaCode.isNotEmpty &&
              order.recipientAreaCode !=
                  (body['areaCode'] ??
                      (body['recipientType'] == 'phone' ? '+86' : ''))) ||
          (order.recvID.isNotEmpty && order.recvID != body['recvID']) ||
          (order.groupID.isNotEmpty && order.groupID != body['groupID'])) {
        throw const FormatException('Fund order does not match the request');
      }
      return order;
    } catch (_) {
      // The write already succeeded, including when its follow-up GET failed.
      throw const FundApiException(-1, 'Fund order confirmation unavailable',
          isUncertain: true);
    }
  }

  FundOrder _parseOrder(Map<String, dynamic> data) {
    final nested = data['order'];
    if (nested != null && nested is! Map) {
      throw const FormatException('Invalid fund order');
    }
    final orderData = nested is Map
        ? Map<String, dynamic>.from(nested)
        : Map<String, dynamic>.from(data);
    // The GET response can place shares alongside the order.
    if (nested != null && data.containsKey('shares')) {
      orderData['shares'] = data['shares'];
    }
    return FundOrder.fromJson(orderData);
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'POST',
    Map<String, dynamic>? data,
    Map<String, dynamic>? queryParameters,
    bool mutation = false,
    bool walletContract = false,
  }) async {
    final token = _tokenProvider != null ? _tokenProvider() : DataSp.chatToken;
    if (token == null || token.isEmpty) {
      throw const FundApiException(-2, 'Chat login required');
    }
    final baseUrl =
        (_baseUrl ?? Config.appAuthUrl).replaceFirst(RegExp(r'/+$'), '');
    Response<dynamic> response;
    try {
      response = await (_client ?? dio).request<dynamic>(
        '$baseUrl$path',
        data: data,
        queryParameters: queryParameters,
        options: Options(
          method: method,
          headers: {
            'token': token,
            'operationID': const Uuid().v4(),
          },
          contentType: data == null ? null : Headers.jsonContentType,
        ),
      );
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      if (walletContract && status == 401) {
        throw const FundApiException(401, '登录状态已失效，请重新登录');
      }
      if (walletContract && status == 503) {
        throw FundApiException(500, '资金服务暂时不可用', isUncertain: mutation);
      }
      // Avoid exposing raw requests containing a payment password in errors.
      throw FundApiException(-1, 'Fund request unavailable',
          isUncertain: mutation);
    }
    if (walletContract && response.statusCode == 401) {
      throw const FundApiException(401, '登录状态已失效，请重新登录');
    }
    if (walletContract && response.statusCode == 503) {
      throw FundApiException(500, '资金服务暂时不可用', isUncertain: mutation);
    }
    final body = response.data;
    if (body is! Map || body['errCode'] is! int) {
      throw FundApiException(-1, 'Invalid fund response',
          isUncertain: mutation);
    }
    final code = body['errCode'] as int;
    if (code != 0) {
      if (walletContract) {
        // Wallet diagnostics can contain request details, including passwords.
        throw FundApiException(code, '资金请求失败');
      }
      throw FundApiException(
          code,
          body['errMsg'] is String
              ? body['errMsg'] as String
              : 'Fund request failed');
    }
    final responseData = body['data'];
    if (responseData is! Map) {
      throw FundApiException(-1, 'Invalid fund response data',
          isUncertain: mutation);
    }
    return Map<String, dynamic>.from(responseData);
  }

  void _validateWrite(String clientOrderID, String payPassword) {
    _requiredID(clientOrderID, 'clientOrderID');
    if (!RegExp(r'^\d{6}$').hasMatch(payPassword)) {
      throw const FormatException('支付密码须为 6 位数字');
    }
    if (utf8.encode(clientOrderID).length > 128) {
      throw const FormatException('业务单号最多 128 字节');
    }
  }

  void _validateAmount(FundAmount amount) {
    if (!amount.isPositive) throw const FormatException('金额必须大于 0');
    if (amount.units > BigInt.parse('9223372036854775807')) {
      throw const FormatException('金额超出支持范围');
    }
  }

  void _validateScene(FundScene scene, String? groupID) {
    if (scene == FundScene.group) _requiredID(groupID ?? '', 'groupID');
    if (scene != FundScene.group && groupID != null && groupID.isNotEmpty) {
      throw const FormatException('单聊不能包含群 ID');
    }
  }

  void _requiredID(String value, String name) {
    if (value.trim().isEmpty || value.trim() != value) {
      throw FormatException('Missing or invalid $name');
    }
  }
}

String fundErrorMessage(Object error, {bool? chinese}) {
  final zh = chinese ?? (Get.locale ?? Get.deviceLocale)?.languageCode != 'en';
  if (error is FormatException) {
    return zh ? error.message : 'Please check the amount and recipient.';
  }
  if (error is FundApiException) {
    if (error.isUncertain) {
      return zh
          ? '结果尚未确认，请保留当前页面并重试确认，请勿重复发起付款'
          : 'The result is not confirmed. Keep this page and retry confirmation; do not create another payment.';
    }
    final messages = <int, (String, String)>{
      -2: ('登录状态已失效，请重新登录', 'Please sign in again.'),
      1001: ('提交参数无效，请检查金额、收款人和备注', 'Check the amount, recipient and remark.'),
      20026: ('可用余额不足', 'Insufficient available balance.'),
      20027: ('金额超出单笔或每日限额', 'The transaction or daily limit was exceeded.'),
      20028: ('红包已领完、过期或退回', 'This packet is empty, expired or refunded.'),
      20029: (
        '当前用户或收款人不在该群中',
        'You or the recipient are no longer in the group.'
      ),
      20030: ('资金服务暂时不可用', 'The fund service is temporarily unavailable.'),
      20031: ('该业务不支持此币种', 'This currency is not supported.'),
      20032: ('订单不存在或无权查看', 'The order is unavailable.'),
      20033: ('你已经领取过这个红包', 'You already claimed this packet.'),
      20034: ('请先设置支付密码', 'Set a payment password first.'),
      20035: ('支付密码不正确', 'Incorrect payment password.'),
      20036: (
        '支付密码已锁定，请 15 分钟后重试',
        'Payment password locked. Try again in 15 minutes.'
      ),
      20037: ('请通过手机短信修改支付密码', 'Reset your payment password by SMS.'),
      20038: ('请先绑定手机号', 'Bind a phone number first.'),
      20062: (
        '原业务单号参数冲突，请查询并核对原订单',
        'Review the original order before retrying.'
      ),
      20076: (
        '手机号或密码修改后需等待24小时，请查看允许转出时间',
        'Wait 24 hours after a phone or password change.'
      ),
      20077: (
        '本次交易需要短信验证',
        'SMS verification is required for this transaction.'
      ),
      20078: (
        '本笔短信验证已失效或不匹配，请重新获取验证码',
        'Request a new verification code for this transaction.'
      ),
      20079: ('当前登录缺少设备信息，请重新登录后再试', 'Sign in again to confirm this device.'),
      20080: ('验证码发送过于频繁，请稍后再试', 'Wait before requesting another code.'),
    };
    final message = messages[error.code];
    if (message != null) return zh ? message.$1 : message.$2;
  }
  return zh ? '资金请求失败，请稍后重试' : 'The fund request failed. Please try again.';
}
