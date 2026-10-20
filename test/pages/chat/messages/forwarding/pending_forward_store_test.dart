import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/messages/forwarding/pending_forward.dart';
import 'package:openim/pages/chat/messages/forwarding/pending_forward_store.dart';

import 'support/chat_forwarding_fixture.dart';

void main() {
  test('reopening restores the forward only in its destination conversation',
      () async {
    final store = PendingForwardStore();
    final first = store.conversation(
        accountID: 'self', sessionToken: 'login', conversationID: 'chat-a');
    final draft = PendingForward(
        [forwardingSource('one')], UserInfo(userID: 'peer'),
        merged: false);
    first.draft.value = draft;
    expect(
        store
            .conversation(
                accountID: 'self',
                sessionToken: 'login',
                conversationID: 'chat-b')
            .draft
            .value,
        isNull);
    final reopened = store.conversation(
        accountID: 'self', sessionToken: 'login', conversationID: 'chat-a');
    expect(reopened.draft.value, same(draft));
    reopened.cancel();
    expect(first.draft.value, isNull);
    first.draft.value = draft;
    expect(await reopened.send((_) async => true), isTrue);
    expect(first.draft.value, isNull);
  });

  test('logout and account or login changes discard retained forwards', () {
    final store = PendingForwardStore();
    final first = store.conversation(
        accountID: 'self', sessionToken: 'login', conversationID: 'chat');
    first.draft.value = PendingForward(
        [forwardingSource('one')], UserInfo(userID: 'peer'),
        merged: false);
    final other = store.conversation(
        accountID: 'other', sessionToken: 'login', conversationID: 'chat');
    expect(first.draft.value, isNull);
    expect(other.draft.value, isNull);
    other.draft.value = PendingForward(
        [forwardingSource('two')], UserInfo(userID: 'peer'),
        merged: false);
    store.conversation(
        accountID: 'other', sessionToken: 'new-login', conversationID: 'chat');
    expect(other.draft.value, isNull);
    store.clear();
    expect(
        store
            .conversation(
                accountID: 'other',
                sessionToken: 'new-login',
                conversationID: 'chat')
            .draft
            .value,
        isNull);
  });
}
