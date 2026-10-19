import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/fund_models.dart';

class ConfirmedFundCard {
  const ConfirmedFundCard(this.order, this.data, this.anchorMessageID);
  final FundOrder order;
  final FundMessageData data;
  final String? anchorMessageID;
  String get id => 'confirmed-fund:${order.orderID}';
}

/// Presentation of paid orders only. SDK messages retain all persistence,
/// delivery, selection and receipt ownership.
class ConfirmedFundCards {
  ConfirmedFundCards({this.messages, required this.currentUserID}) {
    if (messages != null) _worker = ever(messages!, (_) => _reconcile());
  }

  final RxList<Message>? messages;
  final String Function() currentUserID;
  final cards = <String, ConfirmedFundCard>{}.obs;
  final _accepted = <String>{};
  Worker? _worker;

  bool _hasMessage(ConfirmedFundCard card) =>
      messages?.any((message) {
        if (message.sendID != currentUserID() ||
            message.contentType != MessageType.custom) {
          return false;
        }
        final data = FundMessageData.tryParse(message.customElem?.data);
        return data != null &&
            data.orderID == card.data.orderID &&
            data.biz == card.data.biz &&
            data.currency == card.data.currency &&
            _sameAmount(data.amount, card.order);
      }) ==
      true;

  bool _sameAmount(String amount, FundOrder order) {
    try {
      return FundAmount.parse(amount, order.currency) == order.amount;
    } on FormatException {
      return false;
    }
  }

  bool add(FundOrder order, FundMessageData data) {
    if (!_accepted.add(order.orderID)) return false;
    final card =
        ConfirmedFundCard(order, data, messages?.firstOrNull?.clientMsgID);
    if (!_hasMessage(card)) cards[order.orderID] = card;
    return true;
  }

  void _reconcile() {
    for (final card in cards.values.toList()) {
      if (_hasMessage(card)) cards.remove(card.order.orderID);
    }
  }

  void close() {
    _worker?.dispose();
    cards.clear();
    _accepted.clear();
  }
}
