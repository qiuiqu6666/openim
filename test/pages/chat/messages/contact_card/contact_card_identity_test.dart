import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/utils/http_util.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('contact card identity protocol', () {
    test('public account is nested and bound to the unchanged SDK target', () {
      final identity = contactCardIdentityFields('im_target', ' @abcdefgh12 ');
      expect(identity, {
        'contactCard': {'userID': 'im_target', 'account': '@abcdefgh12'},
      });
      final extension = jsonEncode({...identity, 'inviteCode': 'fi_card'});
      expect(contactCardAccount('im_target', extension), '@abcdefgh12');
      expect(contactCardAccount('target', extension), isNull);
      expect(contactCardAccount('im_other', extension), isNull);
      expect(friendCardInviteCode(extension), 'fi_card');
      expect(contactCardIdentityFields('im_target', '0012345678'), {
        'contactCard': {'userID': 'im_target', 'account': '0012345678'},
      });
    });

    test('missing target or empty account never creates a display snapshot',
        () {
      expect(contactCardIdentityFields('', '@abcdefgh12'), isEmpty);
      expect(contactCardIdentityFields('   ', '@abcdefgh12'), isEmpty);
      expect(contactCardIdentityFields('im_target', null), isEmpty);
      expect(contactCardIdentityFields('im_target', ''), isEmpty);
      expect(contactCardIdentityFields('im_target', '   '), isEmpty);
      expect(
          contactCardAccount(
              '',
              jsonEncode({
                'contactCard': {'userID': '', 'account': '@abcdefgh12'},
              })),
          isNull);
    });

    test('malformed or unbound extension fields cannot impersonate an account',
        () {
      final extensions = <String?>[
        null,
        '',
        '{',
        'null',
        'true',
        '17',
        '[]',
        jsonEncode({'account': '@abcdefgh12'}),
        jsonEncode({
          'profile': {'userID': 'im_target', 'account': '@abcdefgh12'}
        }),
        jsonEncode({'contactCard': '@abcdefgh12'}),
        jsonEncode({'contactCard': []}),
        jsonEncode({'contactCard': null}),
        jsonEncode({
          'contactCard': {'account': '@abcdefgh12'}
        }),
        jsonEncode({
          'contactCard': {'userID': 'im_other', 'account': '@abcdefgh12'}
        }),
        jsonEncode({
          'contactCard': {'userID': 12, 'account': '@abcdefgh12'}
        }),
        jsonEncode({
          'contactCard': {'userID': 'im_target', 'account': 1234567890}
        }),
        jsonEncode({
          'contactCard': {'userID': 'im_target', 'account': null}
        }),
        jsonEncode({
          'contactCard': {'userID': 'im_target', 'account': '   '}
        }),
      ];
      for (final extension in extensions) {
        expect(contactCardAccount('im_target', extension), isNull,
            reason: 'Invalid extension: $extension');
      }
    });

    test('legacy fallback accepts only original ASCII numeric IDs', () {
      expect(legacyCardAccount('2138014845'), '2138014845');
      expect(legacyCardAccount('0012345678'), '0012345678');
      for (final target in [
        '',
        'im_2138014845',
        '@abcdefgh12',
        '2138014845 ',
        ' 2138014845',
        '-123',
        '+123',
        '12.3',
        '１２３'
      ]) {
        expect(legacyCardAccount(target), isNull, reason: target);
      }
    });

    test('card invite extension preserves its grant source and bound account',
        () async {
      SharedPreferences.setMockInitialValues({});
      await SpUtil().init();
      await DataSp.putLoginCertificate(LoginCertificate.fromJson({
        'userID': 'owner-a',
        'chatToken': 'chat-a',
        'imToken': 'im-a',
      }));
      final previous = http.dio;
      final requests = <RequestOptions>[];
      final client = Dio();
      client.interceptors
          .add(InterceptorsWrapper(onRequest: (request, handler) {
        requests.add(request);
        handler.resolve(Response(
          requestOptions: request,
          statusCode: 200,
          data: {
            'errCode': 0,
            'data': {'inviteCode': 'fi_card', 'expireAt': 9999999999999}
          },
        ));
      }));
      http.dio = client;
      try {
        final extension = await createFriendCardExtension('im_target',
            account: '@abcdefgh12');
        expect(requests, hasLength(1));
        expect(requests.single.path, endsWith('/chat/friend-invites'));
        expect(requests.single.headers['token'], 'chat-a');
        expect(requests.single.data,
            {'source': 'card', 'targetUserID': 'im_target'});
        expect(jsonDecode(extension), {
          'inviteCode': 'fi_card',
          'contactCard': {'userID': 'im_target', 'account': '@abcdefgh12'},
        });
        expect(friendCardInviteCode(extension), 'fi_card');
        expect(contactCardAccount('im_target', extension), '@abcdefgh12');
      } finally {
        http.dio = previous;
        client.close();
      }
    });
  });

  group('contact card profile resolver', () {
    test('concurrent cards share a request and use the matching target profile',
        () async {
      final pending = Completer<List<UserFullInfo>?>();
      final fixture = _ResolverFixture(fetch: (_) => pending.future);
      final first = fixture.resolver.resolve('im_target');
      final second = fixture.resolver.resolve('im_target');
      expect(fixture.requests, ['im_target']);
      pending.complete([
        UserFullInfo(userID: 'im_other', account: '@wrongaccount'),
        UserFullInfo(userID: 'im_target', account: ' @abcdefgh12 '),
      ]);
      expect(
          await Future.wait([first, second]), ['@abcdefgh12', '@abcdefgh12']);
      expect(fixture.resolver.peek('im_target'), '@abcdefgh12');
      expect(await fixture.resolver.resolve('im_target'), '@abcdefgh12');
      expect(fixture.resolver.peek('im_other'), isNull);
      expect(fixture.requests, ['im_target']);
    });

    final negativeProfiles = <String, List<UserFullInfo>?>{
      'empty response': [],
      'wrong target': [
        UserFullInfo(userID: 'im_other', account: '@wrongaccount')
      ],
      'empty public account': [UserFullInfo(userID: 'im_target', account: ' ')],
    };
    for (final entry in negativeProfiles.entries) {
      test('${entry.key} is cached without repeatedly querying a card',
          () async {
        final fixture = _ResolverFixture(fetch: (_) async => entry.value);
        expect(await fixture.resolver.resolve('im_target'), isNull);
        expect(fixture.resolver.peek('im_target'), isNull);
        expect(await fixture.resolver.resolve('im_target'), isNull);
        expect(await fixture.resolver.resolve('im_target'), isNull);
        expect(fixture.requests, ['im_target']);
      });
    }

    test(
        'unavailable response is retried instead of caching a permission empty list',
        () async {
      final fixture = _ResolverFixture(fetch: (_) async => null);
      expect(await fixture.resolver.resolve('im_target'), isNull);
      expect(fixture.resolver.peek('im_target'), isNull);
      expect(await fixture.resolver.resolve('im_target'), isNull);
      expect(await fixture.resolver.resolve('im_target'), isNull);
      expect(fixture.requests, ['im_target', 'im_target', 'im_target']);
    });

    for (final changeToken in [false, true]) {
      test(
          '${changeToken ? 'token' : 'account'} change rejects a late response and clears snapshots',
          () async {
        final pending = Completer<List<UserFullInfo>?>();
        final fixture = _ResolverFixture(
            fetch: (target) => target == 'cached'
                ? Future.value(
                    [UserFullInfo(userID: 'cached', account: '@cached')])
                : pending.future);
        expect(await fixture.resolver.resolve('cached'), '@cached');
        final oldRequest = fixture.resolver.resolve('im_target');
        if (changeToken) {
          fixture.token = 'token-b';
        } else {
          fixture.userID = 'owner-b';
        }
        pending.complete(
            [UserFullInfo(userID: 'im_target', account: '@oldaccount')]);
        // No intermediate peek/resolve: the response itself must check session.
        expect(await oldRequest, isNull);
        expect(fixture.resolver.peek('im_target'), isNull);
        expect(fixture.resolver.peek('cached'), isNull);
        fixture.fetch = (target) async =>
            [UserFullInfo(userID: target, account: '@newaccount')];
        expect(await fixture.resolver.resolve('im_target'), '@newaccount');
        expect(fixture.requests, ['cached', 'im_target', 'im_target']);
      });
    }

    test(
        'late old-session completion cannot clear the new session single flight',
        () async {
      final oldResponse = Completer<List<UserFullInfo>?>();
      final newResponse = Completer<List<UserFullInfo>?>();
      var call = 0;
      final fixture = _ResolverFixture(
          fetch: (_) => call++ == 0 ? oldResponse.future : newResponse.future);
      final oldRequest = fixture.resolver.resolve('im_target');
      fixture.token = 'token-b';
      final newRequest = fixture.resolver.resolve('im_target');
      oldResponse.complete(
          [UserFullInfo(userID: 'im_target', account: '@oldaccount')]);
      expect(await oldRequest, isNull);
      expect(fixture.resolver.peek('im_target'), isNull);
      final duplicate = fixture.resolver.resolve('im_target');
      expect(fixture.requests, ['im_target', 'im_target']);
      newResponse.complete(
          [UserFullInfo(userID: 'im_target', account: '@newaccount')]);
      expect(await Future.wait([newRequest, duplicate]),
          ['@newaccount', '@newaccount']);
      expect(fixture.resolver.peek('im_target'), '@newaccount');
    });

    test('logout and empty targets never query or expose cached accounts',
        () async {
      final fixture = _ResolverFixture();
      expect(await fixture.resolver.resolve('cached'), '@cached');
      fixture.userID = null;
      expect(fixture.resolver.peek('cached'), isNull);
      expect(await fixture.resolver.resolve('cached'), isNull);
      fixture.userID = 'owner-b';
      fixture.token = null;
      expect(await fixture.resolver.resolve('cached'), isNull);
      fixture.token = 'token-b';
      expect(await fixture.resolver.resolve(''), isNull);
      expect(await fixture.resolver.resolve('  '), isNull);
      expect(fixture.requests, ['cached']);
      expect(await fixture.resolver.resolve('cached'), '@cached');
      expect(fixture.requests, ['cached', 'cached']);
    });

    test('transport failure is retryable instead of caching a missing account',
        () async {
      final fixture =
          _ResolverFixture(fetch: (_) async => throw StateError('offline'));
      expect(await fixture.resolver.resolve('im_target'), isNull);
      fixture.fetch = (target) async =>
          [UserFullInfo(userID: target, account: '@recovered')];
      expect(await fixture.resolver.resolve('im_target'), '@recovered');
      expect(fixture.requests, ['im_target', 'im_target']);
    });

    test('cache is bounded to 256 and recently viewed cards survive eviction',
        () async {
      final fixture = _ResolverFixture();
      for (var index = 0; index < 256; index++) {
        expect(
            await fixture.resolver.resolve('target-$index'), '@target-$index');
      }
      expect(fixture.resolver.peek('target-0'), '@target-0');
      expect(await fixture.resolver.resolve('target-256'), '@target-256');
      expect(fixture.resolver.peek('target-1'), isNull);
      expect(await fixture.resolver.resolve('target-0'), '@target-0');
      expect(fixture.requests, hasLength(257));
      expect(await fixture.resolver.resolve('target-1'), '@target-1');
      expect(fixture.requests.where((target) => target == 'target-1'),
          hasLength(2));
      expect(fixture.resolver.peek('target-2'), isNull);
    });

    test('missing-account snapshots also count toward the bounded cache',
        () async {
      final fixture = _ResolverFixture(fetch: (_) async => <UserFullInfo>[]);
      for (var index = 0; index < 257; index++) {
        expect(await fixture.resolver.resolve('missing-$index'), isNull);
      }
      expect(await fixture.resolver.resolve('missing-1'), isNull);
      expect(fixture.requests, hasLength(257));
      expect(await fixture.resolver.resolve('missing-0'), isNull);
      expect(fixture.requests.where((target) => target == 'missing-0'),
          hasLength(2));
    });
  });
}

class _ResolverFixture {
  _ResolverFixture(
      {Future<List<UserFullInfo>?> Function(String target)? fetch}) {
    this.fetch = fetch ??
        (target) async => [UserFullInfo(userID: target, account: '@$target')];
    resolver = ContactCardProfileResolver(
      fetchProfile: (target) {
        requests.add(target);
        return this.fetch(target);
      },
      currentUserID: () => userID,
      currentToken: () => token,
    );
  }

  String? userID = 'owner-a';
  String? token = 'token-a';
  final requests = <String>[];
  late Future<List<UserFullInfo>?> Function(String target) fetch;
  late final ContactCardProfileResolver resolver;
}
