import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import '../../../fund/notifications/fund_claim_notice.dart';

/// Parse once per payload and find the first receipt once per timeline change.
class FundNoticeIndex {
  FundNoticeIndex(this.messages) {
    _worker = ever(messages, (_) {
      _dirty = true;
      _revision.value++;
    });
  }
  final RxList<Message> messages;
  late final Worker _worker;
  final _revision = 0.obs;
  final _first = <String, String?>{};
  bool _dirty = true;

  bool isFirst(Message message, FundClaimNotice notice) {
    _revision.value;
    if (_dirty) {
      _first.clear();
      for (final row in messages) {
        final parsed = FundClaimNotice.parse(row);
        if (parsed != null) {
          _first.putIfAbsent(parsed.key, () => row.clientMsgID);
        }
      }
      _dirty = false;
    }
    return !_first.containsKey(notice.key) ||
        _first[notice.key] == message.clientMsgID;
  }

  void close() {
    _worker.dispose();
    _first.clear();
  }
}
