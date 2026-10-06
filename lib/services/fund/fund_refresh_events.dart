import 'dart:async';
import 'dart:collection';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import 'fund_deposit_notice.dart';

/// Account-scoped invalidation signals. Consumers reload authoritative data.
abstract final class FundRefreshEvents {
  static final _balances = StreamController<String>.broadcast();
  static final _records = StreamController<String>.broadcast();
  static final _seen = <String, LinkedHashSet<String>>{};

  static String accountKey(String serverURL, String accountID) =>
      '${serverURL.replaceFirst(RegExp(r'/+$'), '')}:$accountID';

  static String get currentAccountKey =>
      accountKey(Config.appAuthUrl, DataSp.userID ?? '');

  static Stream<String> get balanceChanges => _balances.stream;
  static Stream<String> get recordChanges => _records.stream;

  static bool _valid(String key) => key.isNotEmpty && !key.endsWith(':');

  static void notifyBalance({String? accountKey}) {
    final key = accountKey ?? currentAccountKey;
    if (_valid(key)) _balances.add(key);
  }

  static void notifyRecord({String? accountKey}) {
    final key = accountKey ?? currentAccountKey;
    if (_valid(key)) _records.add(key);
  }

  static bool _remember(String account, String id) {
    final entries = _seen.putIfAbsent(account, LinkedHashSet.new);
    if (!entries.add(id)) return false;
    if (entries.length > 512) entries.remove(entries.first);
    if (_seen.length > 4) _seen.remove(_seen.keys.first);
    return true;
  }

  /// Observes live SDK arrivals without changing the SDK message/history.
  static bool observeMessage(Message message,
      {String? accountKey, String? accountID}) {
    final key = accountKey ?? currentAccountKey;
    final receiver = accountID ?? DataSp.userID ?? '';
    if (!_valid(key) || receiver.isEmpty) return false;
    final deposit = fundDepositNoticeID(message, receiverID: receiver);
    String? eventID;
    if (deposit != null) {
      eventID = 'deposit:$deposit';
    } else if (message.contentType == MessageType.custom) {
      final order = FundMessageData.tryParse(message.customElem?.data);
      if (order == null) return false;
      if (message.sessionType == ConversationType.single &&
          message.recvID != null &&
          message.recvID!.isNotEmpty &&
          message.recvID != receiver &&
          message.sendID != receiver) {
        return false;
      }
      eventID = 'order:${order.orderID}:${order.status}';
    }
    if (eventID == null || !_remember(key, eventID)) return false;
    notifyBalance(accountKey: key);
    notifyRecord(accountKey: key);
    return true;
  }

  /// Clears session-local notice identities; no account amounts are cached.
  static void resetNoticeIdentities() => _seen.clear();
}
