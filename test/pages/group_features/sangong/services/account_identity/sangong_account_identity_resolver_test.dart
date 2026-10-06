import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/contacts/search/contact_search_source.dart';
import 'package:openim/pages/group_features/sangong/services/account_identity/sangong_account_identity_resolver.dart';
import 'package:openim_common/openim_common.dart';

class _Search extends ContactSearchSource {
  final requests = <(String, int)>[];
  final replies = <Completer<List<UserFullInfo>?>>[];

  @override
  Future<List<UserFullInfo>?> users(String keyword, int page, {int? way}) {
    requests.add((keyword, page));
    final reply = Completer<List<UserFullInfo>?>();
    replies.add(reply);
    return reply.future;
  }
}

void main() {
  for (final account in ['@abcdefgh12', 'abcdefgh12', ' @abcdefgh12 ']) {
    test('resolves $account to the returned IM ID', () async {
      final source = _Search();
      final resolver =
          SangongAccountIdentityResolver(isCurrent: () => true, source: source);
      addTearDown(resolver.close);
      final pending = resolver.resolve(account);
      expect(source.requests, [('@abcdefgh12', 1)]);
      source.replies.single.complete([
        UserFullInfo(userID: 'im_wrong', account: '@otheracct1'),
        UserFullInfo(userID: 'im_target', account: 'abcdefgh12'),
      ]);
      expect(await pending, 'im_target');
    });
  }

  test('numeric public account uses account search rather than phone search',
      () async {
    final source = _Search();
    final resolver =
        SangongAccountIdentityResolver(isCurrent: () => true, source: source);
    addTearDown(resolver.close);
    final pending = resolver.resolve('0012345678');
    expect(source.requests, [('@0012345678', 1)]);
    source.replies.single.complete([
      UserFullInfo(userID: 'im_numeric_account', account: '0012345678'),
    ]);
    expect(await pending, 'im_numeric_account');
  });

  test('saved internal bot ID remains unchanged, including account-shaped ID',
      () async {
    final source = _Search();
    final resolver =
        SangongAccountIdentityResolver(isCurrent: () => true, source: source);
    addTearDown(resolver.close);
    expect(await resolver.resolve('abcdefgh12', knownUserId: 'abcdefgh12'),
        'abcdefgh12');
    expect(await resolver.resolve('im_existing_bot'), 'im_existing_bot');
    expect(source.requests, isEmpty);
  });

  for (final response in <List<UserFullInfo>?>[
    null,
    [],
    [UserFullInfo(account: 'abcdefgh12')],
    [UserFullInfo(userID: ' ', account: 'abcdefgh12')],
    [UserFullInfo(userID: 'im_other', account: 'otheracct1')],
    [UserFullInfo(userID: 'im_missing_account')],
    [
      UserFullInfo(userID: 'im_one', account: 'abcdefgh12'),
      UserFullInfo(userID: 'im_two', account: 'abcdefgh12'),
    ],
  ]) {
    test(
        'missing or ambiguous identity never becomes an inferred ID: $response',
        () async {
      final source = _Search();
      final resolver =
          SangongAccountIdentityResolver(isCurrent: () => true, source: source);
      addTearDown(resolver.close);
      final pending = resolver.resolve('@abcdefgh12');
      final expectation = expectLater(pending, throwsStateError);
      source.replies.single.complete(response);
      await expectation;
    });
  }

  for (final value in ['', '@short', '@ABCDEFGHIJ', 'some account']) {
    test('rejects malformed public input $value before searching', () async {
      final source = _Search();
      final resolver =
          SangongAccountIdentityResolver(isCurrent: () => true, source: source);
      addTearDown(resolver.close);
      await expectLater(resolver.resolve(value, allowInternalUserId: false),
          throwsStateError);
      expect(source.requests, isEmpty);
    });
  }

  for (final fails in [false, true]) {
    test('stale session suppresses late ${fails ? 'failure' : 'success'}',
        () async {
      var current = true;
      final source = _Search();
      final resolver = SangongAccountIdentityResolver(
          isCurrent: () => current, source: source);
      addTearDown(resolver.close);
      final pending = resolver.resolve('@abcdefgh12');
      current = false;
      if (fails) {
        source.replies.single.completeError(StateError('old error'));
      } else {
        source.replies.single.complete([
          UserFullInfo(userID: 'im_old', account: 'abcdefgh12'),
        ]);
      }
      expect(await pending, isNull);
      expect(await resolver.resolve('im_internal'), isNull);
      expect(source.requests, hasLength(1));
    });
  }

  test('superseded lookup cannot replace the latest account identity',
      () async {
    final source = _Search();
    final resolver =
        SangongAccountIdentityResolver(isCurrent: () => true, source: source);
    addTearDown(resolver.close);
    final old = resolver.resolve('@abcdefgh12');
    final latest = resolver.resolve('@otheracct1');
    source.replies[1].complete([
      UserFullInfo(userID: 'im_latest', account: 'otheracct1'),
    ]);
    source.replies[0].complete([
      UserFullInfo(userID: 'im_old', account: 'abcdefgh12'),
    ]);
    expect(await latest, 'im_latest');
    expect(await old, isNull);
  });

  test('same permissions with a changed scope discard the old account lookup',
      () async {
    var tenant = 'tenant-A';
    final source = _Search();
    final resolver = SangongAccountIdentityResolver(
        isCurrent: () => true,
        scopeToken: () => ('owner', 'group', tenant),
        source: source);
    addTearDown(resolver.close);
    final old = resolver.resolve('@abcdefgh12');
    tenant = 'tenant-B';
    source.replies.single.complete([
      UserFullInfo(userID: 'im_old_tenant', account: 'abcdefgh12'),
    ]);
    expect(await old, isNull);
  });
}
