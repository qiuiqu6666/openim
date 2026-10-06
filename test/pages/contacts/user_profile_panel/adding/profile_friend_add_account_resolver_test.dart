import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/contacts/search/contact_search_source.dart';
import 'package:openim/pages/contacts/user_profile_panel/adding/profile_friend_add_account_resolver.dart';
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

class _Fixture {
  _Fixture() {
    resolver = ProfileFriendAddAccountResolver(
      source: search,
      owner: () => owner,
      sdkOwner: () => sdkOwner,
      token: () => token,
      server: () => server,
    );
  }

  final search = _Search();
  late final ProfileFriendAddAccountResolver resolver;
  String? owner = 'app_owner';
  String? sdkOwner = 'im_owner';
  String? token = 'chat_token';
  String server = 'https://chat.example/prefix';

  void change(String dimension) {
    switch (dimension) {
      case 'owner':
        owner = 'other_app_owner';
      case 'sdkOwner':
        sdkOwner = 'other_im_owner';
      case 'token':
        token = 'other_chat_token';
      case 'server':
        server = 'https://other.example/prefix';
    }
  }
}

Matcher _unavailable(ProfileFriendAddUnavailableReason reason) =>
    isA<ProfileFriendAddUnavailable>()
        .having((error) => error.reason, 'reason', reason);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final candidate in [
    '@abcdefgh12',
    'abcdefgh12',
    ' @abcdefgh12 ',
  ]) {
    test('$candidate searches public account and preserves returned account',
        () async {
      final fixture = _Fixture();
      final pending = fixture.resolver
          .resolve(userID: 'im_original_target', account: candidate);
      expect(fixture.search.requests, [('@abcdefgh12', 1)]);
      fixture.search.replies.single.complete([
        UserFullInfo(userID: 'other', account: '@otheracct1'),
        UserFullInfo(userID: 'im_original_target', account: ' @abcdefgh12 '),
      ]);
      expect(await pending, '@abcdefgh12');
      expect(fixture.resolver.isCurrentSession, isTrue);
      fixture.resolver.close();
    });
  }

  test('numeric public account is prefixed for account search', () async {
    final fixture = _Fixture();
    final pending =
        fixture.resolver.resolve(userID: 'im_target', account: '0012345678');
    expect(fixture.search.requests, [('@0012345678', 1)]);
    fixture.search.replies.single
        .complete([UserFullInfo(userID: 'im_target', account: '0012345678')]);
    expect(await pending, '0012345678');
    fixture.resolver.close();
  });

  for (final candidate in [
    '',
    ' ',
    'im_original_target',
    'Alice',
    '@ABCDEFGHIJ',
    '@tooshort',
    'alice@example.com',
    '+886912345678',
  ]) {
    test('unavailable account $candidate never searches another identifier',
        () async {
      final fixture = _Fixture();
      await expectLater(
          fixture.resolver
              .resolve(userID: 'im_original_target', account: candidate),
          throwsA(
              _unavailable(ProfileFriendAddUnavailableReason.missingAccount)));
      expect(fixture.search.requests, isEmpty);
      fixture.resolver.close();
    });
  }

  test('missing target does not search or infer a userID from account',
      () async {
    final fixture = _Fixture();
    await expectLater(
        fixture.resolver.resolve(userID: ' ', account: '@abcdefgh12'),
        throwsA(
            _unavailable(ProfileFriendAddUnavailableReason.targetUnavailable)));
    expect(fixture.search.requests, isEmpty);
    fixture.resolver.close();
  });

  for (final response in <List<UserFullInfo>?>[
    null,
    [],
    [UserFullInfo(userID: 'different_im_target', account: '@abcdefgh12')],
    [UserFullInfo(userID: 'im_original_target', account: '@otheracct1')],
    [UserFullInfo(userID: 'im_original_target')],
    [UserFullInfo(userID: 'im_original_target', account: 'im_original_target')],
    [UserFullInfo(account: '@abcdefgh12', nickname: 'im_original_target')],
    [UserFullInfo(userID: '@abcdefgh12', account: '@abcdefgh12')],
  ]) {
    test('mismatched or missing search target is unavailable: $response',
        () async {
      final fixture = _Fixture();
      final pending = fixture.resolver
          .resolve(userID: 'im_original_target', account: '@abcdefgh12');
      final rejection = expectLater(
          pending,
          throwsA(_unavailable(
              ProfileFriendAddUnavailableReason.targetUnavailable)));
      fixture.search.replies.single.complete(response);
      await rejection;
      fixture.resolver.close();
    });
  }

  test('current search failure preserves the original error', () async {
    final fixture = _Fixture();
    final error = PlatformException(code: 'network');
    final pending =
        fixture.resolver.resolve(userID: 'im_target', account: '@abcdefgh12');
    final rejection = expectLater(pending, throwsA(same(error)));
    fixture.search.replies.single.completeError(error);
    await rejection;
    fixture.resolver.close();
  });

  test('a current search error permits retry within the bound session',
      () async {
    final fixture = _Fixture();
    final old =
        fixture.resolver.resolve(userID: 'im_target', account: '@abcdefgh12');
    final rejection = expectLater(old, throwsA(isA<TimeoutException>()));
    fixture.search.replies[0].completeError(TimeoutException('try again'));
    await rejection;
    final current =
        fixture.resolver.resolve(userID: 'im_target', account: '@abcdefgh12');
    fixture.search.replies[1]
        .complete([UserFullInfo(userID: 'im_target', account: '@abcdefgh12')]);
    expect(await current, '@abcdefgh12');
    fixture.resolver.close();
  });

  for (final dimension in ['owner', 'sdkOwner', 'token', 'server']) {
    test('$dimension changes permanently invalidate the initial session',
        () async {
      final fixture = _Fixture();
      fixture.change(dimension);
      expect(fixture.resolver.isCurrentSession, isFalse);
      fixture.owner = 'app_owner';
      fixture.sdkOwner = 'im_owner';
      fixture.token = 'chat_token';
      fixture.server = 'https://chat.example/prefix';
      expect(fixture.resolver.isCurrentSession, isFalse);
      expect(
          await fixture.resolver
              .resolve(userID: 'im_target', account: '@abcdefgh12'),
          isNull);
      expect(fixture.search.requests, isEmpty);
      fixture.resolver.close();
    });

    for (final fails in [false, true]) {
      test('$dimension change ignores late ${fails ? 'error' : 'success'}',
          () async {
        final fixture = _Fixture();
        final pending = fixture.resolver
            .resolve(userID: 'im_target', account: '@abcdefgh12');
        fixture.change(dimension);
        if (fails) {
          fixture.search.replies.single
              .completeError(PlatformException(code: '1506'));
        } else {
          fixture.search.replies.single.complete(
              [UserFullInfo(userID: 'im_target', account: '@abcdefgh12')]);
        }
        expect(await pending, isNull);
        expect(fixture.resolver.isCurrentSession, isFalse);
        fixture.resolver.close();
      });
    }
  }

  for (final fails in [false, true]) {
    test('new resolve replaces an old ${fails ? 'failure' : 'success'}',
        () async {
      final fixture = _Fixture();
      final old =
          fixture.resolver.resolve(userID: 'im_old', account: '@abcdefgh12');
      final current = fixture.resolver
          .resolve(userID: 'im_current', account: '@otheracct1');
      fixture.search.replies[1].complete(
          [UserFullInfo(userID: 'im_current', account: ' otheracct1 ')]);
      expect(await current, 'otheracct1');
      if (fails) {
        fixture.search.replies[0].completeError(StateError('old failure'));
      } else {
        fixture.search.replies[0]
            .complete([UserFullInfo(userID: 'im_old', account: '@abcdefgh12')]);
      }
      expect(await old, isNull);
      fixture.resolver.close();
    });
  }

  for (final fails in [false, true]) {
    test('close rejects late ${fails ? 'error' : 'success'} and further reads',
        () async {
      final fixture = _Fixture();
      final pending =
          fixture.resolver.resolve(userID: 'im_target', account: '@abcdefgh12');
      fixture.resolver.close();
      if (fails) {
        fixture.search.replies.single.completeError(StateError('old failure'));
      } else {
        fixture.search.replies.single.complete(
            [UserFullInfo(userID: 'im_target', account: '@abcdefgh12')]);
      }
      expect(await pending, isNull);
      expect(fixture.resolver.isCurrentSession, isFalse);
      expect(
          await fixture.resolver
              .resolve(userID: 'im_target', account: '@abcdefgh12'),
          isNull);
      expect(fixture.search.requests, hasLength(1));
    });
  }
}
