import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/fund_api.dart';
import '../../fund/fund_detail_page.dart';
import '../../fund/fund_send_page.dart';
import 'fund_card_state_cache.dart';
import 'fund_card_recipient.dart';

typedef ChatFundSendPageOpener = Future<FundOrder?> Function({
  required bool isRedPacket,
  String? userID,
  String? groupID,
  String? recipientName,
  String? recipientFaceURL,
});

typedef _FundOrderIdentity = FundCardOrderIdentity;

/// Owns one chat route's fund-card display overrides and navigation work.
/// Fund creation, claiming and payment remain owned by the fund pages/API.
class ChatFundController {
  ChatFundController({
    required this.isClosed,
    required this.canSend,
    required this.userID,
    required this.groupID,
    required this.recipientName,
    required this.recipientFaceURL,
    required this.closeToolbox,
    String Function()? currentUserID,
    String? Function()? certificateID,
    String Function()? serverURL,
    Future<FundOrder> Function(String)? getOrder,
    ChatFundSendPageOpener? openSend,
    ChatFundSendPageOpener? openExclusiveSend,
    Future<FundOrder?> Function(FundMessageData)? openDetail,
    DateTime Function()? now,
    FundCardStateCache? stateCache,
    Future<FundCardRecipient> Function(String, String)? resolveRecipient,
  })  : _currentUserID = currentUserID ?? (() => OpenIM.iMManager.userID),
        _certificateID = certificateID ?? (() => DataSp.userID),
        _serverURL = serverURL ?? (() => Config.appAuthUrl),
        _getOrder = getOrder ?? FundApi().getOrder,
        _openSend = openSend ?? _openSendPage,
        _openExclusiveSend = openExclusiveSend ?? _openExclusiveSendPage,
        _openDetail = openDetail ?? _openDetailPage,
        _usesDefaultDetail = openDetail == null,
        _now = now ?? DateTime.now,
        _resolveRecipient = resolveRecipient ?? FundCardRecipient.resolve,
        _stateCache = stateCache ?? FundCardStateCache.shared {
    _stateEpoch = _stateCache.epoch;
  }

  final bool Function() isClosed;
  final bool Function() canSend;
  final String? Function() userID;
  final String? Function() groupID;
  final String? Function() recipientName;
  final String? Function() recipientFaceURL;
  final VoidCallback closeToolbox;
  final String Function() _currentUserID;
  final String? Function() _certificateID;
  final String Function() _serverURL;
  final Future<FundOrder> Function(String) _getOrder;
  final ChatFundSendPageOpener _openSend;
  final ChatFundSendPageOpener _openExclusiveSend;
  final Future<FundOrder?> Function(FundMessageData) _openDetail;
  final bool _usesDefaultDetail;
  final DateTime Function() _now;
  final Future<FundCardRecipient> Function(String, String) _resolveRecipient;
  final _profileRequests = <String>{};

  FundCardRecipient cardRecipient(FundMessageData message) =>
      _verifiedState(message)?.recipient ?? const FundCardRecipient();
  int? packetCount(FundMessageData message) =>
      message.isPacket ? _verifiedState(message)?.packetCount : null;

  final FundCardStateCache _stateCache;
  late final int _stateEpoch;
  final _generations = <String, int>{};
  final _visibleMessages = <String, Message>{};
  final _refreshTimes = <String, DateTime>{};
  final _requests = <String>{};
  final _confirmedHere = <String, int>{};
  bool _openingPage = false;
  bool _disposed = false;
  static const _statusLifetime = Duration(seconds: 60);

  bool get _closed => _disposed || isClosed();

  FundMessageData? messageData(Message message) {
    if (message.contentType != MessageType.custom) return null;
    final data = FundMessageData.tryParse(message.customElem?.data);
    if (data == null) return null;
    final verified = _verifiedState(data);
    return verified != null
        ? data.copyWith(
            status: verified.status, remark: verified.identity.remark)
        : data;
  }

  bool claimedByMe(FundMessageData message) {
    return _verifiedState(message)?.claimedByMe ?? false;
  }

  bool statusResolved(FundMessageData message) {
    final state = _verifiedState(message);
    if (state == null) return message.status != 'open';
    // A prior unclaimed observation can change on another phone. Reconfirm
    // it in this route; completed/claimed results can render immediately.
    return state.status != 'open' ||
        state.claimedByMe ||
        _confirmedHere[_cacheKey(message.orderID)] == state.revision;
  }

