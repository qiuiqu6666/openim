import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/fund/confirmed_fund_cards.dart';
import 'package:openim_common/openim_common.dart';

import 'chat_fund_controller_test.dart' as fixtures;

void main() {
  for (final biz in ['packet_normal', 'transfer', 'packet_exclusive']) {
    for (final sdkFirst in [false, true]) {
      test('one card for $biz, SDK first=$sdkFirst', () {
        final messages = <Message>[].obs;
        final cards =
            ConfirmedFundCards(messages: messages, currentUserID: () => 'me');
        addTearDown(cards.close);
        final message = fixtures.fundMessage(biz: biz, amount: '1.00')
          ..sendID = 'me';
        final data = FundMessageData.tryParse(message.customElem!.data)!;
        final order = fixtures.order(biz: biz, amount: '1');
        if (sdkFirst) messages.add(message);
        expect(cards.add(order, data), isTrue);
        expect(cards.cards.length + messages.length, 1);
        expect(cards.add(order, data), isFalse);
        if (!sdkFirst) messages.add(message);
        expect(cards.cards, isEmpty);
        expect(messages.single, same(message));
        // Removing/paging away from the SDK row must not resurrect a local card.
        messages.clear();
        expect(cards.add(order, data), isFalse);
        expect(cards.cards, isEmpty);
      });
    }
  }

  test('unrelated SDK rows cannot replace a paid card', () {
    final messages = <Message>[].obs;
    final cards =
        ConfirmedFundCards(messages: messages, currentUserID: () => 'me');
    addTearDown(cards.close);
    final data =
        FundMessageData.tryParse(fixtures.fundMessage().customElem!.data)!;
    cards.add(fixtures.order(), data);
    messages.add(fixtures.fundMessage()..sendID = 'someone-else');
    messages.add(fixtures.fundMessage(amount: '2')..sendID = 'me');
    expect(cards.cards, hasLength(1));
    cards.close();
    expect(cards.cards, isEmpty);
  });
}
