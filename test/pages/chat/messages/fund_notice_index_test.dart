import 'dart:convert';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/messages/presentation/fund_notice_index.dart';
import 'package:openim/pages/fund/notifications/fund_claim_notice.dart';

class _Rows extends RxList<Message> {
  int scans = 0;
  @override
  Iterator<Message> get iterator => _walk().iterator;
  Iterable<Message> _walk() sync* {
    for (var i = 0; i < length; i++) {
      scans++;
      yield this[i];
    }
  }
}

void main() {
  test('duplicate notices share one scan; deletion promotes next receipt', () {
    final rows = _Rows();
    rows.addAll(List.generate(
        600,
        (i) => Message(
            clientMsgID: '$i',
            sendID: 'peer',
            contentType: MessageType.custom,
            customElem: CustomElem(
                data: jsonEncode({
              'businessID': 'fund_packet_claim_notice',
              'orderID': 'packet',
              'claimerID': 'peer',
              'senderID': 'owner'
            })))));
    final index = FundNoticeIndex(rows);
    addTearDown(index.close);
    for (var i = 0; i < 600; i++) {
      expect(index.isFirst(rows[i], FundClaimNotice.parse(rows[i])!), i == 0);
    }
    expect(rows.scans, 600);
    rows.removeAt(0);
    expect(
        index.isFirst(rows.first, FundClaimNotice.parse(rows.first)!), isTrue);
    expect(rows.scans, lessThanOrEqualTo(1200));
  });
}
