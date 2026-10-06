import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/chat_message_sender.dart';
import '../../../services/favorite_send_coordinator.dart';
import '../../../services/fund_models.dart';

/// Informational IM receipt. Never used as proof of a financial state.
class FundClaimNotice {
  const FundClaimNotice(this.orderID, this.claimerID, this.senderID);

  final String orderID;
  final String claimerID;
  final String senderID;
  String get key => jsonEncode([orderID, claimerID]);

  static FundClaimNotice? parse(Message message) {
    if (message.contentType != MessageType.custom) return null;
    try {
      final data = jsonDecode(message.customElem?.data ?? '');
      if (data is! Map || data['businessID'] != 'fund_packet_claim_notice') {
        return null;
      }
      final order = data['orderID'];
      final claimer = data['claimerID'];
      final sender = data['senderID'];
      if (order is! String ||
          order.trim().isEmpty ||
          claimer is! String ||
          claimer.isEmpty ||
          sender is! String ||
          claimer != message.sendID) {
        return null;
      }
      return FundClaimNotice(order, claimer, sender);
    } catch (_) {
      return null;
    }
  }

  String text(Message message, String viewerID) {
    final name = message.senderNickname?.trim();
    final who = claimerID == viewerID
        ? '你'
        : (name?.isNotEmpty == true ? name! : claimerID);
    return senderID == viewerID ? '$who领取了你的红包' : '$who领取了红包';
  }
}

/// Called only after a successful claim response, never after a details GET.
class FundClaimNoticeSender {
  static final shared = FundClaimNoticeSender();
  final _attempted = <String>{};

  Future<void> send(FundOrder order, String claimerID,
      {String messageSenderID = ''}) async {
    try {
      final scope = jsonEncode([Config.appAuthUrl, claimerID, order.orderID]);
      if (!order.requiresClaim ||
          order.groupID.isEmpty ||
          claimerID.isEmpty ||
          OpenIM.iMManager.userID != claimerID ||
          DataSp.userID != claimerID ||
          !_attempted.add(scope)) {
        return;
      }
      final server = Config.appAuthUrl;
      final message = await OpenIM.iMManager.messageManager.createCustomMessage(
        data: jsonEncode({
          'businessID': 'fund_packet_claim_notice',
          'orderID': order.orderID,
          'claimerID': claimerID,
          'senderID':
              order.senderID.isNotEmpty ? order.senderID : messageSenderID,
        }),
        extension: '',
        description: '领取了红包',
      );
      if (OpenIM.iMManager.userID != claimerID ||
          DataSp.userID != claimerID ||
          Config.appAuthUrl != server) {
        return;
      }
      await ChatMessageSender().sendRaw(
          message, FavoriteTarget(conversationID: '', groupID: order.groupID));
    } catch (_) {
      // A notice failure must not turn a completed claim into a failed claim.
      // Do not resend blindly: transport failure can mean receipt ambiguity.
    }
  }
}
