import 'package:get/get.dart';

import '../../../services/fund_models.dart';
import 'fund_card_recipient.dart';

typedef FundCardOrderIdentity = ({
  String orderID,
  String biz,
  FundCurrency currency,
  FundAmount amount,
  String remark,
});

class FundCardState {
  const FundCardState(
      {required this.identity,
      required this.status,
      required this.claimedByMe,
      required this.confirmedAt,
      this.recipient = const FundCardRecipient(),
      this.packetCount,
      required this.revision});
  final int? packetCount;
  final FundCardRecipient recipient;
  final FundCardOrderIdentity identity;
  final String status;
  final bool claimedByMe;
  final DateTime confirmedAt;
  final int revision;
}

/// Process-local display snapshots, keyed by server, account and order.
/// No credentials, SDK message mutations or payment authority are stored.
class FundCardStateCache {
  FundCardStateCache({this.maxEntries = 200}) : assert(maxEntries > 0);
  static final shared = FundCardStateCache();
  final int maxEntries;
  final _entries = <String, FundCardState>{}.obs;
  int _epoch = 0;
  int _revision = 0;
  int get epoch => _epoch;
  FundCardState? read(String key) => _entries[key];

  void remember(String key,
      {required FundCardOrderIdentity identity,
      required String status,
      required bool claimedByMe,
      String recipientID = '',
      int? packetCount,
      required DateTime confirmedAt}) {
    final previous = _entries[key];
    final sameOrder = previous != null &&
        previous.identity.orderID == identity.orderID &&
        previous.identity.biz == identity.biz &&
        previous.identity.currency == identity.currency &&
        previous.identity.amount == identity.amount;
    _entries[key] = FundCardState(
        identity: identity,
        status: sameOrder && previous.status != 'open' && status == 'open'
            ? previous.status
            : status,
        claimedByMe: claimedByMe || (sameOrder && previous.claimedByMe),
        packetCount: packetCount != null && packetCount > 0
            ? packetCount
            : sameOrder
                ? previous.packetCount
                : null,
        recipient: sameOrder && previous.recipient.userID == recipientID
            ? previous.recipient
            : FundCardRecipient(userID: recipientID),
        confirmedAt: confirmedAt,
        revision: ++_revision);
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  void enrichRecipient(String key, FundCardRecipient recipient) {
    final state = _entries[key];
    if (state == null || state.recipient.userID != recipient.userID) return;
    _entries[key] = FundCardState(
        identity: state.identity,
        status: state.status,
        claimedByMe: state.claimedByMe,
        confirmedAt: state.confirmedAt,
        revision: state.revision,
        packetCount: state.packetCount,
        recipient: recipient);
  }

  void clear() {
    _epoch++;
    _entries.clear();
  }
}