  FundCardState? _verifiedState(FundMessageData message) {
    final state = _stateCache.read(_cacheKey(message.orderID));
    if (_stateEpoch != _stateCache.epoch ||
        _closed ||
        _currentUserID().isEmpty ||
        _certificateID() != _currentUserID()) {
      return null;
    }
    return state != null && _matchesIdentity(message, state.identity)
        ? state
        : null;
  }

  _FundOrderIdentity _identityOf(FundOrder order) => (
        orderID: order.orderID,
        biz: order.biz,
        currency: order.currency,
        amount: order.amount,
        // Display metadata is authoritative, but is not part of identity.
        remark: FundMessageData.normalizeRemark(order.remark),
      );

  bool _matchesOrder(FundMessageData message, FundOrder order) =>
      _matchesIdentity(message, _identityOf(order));

  bool _matchesIdentity(FundMessageData message, _FundOrderIdentity order) {
    try {
      return message.orderID == order.orderID &&
          message.biz == order.biz &&
          message.currency == order.currency.code &&
          FundAmount.parse(message.amount, order.currency) == order.amount;
    } on FormatException {
      return false;
    }
  }

  bool isFundMessage(Message message) =>
      message.contentType == MessageType.custom &&
      FundMessageData.tryParse(message.customElem?.data) != null;

  String _cacheKey(String orderID, {String? ownerID, String? serverURL}) =>
      jsonEncode([
        serverURL ?? _serverURL(),
        ownerID ?? _currentUserID(),
        orderID,
      ]);

  void setVisible(Message message, bool visible) {
    if (_closed) return;
    final data = FundMessageData.tryParse(message.customElem?.data);
    if (message.contentType != MessageType.custom || data == null) return;
    final key = message.clientMsgID ?? data.orderID;
    if (visible) {
      _visibleMessages[key] = message;
      unawaited(_refresh(message));
    } else {
      _visibleMessages.remove(key);
    }
  }

  void _applyOrder(FundMessageData message, FundOrder order,
      {required String ownerID,
      required String? certificateID,
      required String serverURL,
      int? expectedGeneration,
      int? expectedRevision}) {
    final cacheKey =
        _cacheKey(message.orderID, ownerID: ownerID, serverURL: serverURL);
    if (_closed ||
        _stateEpoch != _stateCache.epoch ||
        serverURL != _serverURL() ||
        ownerID.isEmpty ||
        certificateID != ownerID ||
        ownerID != _currentUserID() ||
        certificateID != _certificateID() ||
        (expectedGeneration != null &&
            expectedGeneration != (_generations[cacheKey] ?? 0)) ||
        (expectedRevision != null &&
            expectedRevision != (_stateCache.read(cacheKey)?.revision ?? 0)) ||
        !_matchesOrder(message, order)) {
      return;
    }
    // The server order is a display override, never an IM-record rewrite.
    _generations[cacheKey] = (_generations[cacheKey] ?? 0) + 1;
    _stateCache.remember(cacheKey,
        identity: _identityOf(order),
        status: order.status,
        claimedByMe: order.shares.any((share) => share.claimerID == ownerID),
        recipientID: order.recvID,
        packetCount: !order.isPacket
            ? null
            : order.requiresClaim
                ? (order.shareCount > 0 ? order.shareCount : null)
                : (order.recvID.isNotEmpty ? 1 : null),
        confirmedAt: _now());
    _confirmedHere[cacheKey] = _stateCache.read(cacheKey)!.revision;
    _refreshTimes[cacheKey] = _now();
    if ((order.biz == 'packet_exclusive' || order.biz == 'group_transfer') &&
        order.recvID.isNotEmpty &&
        _stateCache.read(cacheKey)!.recipient.name.isEmpty &&
        _profileRequests.add(cacheKey)) {
      unawaited(_enrichRecipient(cacheKey, order, ownerID, serverURL));
    }
  }

  Future<void> _enrichRecipient(
      String key, FundOrder order, String ownerID, String serverURL) async {
    try {
      final recipient = await _resolveRecipient(order.recvID, order.groupID);
      if (!_closed &&
          _stateEpoch == _stateCache.epoch &&
          ownerID == _currentUserID() &&
          ownerID == _certificateID() &&
          serverURL == _serverURL() &&
          recipient.userID == order.recvID) {
        _stateCache.enrichRecipient(key, recipient);
      }
    } catch (_) {
      // Missing profiles leave a neutral recipient label, never a fake person.
    } finally {
      _profileRequests.remove(key);
    }
  }

