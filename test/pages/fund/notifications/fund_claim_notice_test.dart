import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/fund/notifications/fund_claim_notice.dart';

void main() {
  Message receipt({String envelopeSender = 'receiver'}) => Message(
        contentType: MessageType.custom,
        sendID: envelopeSender,
        senderNickname: '小林',
        customElem: CustomElem(
            data: jsonEncode({
          'businessID': 'fund_packet_claim_notice',
          'orderID': 'packet',
          'claimerID': 'receiver',
          'senderID': 'owner',
        })),
      );

  test('sender sees recipient claim tip; claimant sees own tip', () {
    final message = receipt();
    final notice = FundClaimNotice.parse(message)!;
    expect(notice.text(message, 'owner'), '小林领取了你的红包');
    expect(notice.text(message, 'receiver'), '你领取了红包');
    expect(notice.key, FundClaimNotice.parse(receipt())!.key);
  });

  test('does not trust a forged claimant inside custom JSON', () {
    expect(FundClaimNotice.parse(receipt(envelopeSender: 'other')), isNull);
    expect(
        FundClaimNotice.parse(Message(contentType: MessageType.text)), isNull);
  });
}
