import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/customer_service/data/data.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeApi api;
  late SharedPreferences prefs;
  late bool active;
  late CustomerServiceSessionStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    api = _FakeApi();
    active = true;
    store = CustomerServiceSessionStore(
        api: api,
        accountId: 'account-a',
        isActive: () => active,
        preferences: () async => prefs,
        identifierFactory: () => 'visitor-uuid');
  });
  tearDown(() {
    store.dispose();
    api.dispose();
  });

  test(
      'serializes simultaneous ensures and reuses persisted contact/conversation',
      () async {
    api.contactGate = Completer<CustomerServiceContact>();
    final first = store.ensure(name: 'Alice');
    final second = store.ensure(name: 'Alice');
    await Future<void>.delayed(Duration.zero);
    expect(api.contacts, 1);
    api.contactGate!.complete(const CustomerServiceContact(
        sourceId: 'contact-a', pubsubToken: 'token-a'));
    final sessions = await Future.wait([first, second]);
    expect(sessions[0], same(sessions[1]));
    expect(api.conversations, 1);
    final reopened = CustomerServiceSessionStore(
        api: api,
        accountId: 'account-a',
        isActive: () => active,
        preferences: () async => prefs);
    final session = await reopened.ensure(name: 'Alice new name');
    expect(session.sourceId, 'contact-a');
    expect(session.conversationId, 'conversation-1');
    expect(api.contacts, 1);
    expect(api.conversations, 1);
    expect(api.updatedName, 'Alice new name');
    reopened.dispose();
  });

  test('account, endpoint and inbox each isolate persisted sessions', () async {
    await store.ensure(name: 'Alice');
    final accountB = CustomerServiceSessionStore(
        api: api,
        accountId: 'account-b',
        isActive: () => true,
        preferences: () async => prefs);
    final otherEndpoint = CustomerServiceSessionStore(
        api: _FakeApi(
            config: const CustomerServiceConfig(
                baseUrl: 'https://other.example/kefu',
                inboxIdentifier: 'inbox')),
        accountId: 'account-a',
        isActive: () => true);
    final otherInbox = CustomerServiceSessionStore(
        api: _FakeApi(
            config: const CustomerServiceConfig(
                baseUrl: 'https://support.example/kefu',
                inboxIdentifier: 'other')),
        accountId: 'account-a',
        isActive: () => true);
    expect({
      store.storageKey,
      accountB.storageKey,
      otherEndpoint.storageKey,
      otherInbox.storageKey
    }, hasLength(4));
    final b = await accountB.ensure(name: 'Bob');
    expect(b.sourceId, 'contact-2');
    expect(prefs.getString(store.storageKey), contains('contact-1'));
    accountB.dispose();
    otherEndpoint.dispose();
    otherInbox.dispose();
    otherEndpoint.api.dispose();
    otherInbox.api.dispose();
  });

  test(
      'account generation invalidation blocks late contact persistence and chat',
      () async {
    api.contactGate = Completer<CustomerServiceContact>();
    final work = store.ensure(name: 'Alice');
    final assertion =
        expectLater(work, throwsA(isA<CustomerServiceSessionCancelled>()));
    await Future<void>.delayed(Duration.zero);
    active = false;
    api.contactGate!.complete(const CustomerServiceContact(
        sourceId: 'stale-contact', pubsubToken: 'stale-token'));
    await assertion;
    expect(api.conversations, 0);
    final saved = jsonDecode(prefs.getString(store.storageKey)!) as Map;
    expect(saved['sourceId'], isEmpty);
    expect(saved['pubsubToken'], isEmpty);
  });

  test('conversation failure retries with the already persisted real contact',
      () async {
    api.failConversation = true;
    await expectLater(store.ensure(name: 'Alice'), throwsStateError);
    api.failConversation = false;
    final session = await store.ensure(name: 'Alice');
    expect(session.sourceId, 'contact-1');
    expect(api.contacts, 1);
    expect(api.conversations, 2);
  });

  test('history failure leaves cached session and credentials intact',
      () async {
    final session = await store.ensure(name: 'Alice');
    final saved = prefs.getString(store.storageKey);
    await expectLater(
        api.listMessages(
            contactId: session.sourceId,
            conversationId: session.conversationId),
        throwsStateError);
    expect(await store.ensure(name: 'Alice'), same(session));
    expect(prefs.getString(store.storageKey), saved);
    expect(api.contacts, 1);
    expect(api.conversations, 1);
  });

  test('disposed store prevents new work even for a previously ready session',
      () async {
    await store.ensure(name: 'Alice');
    store.dispose();
    await expectLater(store.ensure(name: 'Alice'),
        throwsA(isA<CustomerServiceSessionCancelled>()));
  });
}

class _FakeApi extends CustomerServiceApi {
  _FakeApi(
      {super.config = const CustomerServiceConfig(
          baseUrl: 'https://support.example/kefu', inboxIdentifier: 'inbox')});
  int contacts = 0, conversations = 0;
  bool failConversation = false;
  String updatedName = '';
  Completer<CustomerServiceContact>? contactGate;

  @override
  Future<CustomerServiceContact> createContact(
      {required String identifier,
      required String name,
      String avatarUrl = ''}) async {
    contacts++;
    return contactGate == null
        ? CustomerServiceContact(
            sourceId: 'contact-$contacts', pubsubToken: 'token-$contacts')
        : await contactGate!.future;
  }

  @override
  Future<void> updateContact(
      {required String sourceId,
      required String name,
      String avatarUrl = ''}) async {
    updatedName = name;
  }

  @override
  Future<String> createConversation(String sourceId) async {
    conversations++;
    if (failConversation) throw StateError('temporary backend failure');
    return 'conversation-$conversations';
  }

  @override
  Future<List<CustomerServiceMessage>> listMessages(
          {required String contactId, required String conversationId}) async =>
      throw StateError('history failed');
}