  Future<void> _refresh(Message message, {bool force = false}) async {
    final data = FundMessageData.tryParse(message.customElem?.data);
    if (_closed || data == null || _stateEpoch != _stateCache.epoch) return;
    final ownerID = _currentUserID();
    final certificateID = _certificateID();
    final serverURL = _serverURL();
    if (ownerID.isEmpty || certificateID != ownerID) return;
    final cacheKey =
        _cacheKey(data.orderID, ownerID: ownerID, serverURL: serverURL);
    if (_requests.contains(cacheKey)) return;
    final cached = _verifiedState(data);
    final refreshedAt = _refreshTimes[cacheKey] ??
        (cached != null && (cached.status != 'open' || cached.claimedByMe)
            ? cached.confirmedAt
            : null);
    if (!force &&
        refreshedAt != null &&
        _now().difference(refreshedAt) < _statusLifetime) {
      return;
    }
    _requests.add(cacheKey);
    final generation = _generations[cacheKey] ?? 0;
    final revision = _stateCache.read(cacheKey)?.revision ?? 0;
    _refreshTimes[cacheKey] = _now();
    try {
      _applyOrder(data, await _getOrder(data.orderID),
          ownerID: ownerID,
          certificateID: certificateID,
          serverURL: serverURL,
          expectedGeneration: generation,
          expectedRevision: revision);
    } catch (_) {
      // Visibility refreshes remain quiet. Fund detail owns loading/retry UI.
    } finally {
      _requests.remove(cacheKey);
    }
  }

  Future<void> openSend({required bool isRedPacket}) =>
      _openSendEntry(isRedPacket: isRedPacket);

  /// Opens the existing payment form for this member; payment still requires
  /// the user's amount review and password confirmation in the fund page.
  Future<void> sendExclusiveRedPacket(GroupMembersInfo member) async {
    final targetID = member.userID?.trim() ?? '';
    final chatGroupID = groupID();
    final memberGroupID = member.groupID?.trim() ?? '';
    final ownerID = _currentUserID();
    if (targetID.isEmpty ||
        targetID == ownerID ||
        ownerID.isEmpty ||
        _certificateID() != ownerID ||
        chatGroupID == null ||
        chatGroupID.trim().isEmpty ||
        (memberGroupID.isNotEmpty && memberGroupID != chatGroupID)) {
      return;
    }
    await _openSendEntry(isRedPacket: true, exclusiveRecipient: member);
  }

  Future<void> _openSendEntry({
    required bool isRedPacket,
    GroupMembersInfo? exclusiveRecipient,
  }) async {
    if (_closed || _openingPage || !canSend()) return;
    final ownerID = _currentUserID();
    final certificateID = _certificateID();
    final serverURL = _serverURL();
    final chatUserID = userID();
    final targetUserID = exclusiveRecipient?.userID?.trim() ?? chatUserID;
    final selectedName = exclusiveRecipient?.nickname?.trim();
    final targetGroupID = groupID();
    final isGroup = targetGroupID?.isNotEmpty == true;
    _openingPage = true;
    closeToolbox();
    try {
      final openPage =
          exclusiveRecipient == null ? _openSend : _openExclusiveSend;
      final order = await openPage(
        isRedPacket: isRedPacket,
        userID: targetUserID,
        groupID: targetGroupID,
        recipientName: exclusiveRecipient == null
            ? recipientName()
            : selectedName?.isNotEmpty == true
                ? selectedName
                : targetUserID,
        recipientFaceURL: exclusiveRecipient == null
            ? recipientFaceURL()
            : exclusiveRecipient.faceURL,
      );
      if (order == null ||
          _closed ||
          chatUserID != userID() ||
          targetGroupID != groupID() ||
          order.isPacket != isRedPacket ||
          order.scene != (isGroup ? FundScene.group : FundScene.single) ||
          (!isGroup &&
              (order.biz == 'group_transfer' || order.biz == 'packet_lucky')) ||
          (order.senderID.isNotEmpty && order.senderID != ownerID) ||
          order.recvID == ownerID ||
          (exclusiveRecipient != null &&
              (order.biz != FundPacketBiz.exclusive.code ||
                  order.recvID != targetUserID ||
                  order.groupID != targetGroupID)) ||
          (isGroup
              ? order.groupID.isNotEmpty && order.groupID != targetGroupID
              : targetUserID == null ||
                  targetUserID.isEmpty ||
                  order.groupID.isNotEmpty ||
                  (order.recvID.isNotEmpty && order.recvID != targetUserID))) {
        return;
      }
      // The API-confirmed order can arrive before its server-created IM card.
      // Cache its verified identity; do not create or rewrite an IM message.
      final reference = FundMessageData.tryParse(jsonEncode({
        'orderID': order.orderID,
        'biz': order.biz,
        'currency': order.currency.code,
        'amount': order.amount.decimal,
        'status': order.status,
        'remark': order.remark,
      }));
      if (reference != null) {
        _applyOrder(reference, order,
            ownerID: ownerID,
            certificateID: certificateID,
            serverURL: serverURL);
      }
    } finally {
      _openingPage = false;
    }
  }

