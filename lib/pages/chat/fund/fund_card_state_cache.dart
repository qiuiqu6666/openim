import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

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

/// Process-local order state and optional persisted recipient display snapshots,
/// keyed by server, account and order.
/// No credentials, SDK message mutations or payment authority are stored.
class FundCardStateCache {
  FundCardStateCache({this.maxEntries = 200, this.persistRecipients = false})
      : assert(maxEntries > 0);
  static final shared = FundCardStateCache(persistRecipients: true);
  final bool persistRecipients;
  static const _recipientStorageKey = 'fund_card_recipients_v1';
  Map<String, dynamic>? _recipientSnapshots;

  Map<String, dynamic> get _snapshots {
    if (_recipientSnapshots == null) {
      try {
        _recipientSnapshots = persistRecipients
            ? Map<String, dynamic>.from(
                SpUtil().getObject(_recipientStorageKey) ?? {})
            : {};
      } catch (_) {
        _recipientSnapshots = {};
      }
    }
    return _recipientSnapshots!;
  }

  // Display metadata only: never restore payment/claim status from disk.
  FundCardRecipient? savedRecipient(
      String key, FundCardOrderIdentity identity) {
    final value = _snapshots[key];
    if (value is! Map ||
        value['biz'] != identity.biz ||
        value['currency'] != identity.currency.code ||
        value['amount'] != identity.amount.decimal ||
        value['orderID'] != identity.orderID ||
        value['userID'] is! String ||
        value['name'] is! String ||
        value['faceURL'] is! String) {
      return null;
    }
    return FundCardRecipient(
        userID: value['userID'],
        name: value['name'],
        faceURL: value['faceURL']);
  }

  void _saveRecipient(
      String key, FundCardState state, FundCardRecipient recipient) {
    if (recipient.name.isEmpty && recipient.faceURL.isEmpty) return;
    _snapshots.remove(key);
    _snapshots[key] = {
      'orderID': state.identity.orderID,
      'biz': state.identity.biz,
      'currency': state.identity.currency.code,
      'amount': state.identity.amount.decimal,
      'userID': recipient.userID,
      'name': recipient.name,
      'faceURL': recipient.faceURL,
    };
    while (_snapshots.length > maxEntries) {
      _snapshots.remove(_snapshots.keys.first);
    }
    if (persistRecipients) {
      SpUtil()
          .putObject(_recipientStorageKey, _snapshots)
          ?.catchError((_) => false);
    }
  }

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
    final saved = savedRecipient(key, identity);
    if (_snapshots.containsKey(key) &&
        (saved == null || saved.userID != recipientID)) {
      _snapshots.remove(key);
      if (persistRecipients) {
        SpUtil()
            .putObject(_recipientStorageKey, _snapshots)
            ?.catchError((_) => false);
      }
    }
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
    _saveRecipient(key, state, recipient);
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
    _recipientSnapshots = {};
    if (persistRecipients) {
      SpUtil().remove(_recipientStorageKey)?.catchError((_) => false);
    }
  }
}
