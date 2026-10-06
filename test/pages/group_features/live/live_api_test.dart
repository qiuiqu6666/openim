import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'package:openim/pages/group_features/live/data/live_api.dart';
import 'package:openim/pages/group_features/live/models/live_errors.dart';
import 'package:openim/pages/group_features/live/models/live_models.dart';
import 'package:openim/pages/group_features/live/models/live_tip_currency.dart';
import 'package:openim/services/fund_pending_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'live_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final invalidSummaries = <Object?>[
    null,
    {'schemaVersion': 2, 'revision': 8},
    {
      'schemaVersion': 1,
      'revision': 8,
      'live': {'status': 'ready', 'sessionID': 'other-scene'}
    },
    {
      'schemaVersion': 1,
      'revision': 8,
      'live': {'status': 'ended', 'sessionID': 'live-1'}
    }
  ];
  for (var index = 0; index < invalidSummaries.length; index++) {
    final summary = invalidSummaries[index];
    test(
        'incomplete successful-write summary $index preserves its DTO without another POST',
        () async {
      final applied = <Map<String, dynamic>>[];
      final transport = LiveTransport((_) => {
            ...liveDTO(),
            'imSyncStatus': 'pending',
            if (summary != null) 'groupFeatures': summary
          });
      final api =
          LiveApi(liveContext(transport.api(), onFeaturesChanged: applied.add));
      await expectLater(
          api.configure(name: '房间', description: '', anchorID: 'anchor'),
          throwsA(isA<LiveApiException>()
              .having((e) => e.unknownResult, 'must reconcile', isTrue)
              .having(
                  (e) => e.committedSession?.id, 'preserved real DTO', 'live-1')
              .having((e) => e.committedSession?.version, 'scene version', 1)));
      expect(applied, isEmpty);
      expect(transport.requests.length, 1);
    });
  }
  test(
      'pending commit marks the local authoritative summary for mirror protection',
      () async {
    final commits = <(Map<String, dynamic>, bool)>[];
    final transport = LiveTransport((_) => {
          ...liveDTO(),
          'imSyncStatus': 'pending',
          'groupFeatures': {
            'schemaVersion': 1,
            'revision': 8,
            'live': {'status': 'ready', 'sessionID': 'live-1'}
          }
        });
    final base = liveContext(transport.api());
    final context = GroupFeatureContext(
        groupID: base.groupID,
        groupName: base.groupName,
        currentUserID: base.currentUserID,
        api: base.api,
        capabilities: base.capabilities,
        sessionCurrent: base.sessionCurrent,
        onFeaturesChanged: (_) => fail('Commit bypassed mirror-aware callback'),
        onFeaturesCommitted: (summary, pending) =>
            commits.add((summary, pending)));
    final result = await LiveApi(context)
        .configure(name: '房间', description: '', anchorID: 'anchor');
    expect(result.imSyncStatus, 'pending');
    expect(commits.single.$1['revision'], 8);
    expect(commits.single.$2, isTrue);
  });
  test(
      'actual contract sends explicit null/strings and accepts committed pending summaries',
      () async {
    final summaries = <Map<String, dynamic>>[];
    final transport = LiveTransport((request) => {
          'errCode': 0,
          'data': {
            ...liveDTO(
                status: request.method == 'PATCH' ? 'SCHEDULED' : 'AUTHORIZED'),
            'scheduledStartAt': request.method == 'PATCH'
                ? (request.data as Map)['scheduledStartAt']
                : null,
            'imSyncStatus': 'pending',
            'groupFeatures': {
              'schemaVersion': 1,
              'revision': 8,
              'live': {
                'status': request.method == 'PATCH' ? 'scheduled' : 'ready',
                'sessionID': 'live-1'
              }
            }
          }
        });
    final api =
        LiveApi(liveContext(transport.api(), onFeaturesChanged: summaries.add));
    final configured = await api.configure(
        name: '  名称  ', description: '  描述  ', anchorID: 'anchor');
    expect(configured.imSyncStatus, 'pending');
    final at = DateTime.now().add(const Duration(days: 1));
    await api.schedule(name: '更新名称', at: at);
    expect(transport.requests.first.uri.toString(),
        contains('/groups/group%231/live/authorize'));
    expect(transport.requests.first.headers['token'], 'chat-token');
    expect(transport.requests.first.data, {
      'roomName': '名称',
      'description': '描述',
      'anchorUserId': 'anchor',
      'scheduledStartAt': null
    });
    expect(transport.requests.last.data,
        {'roomName': '更新名称', 'scheduledStartAt': at.toUtc().toIso8601String()});
    expect(
        transport.requests.map((v) => v.headers['operationID']).toSet().length,
        2);
    expect(summaries.map((v) => v['revision']), [8, 8]);
  });
  test('private operations reject missing capabilities before any request',
      () async {
    final transport = LiveTransport((_) => liveDTO());
    final api = LiveApi(liveContext(transport.api(),
        permissions: const GroupLiveCapabilities()));
    await expectLater(
        api.configure(name: '名字', description: '', anchorID: 'anchor'),
        throwsStateError);
    await expectLater(
        api.schedule(
            name: '名字', at: DateTime.now().add(const Duration(days: 1))),
        throwsStateError);
    await expectLater(api.push('live-1'), throwsStateError);
    await expectLater(api.end(revoke: true), throwsStateError);
    await expectLater(
        api.tip(
            id: 'live-1',
            currency: 'USDT',
            amount: 1,
            password: '123456',
            orderID: 'order',
            memo: ''),
        throwsStateError);
    expect(transport.requests, isEmpty);
  });
  test('late account response does not apply a summary', () async {
    var current = true;
    final response = Completer<Map<String, dynamic>>();
    final transport = LiveTransport((_) => response.future);
    final summaries = <Map<String, dynamic>>[];
    final pending = LiveApi(liveContext(transport.api(),
            current: () => current, onFeaturesChanged: summaries.add))
        .current();
    await Future<void>.delayed(Duration.zero);
    current = false;
    final expectation = expectLater(pending, throwsStateError);
    response.complete({
      'active': true,
      'session': liveDTO(),
      'groupFeatures': {'schemaVersion': 1, 'revision': 9}
    });
    await expectation;
    expect(summaries, isEmpty);
  });
  test(
      'confirmed tip remains success after permission notice while private reads are fenced',
      () async {
    var allowed = true;
    final response = Completer<Map<String, dynamic>>();
    final transport = LiveTransport((request) =>
        request.method == 'POST' ? response.future : {'active': false});
    final api = LiveApi(
        liveContext(transport.api(), capabilitiesCurrent: () => allowed));
    final payment = api.tip(
        id: 'live-1',
        currency: 'USDT',
        amount: 1,
        password: '123456',
        orderID: 'same-order',
        memo: '');
    await Future<void>.delayed(Duration.zero);
    allowed = false;
    response.complete({'tipId': 5, 'liveSessionId': 'live-1'});
    expect(await payment, {'tipId': 5, 'liveSessionId': 'live-1'});
    expect(await api.current(), isNull);
    await expectLater(
        api.push('live-1'), throwsA(isA<GroupFeatureException>()));
    expect(transport.requests.length, 2);
  });
  test(
      'unsupported RTC-only playback and unavailable services produce real errors',
      () async {
    final transport = LiveTransport((_) => {
          'liveSessionId': 'live-1',
          'protocol': 'webrtc',
          'playUrl': 'https://rtc.test/room'
        });
    final api = LiveApi(liveContext(transport.api()));
    await expectLater(api.play('live-1'), throwsFormatException);
    transport.status = 404;
    await expectLater(
        api.current(),
        throwsA(isA<GroupFeatureException>()
            .having((v) => v.unavailable, 'unavailable', isTrue)));
  });
  test(
      'malformed payment success remains uncertain and preserves backend payload fields',
      () async {
    final transport = LiveTransport((_) => {});
    final api = LiveApi(liveContext(transport.api(),
        permissions: const GroupLiveCapabilities(canTip: true, raw: {
          'tipCurrencies': [
            {'code': 'BI99', 'label': '99BI', 'decimals': 2}
          ]
        })));
    await expectLater(
        api.tip(
            id: 'live-1',
            currency: 'BI99',
            amount: 100,
            password: '123456',
            orderID: 'same',
            memo: '谢谢'),
        throwsA(isA<GroupFeatureException>()
            .having((v) => v.unknownResult, 'unknown result', isTrue)));
    expect(transport.requests.single.data, {
      'currency': 'BI99',
      'amount': 100,
      'payPin': '123456',
      'clientOrderId': 'same',
      'memo': '谢谢'
    });
  });
  test('currency is explicit and decimal amounts use integer units', () {
    expect(LiveTipCurrency.fromCapabilities({}), isEmpty);
    final currencies = LiveTipCurrency.fromCapabilities({
      'tipCurrencies': ['USDT', '99', 'PLATFORM']
    });
    expect(currencies.map((v) => v.code), ['USDT', '99']);
    expect(currencies.first.units('1.000001'), 1000001);
    expect(currencies.last.units('0.01'), 1);
    expect(() => currencies.last.units('1.001'), throwsFormatException);
    expect(() => currencies.first.units('0'), throwsFormatException);
    expect(() => currencies.first.units('1e6'), throwsFormatException);
  });
  test('empty optional strings are transmitted and no old 99 alias is accepted',
      () async {
    final transport = LiveTransport((request) => request.path.endsWith('/tip')
        ? {'tipId': 1, 'liveSessionId': 'live-1'}
        : {
            ...liveDTO(),
            'groupFeatures': {
              'schemaVersion': 1,
              'revision': 1,
              'live': {'status': 'ready', 'sessionID': 'live-1'}
            }
          });
    final api = LiveApi(liveContext(transport.api()));
    await api.configure(name: '房间', description: '  ', anchorID: 'anchor');
    await api.tip(
        id: 'live-1',
        currency: 'USDT',
        amount: LiveApi.maxTipAmount,
        password: '123456',
        orderID: 'one',
        memo: '  ');
    expect(transport.requests.first.data, {
      'roomName': '房间',
      'description': '',
      'anchorUserId': 'anchor',
      'scheduledStartAt': null
    });
    expect((transport.requests.last.data as Map)['memo'], '');
    await expectLater(
        api.tip(
            id: 'live-1',
            currency: '99',
            amount: 100,
            password: '123456',
            orderID: 'old-alias',
            memo: ''),
        throwsFormatException);
    expect(transport.requests.length, 2);
  });
  test(
      'invalid Unicode lengths, schedule and unsafe integer reject before transport',
      () async {
    final transport = LiveTransport((_) => liveDTO());
    final api = LiveApi(liveContext(transport.api()));
    await expectLater(
        api.configure(
            name: List.filled(11, '😀').join(),
            description: '',
            anchorID: 'anchor'),
        throwsFormatException);
    await expectLater(
        api.configure(
            name: '房间',
            description: List.filled(31, '字').join(),
            anchorID: 'anchor'),
        throwsFormatException);
    await expectLater(
        api.schedule(name: '', at: DateTime.now().add(const Duration(days: 1))),
        throwsFormatException);
    await expectLater(
        api.configure(
            name: '房间',
            description: '',
            anchorID: 'anchor',
            scheduledAt: DateTime.now()),
        throwsFormatException);
    await expectLater(
        api.tip(
            id: 'live-1',
            currency: 'USDT',
            amount: LiveApi.maxTipAmount + 1,
            password: '123456',
            orderID: 'one',
            memo: ''),
        throwsFormatException);
    await expectLater(
        api.tip(
            id: 'live-1',
            currency: 'USDT',
            amount: 1,
            password: '123456',
            orderID: 'one',
            memo: List.filled(51, '字').join()),
        throwsFormatException);
    expect(transport.requests, isEmpty);
  });
  for (final operation in ['configure', 'schedule', 'stop']) {
    test(
        'committed $operation succeeds when its permission epoch changes in flight',
        () async {
      var allowed = true;
      final response = Completer<Map<String, dynamic>>();
      final transport = LiveTransport((_) => response.future);
      final summaries = <Map<String, dynamic>>[];
      final api = LiveApi(liveContext(transport.api(),
          capabilitiesCurrent: () => allowed,
          onFeaturesChanged: summaries.add));
      final at = DateTime.now().add(const Duration(days: 1)).toUtc();
      final Future<LiveSession> pending = switch (operation) {
        'configure' =>
          api.configure(name: '房间', description: '', anchorID: 'anchor'),
        'schedule' => api.schedule(name: '房间', at: at),
        _ => api.end(revoke: false)
      };
      await Future<void>.delayed(Duration.zero);
      allowed = false;
      response.complete({
        'errCode': 0,
        'data': {
          ...liveDTO(
              status: operation == 'stop'
                  ? 'ENDED'
                  : operation == 'schedule'
                      ? 'SCHEDULED'
                      : 'AUTHORIZED',
              version: 2),
          'scheduledStartAt':
              operation == 'schedule' ? at.toIso8601String() : null,
          'imSyncStatus': 'pending',
          'groupFeatures': {
            'schemaVersion': 1,
            'revision': 9,
            'live': {
              'sessionID': 'live-1',
              'status': operation == 'stop'
                  ? 'ended'
                  : operation == 'schedule'
                      ? 'scheduled'
                      : 'ready'
            }
          }
        }
      });
      final result = await pending;
      expect(result.imSyncStatus, 'pending');
      expect(result.version, 2);
      expect(summaries.single['revision'], 9);
      expect(transport.requests.length, 1);
    });
  }
  test(
      'private push credentials cannot escape a permission change during the read',
      () async {
    var allowed = true;
    final response = Completer<Map<String, dynamic>>();
    final transport = LiveTransport((_) => response.future);
    final api = LiveApi(
        liveContext(transport.api(), capabilitiesCurrent: () => allowed));
    final pending = api.push('live-1');
    await Future<void>.delayed(Duration.zero);
    allowed = false;
    final expectation = expectLater(
        pending,
        throwsA(isA<GroupFeatureException>()
            .having((e) => e.code, 'code', 'CAPABILITIES_CHANGED')));
    response.complete(
        {'rtmpServer': 'rtmp://push.test/live', 'streamKey': 'secret'});
    await expectation;
    expect(transport.requests.length, 1);
  });
  for (final code in ['20012', '1002', 'FORBIDDEN']) {
    test('permission rejection $code invalidates once without retrying a write',
        () async {
      var invalidations = 0;
      final transport = LiveTransport((_) => {'errCode': code, 'errMsg': 'raw'})
        ..status = 403;
      final base = liveContext(transport.api());
      final context = GroupFeatureContext(
          groupID: base.groupID,
          groupName: base.groupName,
          currentUserID: base.currentUserID,
          api: base.api,
          capabilities: base.capabilities,
          sessionCurrent: base.sessionCurrent,
          onFeaturesChanged: base.onFeaturesChanged,
          onCapabilitiesInvalidated: () => invalidations++);
      await expectLater(
          LiveApi(context)
              .configure(name: '房间', description: '', anchorID: 'anchor'),
          throwsA(isA<LiveApiException>()
              .having((e) => e.code, 'code', code)
              .having((e) => e.unknownResult, 'definite server rejection',
                  isFalse)));
      expect(invalidations, 1);
      expect(transport.requests.length, 1);
    });
  }
  for (final entry in {
    20026: '余额不足',
    20034: '设置支付密码',
    20035: '支付密码不正确',
    20036: '支付密码已锁定',
    20062: '原交易',
    20068: '不存在',
    20069: '已有未结束',
    20070: '状态不允许',
    20071: '尚未配置'
  }.entries) {
    test(
        'business code ${entry.key} has actionable feedback and preserves certainty',
        () async {
      final transport =
          LiveTransport((_) => {'errCode': entry.key, 'errMsg': 'raw'});
      final api = LiveApi(liveContext(transport.api()));
      final request = switch (entry.key) {
        20068 => api.detail('live-1'),
        20069 => api.configure(name: '房间', description: '', anchorID: 'anchor'),
        20071 => api.play('live-1'),
        _ => api.tip(
            id: 'live-1',
            currency: 'USDT',
            amount: 1,
            password: '123456',
            orderID: 'one',
            memo: '')
      };
      await expectLater(
          request,
          throwsA(isA<LiveApiException>()
              .having((e) => e.code, 'code', '${entry.key}')
              .having((e) => e.message, 'feedback', contains(entry.value))
              .having((e) => e.unknownResult, 'definite rejection', isFalse)));
    });
  }
  test('malformed committed DTO is uncertain and never applies its summary',
      () async {
    final summaries = <Map<String, dynamic>>[];
    final transport = LiveTransport((_) => {
          ...liveDTO(),
          'version': 0,
          'imSyncStatus': 'pending',
          'groupFeatures': {'schemaVersion': 1, 'revision': 10}
        });
    await expectLater(
        LiveApi(liveContext(transport.api(), onFeaturesChanged: summaries.add))
            .configure(name: '房间', description: '', anchorID: 'anchor'),
        throwsA(isA<LiveApiException>()
            .having((e) => e.unknownResult, 'uncertain', isTrue)));
    expect(summaries, isEmpty);
  });
  test(
      'DTOs reject wrong group, nonboolean current, bad version and invalid expiry',
      () async {
    var reply = <String, dynamic>{...liveDTO(), 'groupId': 'other'};
    final transport = LiveTransport((_) => reply);
    final api = LiveApi(liveContext(transport.api()));
    await expectLater(api.detail('live-1'), throwsFormatException);
    reply = {'active': 'true', 'session': liveDTO()};
    await expectLater(api.current(), throwsFormatException);
    reply = {...liveDTO(), 'version': '1'};
    await expectLater(api.detail('live-1'), throwsFormatException);
    reply = {...liveDTO(), 'scheduledStartAt': 1791100800000};
    await expectLater(api.detail('live-1'), throwsFormatException);
    reply = {
      'liveSessionId': 'live-1',
      'playUrl': 'https://play.test/live.m3u8',
      'expiresAt': 'bad-date'
    };
    await expectLater(api.play('live-1'), throwsFormatException);
    reply = {'rtmpServer': 'http://push.test/live', 'streamKey': 'secret'};
    await expectLater(api.push('live-1'), throwsFormatException);
  });
  test(
      'detail and play forward cancellation without returning stale credentials',
      () async {
    final transport = LiveTransport((_) => liveDTO());
    final api = LiveApi(liveContext(transport.api()));
    final cancel = CancelToken()..cancel('route closed');
    for (final request in [
      () => api.detail('live-1', cancelToken: cancel),
      () => api.play('live-1', cancelToken: cancel)
    ]) {
      await expectLater(
          request(),
          throwsA(isA<GroupFeatureException>()
              .having((e) => e.code, 'cancelled', 'CANCELLED')));
    }
    expect(transport.requests, isEmpty);
  });
  test(
      'confirmed create cannot apply its summary to a changed account or group session',
      () async {
    var current = true;
    final response = Completer<Map<String, dynamic>>();
    final transport = LiveTransport((_) => response.future);
    final summaries = <Map<String, dynamic>>[];
    final api = LiveApi(liveContext(transport.api(),
        current: () => current, onFeaturesChanged: summaries.add));
    final pending =
        api.configure(name: '房间', description: '', anchorID: 'anchor');
    await Future<void>.delayed(Duration.zero);
    current = false;
    final expectation = expectLater(pending, throwsStateError);
    response.complete({
      ...liveDTO(),
      'imSyncStatus': 'pending',
      'groupFeatures': {'schemaVersion': 1, 'revision': 10}
    });
    await expectation;
    expect(summaries, isEmpty);
    expect(transport.requests.length, 1);
  });
  test(
      'existing pending store retains the original tip ID across reopen and rejects replacement',
      () async {
    SharedPreferences.setMockInitialValues({});
    const scope = 'group-live-tip:group#1:live-1';
    final draft = {
      'clientOrderID': 'tip-original',
      'liveSessionId': 'live-1',
      'amount': 10,
      'currency': '99'
    };
    final first = FundPendingStore(accountKey: 'https://example.test:self');
    await first.save(scope, draft);
    final reopened = FundPendingStore(accountKey: 'https://example.test:self');
    expect(await reopened.read(scope), draft);
    await expectLater(
        reopened.save(scope, {...draft, 'clientOrderID': 'tip-new'}),
        throwsA(isA<FundPendingConflict>()));
    expect(
        await FundPendingStore(accountKey: 'https://example.test:other')
            .read(scope),
        isNull);
    await reopened.clear(scope, clientOrderID: 'tip-original');
    expect(await reopened.read(scope), isNull);
  });
}
