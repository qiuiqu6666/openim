import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_repository.dart';
import 'package:openim/pages/wallet/data/wallet_session_source.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_counterparty_source.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  late List<MethodCall> requests;
  late Future<Object?> Function(MethodCall) respond;

  setUp(() {
    requests = [];
    respond = (call) async => jsonEncode([
          {
            'userID': 'im_peer_a',
            'nickname': '  小秋  ',
            'account': '990001',
            'faceURL': ' https://profiles.example.test/a.png '
          },
          {
            'userID': 'im_peer_b',
            'nickname': '',
            'account': '990002',
            'faceURL': 'https://profiles.example.test/b.png'
          },
          {
            'userID': 'unrequested',
            'nickname': '其他用户',
            'faceURL': 'https://profiles.example.test/other.png'
          },
        ]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
      requests.add(call);
      return respond(call);
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  OpenIMWalletJournalCounterpartySource source({
    String Function()? accountProvider,
    String? Function()? tokenProvider,
    Duration timeout = const Duration(seconds: 2),
  }) =>
      OpenIMWalletJournalCounterpartySource(
        accountProvider: accountProvider ?? (() => 'synthetic-server:viewer'),
        tokenProvider: tokenProvider ?? (() => 'synthetic-im-session'),
        lookupTimeout: timeout,
      );

  test(
      'real SDK lookup batches deduplicated IDs and returns only their nicknames',
      () async {
    final profiles = await source()
        .getNicknames({'im_peer_a', ' im_peer_a ', 'im_peer_b', '', '  '});
    expect(requests, hasLength(1));
    expect(requests.single.method, 'getUsersInfo');
    expect(requests.single.arguments['userIDList'], ['im_peer_a', 'im_peer_b']);
    expect(profiles, {'im_peer_a': '小秋'});
    expect(profiles.values, isNot(contains('990001')));
    expect(profiles.keys, isNot(contains('unrequested')));
    expect(() => profiles['im_peer_a'] = 'changed', throwsUnsupportedError);
  });

  test('empty counterpart set skips the SDK call', () async {
    expect(await source().getNicknames({'', '  '}), isEmpty);
    expect(requests, isEmpty);
  });

  test('rich SDK profiles return nickname and avatar from one requested batch',
      () async {
    final profiles = await source().getProfiles({'im_peer_a', 'im_peer_b'});
    expect(requests, hasLength(1));
    expect(requests.single.method, 'getUsersInfo');
    expect(profiles.keys, ['im_peer_a', 'im_peer_b']);
    expect(profiles['im_peer_a']!.nickname, '小秋');
    expect(
        profiles['im_peer_a']!.faceURL, 'https://profiles.example.test/a.png');
    expect(profiles['im_peer_b']!.nickname, isEmpty);
    expect(
        profiles['im_peer_b']!.faceURL, 'https://profiles.example.test/b.png');
    expect(() => profiles.clear(), throwsUnsupportedError);
  });

  test('unknown, blank or absent nickname never falls back to an IM ID',
      () async {
    respond = (call) async => jsonEncode([
          {
            'userID': 'im_peer_a',
            'nickname': '   ',
            'account': 'public-account'
          },
          {'userID': 'im_peer_b'},
        ]);
    expect(await source().getNicknames({'im_peer_a', 'im_peer_b', 'missing'}),
        isEmpty);
  });

  test('late SDK rich result is rejected after an owner switch', () async {
    var owner = 'synthetic-server:old';
    final pending = Completer<Object?>();
    final arrived = Completer<void>();
    respond = (call) {
      arrived.complete();
      return pending.future;
    };
    final resolver = source(accountProvider: () => owner);
    final result = resolver.getProfiles({'im_peer_a'});
    final rejected =
        expectLater(result, throwsA(isA<WalletAccountChangedException>()));
    await arrived.future;
    owner = 'synthetic-server:new';
    pending.complete(jsonEncode([
      {
        'userID': 'im_peer_a',
        'nickname': '旧登录看到的昵称',
        'faceURL': 'https://profiles.example.test/old.png'
      },
    ]));
    await rejected;
    await expectLater(resolver.getNicknames({'im_peer_b'}),
        throwsA(isA<WalletAccountChangedException>()));
    expect(requests, hasLength(1));
  });

  test('same-account replacement login token rejects a late SDK avatar',
      () async {
    var session = 'synthetic-im-session-old';
    final pending = Completer<Object?>();
    final arrived = Completer<void>();
    respond = (call) {
      arrived.complete();
      return pending.future;
    };
    final resolver = source(tokenProvider: () => session);
    final rejected = expectLater(resolver.getProfiles({'im_peer_a'}),
        throwsA(isA<WalletAccountChangedException>()));
    await arrived.future;
    session = 'synthetic-im-session-new';
    pending.complete(jsonEncode([
      {
        'userID': 'im_peer_a',
        'nickname': '旧会话昵称',
        'faceURL': 'https://profiles.example.test/old.png'
      },
    ]));
    await rejected;
  });

  test('SDK failure and timeout remain optional enrichment failures', () async {
    respond =
        (call) async => throw PlatformException(code: 'synthetic-offline');
    await expectLater(source().getNicknames({'im_peer_a'}),
        throwsA(isA<PlatformException>()));
    respond = (call) => Completer<Object?>().future;
    await expectLater(
        source(timeout: const Duration(milliseconds: 10))
            .getNicknames({'im_peer_a'}),
        throwsA(isA<TimeoutException>()));
  });

  test('missing session never performs a profile request', () async {
    await expectLater(
        source(tokenProvider: () => null).getNicknames({'im_peer_a'}),
        throwsA(isA<WalletAccountChangedException>()));
    expect(requests, isEmpty);
  });

  test('production repository delegates to the real SDK batch lookup',
      () async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'synthetic-viewer',
      'imToken': 'synthetic-im-session',
      'chatToken': 'synthetic-chat-session',
    }));
    addTearDown(() async => DataSp.removeLoginCertificate());
    final repository =
        WalletFundRepository(accountProvider: () => 'synthetic-server:viewer');
    expect(repository, isA<WalletJournalCounterpartySource>());
    expect(await repository.getNicknames({'im_peer_a', 'im_peer_b'}),
        {'im_peer_a': '小秋'});
    expect(requests.single.method, 'getUsersInfo');
    expect(requests.single.arguments['userIDList'], ['im_peer_a', 'im_peer_b']);
  });

  test('repository guards even an injected source across an owner change',
      () async {
    var owner = 'synthetic-server:old';
    final pending = Completer<Map<String, String>>();
    final fixture = _FixtureCounterpartySource(pending.future);
    final repository = WalletFundRepository(
        accountProvider: () => owner, counterpartySource: fixture);
    final rejected = expectLater(repository.getNicknames({'im_peer_a'}),
        throwsA(isA<WalletAccountChangedException>()));
    owner = 'synthetic-server:new';
    pending.complete({'im_peer_a': '旧昵称'});
    await rejected;
    await expectLater(repository.getNicknames({'im_peer_b'}),
        throwsA(isA<WalletAccountChangedException>()));
    expect(fixture.requests, [
      <String>{'im_peer_a'}
    ]);
    expect(requests, isEmpty);
  });

  test('repository rich capability adapts old nickname-only injections once',
      () async {
    final fixture =
        _FixtureCounterpartySource(Future.value({'im_peer_a': '真实昵称'}));
    final repository = WalletFundRepository(
        accountProvider: () => 'synthetic-server:viewer',
        counterpartySource: fixture);
    final profiles = await repository.getProfiles({'im_peer_a'});
    expect(profiles['im_peer_a']!.nickname, '真实昵称');
    expect(profiles['im_peer_a']!.faceURL, isEmpty);
    expect(fixture.requests, [
      <String>{'im_peer_a'}
    ]);
    expect(requests, isEmpty);
  });
}

class _FixtureCounterpartySource implements WalletJournalCounterpartySource {
  _FixtureCounterpartySource(this.reply);
  final Future<Map<String, String>> reply;
  final List<Set<String>> requests = [];

  @override
  Future<Map<String, String>> getNicknames(Set<String> userIDs) {
    requests.add(Set.of(userIDs));
    return reply;
  }
}