  Future<void> openDetail(FundMessageData message,
      {Message? sourceMessage}) async {
    if (_closed ||
        _openingPage ||
        (_usesDefaultDetail && Get.context == null)) {
      return;
    }
    _openingPage = true;
    closeToolbox();
    final ownerID = _currentUserID();
    final certificateID = _certificateID();
    final serverURL = _serverURL();
    try {
      final order = _usesDefaultDetail
          ? await _openDetailPage(message,
              messageSender: _detailMessageSender(message, sourceMessage))
          : await _openDetail(message);
      if (order != null) {
        _applyOrder(message, order,
            ownerID: ownerID,
            certificateID: certificateID,
            serverURL: serverURL);
      }
    } finally {
      _openingPage = false;
    }
  }

  FundDetailMessageSender? _detailMessageSender(
      FundMessageData message, Message? source) {
    if (source?.contentType != MessageType.custom) return null;
    final senderID = source?.sendID?.trim() ?? '';
    if (senderID.isEmpty) return null;
    final data = FundMessageData.tryParse(source?.customElem?.data);
    if (data == null) return null;
    try {
      final currency = FundCurrency.parse(data.currency);
      if (!_matchesIdentity(message, (
        orderID: data.orderID,
        biz: data.biz,
        currency: currency,
        amount: FundAmount.parse(data.amount, currency),
        remark: data.remark,
      ))) {
        return null;
      }
    } on FormatException {
      return null;
    }
    // Read only SDK envelope metadata, never identity fields inside custom
    // JSON. This context is for display, not an authoritative financial party.
    return FundDetailMessageSender(
      userID: senderID,
      nickname: source?.senderNickname ?? '',
      faceURL: source?.senderFaceUrl ?? '',
    );
  }

  /// Foreground refreshes apply only to cards still tracked as visible.
  void refreshVisible() {
    if (_closed) return;
    for (final message in _visibleMessages.values.toList()) {
      unawaited(_refresh(message, force: true));
    }
  }

  void close() {
    _disposed = true;
    _visibleMessages.clear();
    _refreshTimes.clear();
    _generations.clear();
    _requests.clear();
    _confirmedHere.clear();
  }

  static Future<FundOrder?> _openSendPage({
    required bool isRedPacket,
    String? userID,
    String? groupID,
    String? recipientName,
    String? recipientFaceURL,
    FundPacketBiz? initialPacketBiz,
  }) async {
    return Get.to<FundOrder>(() => FundSendPage(
          isRedPacket: isRedPacket,
          userID: userID,
          groupID: groupID,
          recipientName: recipientName,
          recipientFaceURL: recipientFaceURL,
          initialPacketBiz: initialPacketBiz,
        ));
  }

  static Future<FundOrder?> _openExclusiveSendPage({
    required bool isRedPacket,
    String? userID,
    String? groupID,
    String? recipientName,
    String? recipientFaceURL,
  }) =>
      _openSendPage(
        isRedPacket: isRedPacket,
        userID: userID,
        groupID: groupID,
        recipientName: recipientName,
        recipientFaceURL: recipientFaceURL,
        initialPacketBiz: FundPacketBiz.exclusive,
      );

  static Future<FundOrder?> _openDetailPage(FundMessageData message,
      {FundDetailMessageSender? messageSender}) async {
    final context = Get.context;
    if (context == null) return null;
    return Navigator.of(context)
        .push(FundDetailRoute(message: message, messageSender: messageSender));
  }
}
