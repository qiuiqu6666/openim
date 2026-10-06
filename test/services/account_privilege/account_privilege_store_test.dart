import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/account_privilege/account_privilege_store.dart';
import 'package:openim_common/openim_common.dart';

const initial = AccountPrivilegeSession(
    userID: 'owner', chatToken: 'chat-token', baseUrl: 'https://chat.example');

void main() {
  test('unknown and missing flag stay closed; only strict true opens',
      () async {
    var raw = <String, dynamic>{'userID': 'owner'};
    final store = AccountPrivilegeStore(
        session: () => initial,
        fetchProfile: (_) async => UserFullInfo.fromJson(raw));
    addTearDown(store.dispose);
    expect(store.allows(userID: 'owner', baseUrl: initial.baseUrl), isFalse);
    for (final value in [null, false, 'true', 1, 0]) {
      raw = {'userID': 'owner', 'isPrivileged': value};
      expect(await store.refresh(), isFalse);
    }
    raw = {'userID': 'owner', 'isPrivileged': true};
    expect(await store.refresh(), isTrue);
    expect(store.allows(userID: 'other', baseUrl: initial.baseUrl), isFalse);
    expect(store.allows(userID: 'owner', baseUrl: 'https://other.example'),
        isFalse);
  });

  test('simultaneous foreground and page entry share one profile request',
      () async {
    final gate = Completer<UserFullInfo?>();
    var calls = 0;
    final store = AccountPrivilegeStore(
        session: () => initial,
        fetchProfile: (_) {
          calls++;
          return gate.future;
        });
    addTearDown(store.dispose);
    final one = store.refresh();
    final two = store.refresh();
    gate.complete(UserFullInfo(userID: 'owner', isPrivileged: true));
    expect(await one, isTrue);
    expect(await two, isTrue);
    expect(calls, 1);
  });

  test('failed refresh closes previously verified privilege', () async {
    var fail = false;
    final store = AccountPrivilegeStore(
        session: () => initial,
        fetchProfile: (_) async {
          if (fail) throw StateError('offline');
          return UserFullInfo(userID: 'owner', isPrivileged: true);
        });
    addTearDown(store.dispose);
    expect(await store.refresh(), isTrue);
    final grantedRevision = store.revision;
    fail = true;
    expect(await store.refresh(), isFalse);
    expect(store.allows(userID: 'owner', baseUrl: initial.baseUrl), isFalse);
    expect(store.revision, greaterThan(grantedRevision));
  });

  test('missing or mismatched own profile never grants privilege', () async {
    UserFullInfo? profile = UserFullInfo(userID: 'other', isPrivileged: true);
    final store = AccountPrivilegeStore(
        session: () => initial, fetchProfile: (_) async => profile);
    addTearDown(store.dispose);
    expect(await store.refresh(), isFalse);
    profile = null;
    expect(await store.refresh(), isFalse);
  });

  for (final dimension in ['account', 'token', 'server']) {
    test('late privileged response cannot cross $dimension change', () async {
      AccountPrivilegeSession? current = initial;
      final gate = Completer<UserFullInfo?>();
      final store = AccountPrivilegeStore(
          session: () => current, fetchProfile: (_) => gate.future);
      addTearDown(store.dispose);
      final result = store.refresh();
      current = AccountPrivilegeSession(
          userID: dimension == 'account' ? 'new-owner' : 'owner',
          chatToken: dimension == 'token' ? 'new-chat-token' : 'chat-token',
          baseUrl:
              dimension == 'server' ? 'https://new.example' : initial.baseUrl);
      gate.complete(UserFullInfo(userID: 'owner', isPrivileged: true));
      expect(await result, isFalse);
      expect(store.allows(userID: current.userID, baseUrl: current.baseUrl),
          isFalse);
    });
  }

  test('a late old response cannot overwrite a newer verified account',
      () async {
    AccountPrivilegeSession current = initial;
    final oldRead = Completer<UserFullInfo?>();
    final store = AccountPrivilegeStore(
        session: () => current,
        fetchProfile: (session) => session.userID == 'owner'
            ? oldRead.future
            : Future.value(
                UserFullInfo(userID: 'new-owner', isPrivileged: true)));
    addTearDown(store.dispose);
    final old = store.refresh();
    current = const AccountPrivilegeSession(
        userID: 'new-owner',
        chatToken: 'new-token',
        baseUrl: 'https://chat.example');
    expect(await store.refresh(), isTrue);
    oldRead.complete(UserFullInfo(userID: 'owner', isPrivileged: false));
    expect(await old, isFalse);
    expect(store.allows(userID: 'new-owner', baseUrl: current.baseUrl), isTrue);
  });

  test('logout discards pending grant and later reopen advances authorization',
      () async {
    final gate = Completer<UserFullInfo?>();
    var pending = true;
    final store = AccountPrivilegeStore(
        session: () => initial,
        fetchProfile: (_) => pending
            ? gate.future
            : Future.value(UserFullInfo(userID: 'owner', isPrivileged: true)));
    addTearDown(store.dispose);
    final old = store.refresh();
    store.reset();
    gate.complete(UserFullInfo(userID: 'owner', isPrivileged: true));
    expect(await old, isFalse);
    pending = false;
    expect(await store.refresh(), isTrue);
    final grantedRevision = store.revision;
    store.reset();
    expect(await store.refresh(), isTrue);
    expect(store.revision, greaterThan(grantedRevision));
  });

  test('dispose fences pending request without notifying a closed store',
      () async {
    final gate = Completer<UserFullInfo?>();
    final store = AccountPrivilegeStore(
        session: () => initial, fetchProfile: (_) => gate.future);
    final request = store.refresh();
    store.dispose();
    gate.complete(UserFullInfo(userID: 'owner', isPrivileged: true));
    expect(await request, isFalse);
  });
}
