import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_my_config.dart';
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';

import '../sangong_test_support.dart';

Future<SangongMyConfig> _request(SangongRuntime runtime, String method) =>
    method == 'GET'
        ? runtime.admin.fetchMyConfig()
        : runtime.admin.saveMyConfig(
            name: ' 一号厅 ',
            imGroupGameId: ' group-sangong ',
            imGroupAdminStatsId: ' group-statistics ',
            imGroupLedgerId: ' group-credit ',
            imBotUserId: ' bot-sangong ',
            imGroupWaterId: ' group-water ',
          );

Matcher get _invalidConfiguration => isA<FormatException>().having(
      (error) => error.message,
      'message',
      'Invalid Sangong configuration response',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SangongTestApi api;
  late SangongRuntime runtime;
  setUp(() {
    api = SangongTestApi();
    runtime = SangongRuntime(sangongTestContext(
      api,
      canConfigure: true,
      canManage: false,
      canOpenAgent: false,
      enabled: false,
      tenantID: '',
    ));
    addTearDown(api.privilege.dispose);
    addTearDown(runtime.dispose);
  });

  for (final method in ['GET', 'PUT']) {
    test('$method accepts explicit boolean and compatible configuration status',
        () async {
      final cases = <(Object, bool)>[
        (true, true),
        (false, false),
        (0, false),
        (0.0, false),
        (-0.0, false),
        (1, true),
        (2, true),
        (-1, true),
        (0.5, true),
        (' true ', true),
        ('FALSE', false),
        ('1', true),
        (' 0 ', false),
        ('YeS', true),
        (' no ', false),
      ];
      for (final (status, expected) in cases) {
        api.respond = (_) => {...sangongConfig(), 'configured': status};
        final config = await _request(runtime, method);
        expect(config.configured, expected, reason: 'configured=$status');
        expect(config.tenantId, 'tenant-authorized');
        expect(config.imGroupGameId, 'group-sangong');
        expect(config.isOwner, isTrue);
        expect(api.calls.last.method, method);
        expect(api.calls.last.path, endsWith('/admin/my-config'));
      }
      // Direct API parsing does not publish a private binding or permissions.
      expect(runtime.config.hasCachedConfig, isFalse);
      expect(runtime.http.tenantId, isNull);
      expect(runtime.canManage, isFalse);
      expect(api.streamStarts, 0);
    });

    test('$method rejects null, structured and unknown configuration status',
        () async {
      final statuses = <dynamic>[
        null,
        <String, dynamic>{},
        <String, dynamic>{'value': false},
        <dynamic>[],
        <dynamic>[false],
        '',
        ' ',
        'unknown',
        'null',
        '2',
        '0.0',
        'true-ish',
      ];
      for (final status in statuses) {
        final response = {...sangongConfig(), 'configured': status};
        final original = jsonEncode(response);
        api.respond = (_) => response;
        await expectLater(
            _request(runtime, method), throwsA(_invalidConfiguration),
            reason: 'configured=$status');
        expect(jsonEncode(response), original);
      }
      expect(runtime.config.hasCachedConfig, isFalse);
      expect(runtime.http.tenantId, isNull);
      expect(runtime.canManage, isFalse);
    });

    test('$method rejects missing status and non-object responses', () async {
      final missingStatus = sangongConfig()..remove('configured');
      for (final response in <dynamic>[
        missingStatus,
        <String, dynamic>{},
        null,
        <dynamic>[],
        'unexpected response',
        {'errCode': 0, 'data': missingStatus},
      ]) {
        api.respond = (_) => response;
        await expectLater(
            _request(runtime, method), throwsA(_invalidConfiguration));
      }
    });

    test('$method preserves envelope fields and explicit permission values',
        () async {
      final payload = {
        ...sangongConfig(),
        'configured': ' YES ',
        'imGroupWaterId': ' group-water ',
        'canEditConfig': false,
        'canManageMembers': false,
      };
      final response = {'errCode': 0, 'data': payload};
      final original = jsonEncode(response);
      api.respond = (_) => response;
      final config = await _request(runtime, method);
      expect(config.configured, isTrue);
      expect(config.name, '一号厅');
      expect(config.tenantId, 'tenant-authorized');
      expect(config.imGroupGameId, 'group-sangong');
      expect(config.imGroupAdminStatsId, 'group-statistics');
      expect(config.imGroupLedgerId, 'group-credit');
      expect(config.imGroupWaterId, 'group-water');
      expect(config.imBotUserId, 'bot-sangong');
      expect(config.myRole, 'owner');
      expect(config.canEditConfig, isFalse);
      expect(config.canManageMembers, isFalse);
      expect(jsonEncode(response), original);
      expect(api.calls.single.method, method);
      if (method == 'PUT') {
        expect(api.calls.single.body, {
          'name': '一号厅',
          'imGroupGameId': 'group-sangong',
          'imGroupAdminStatsId': 'group-statistics',
          'imGroupLedgerId': 'group-credit',
          'imBotUserId': 'bot-sangong',
          'imGroupWaterId': 'group-water',
        });
      }
    });
  }

  test('invalid status cannot cache a first-time configuration or grant access',
      () async {
    final capability = runtime.featureContext.capabilities;
    api.respond = (_) => {...sangongConfig(), 'configured': null};
    await expectLater(
        runtime.config.refreshFromNetwork(), throwsA(_invalidConfiguration));
    expect(runtime.config.hasCachedConfig, isFalse);
    expect(runtime.http.tenantId, isNull);
    expect(runtime.featureContext.capabilities, same(capability));
    expect(runtime.canManage, isFalse);
    expect(api.calls.single.method, 'GET');
    expect(api.streamStarts, 0);
  });

  test('explicit false is a valid cached first-time configuration', () async {
    api.respond = (_) => sangongConfig(configured: false);
    final config = await runtime.config.refreshFromNetwork();
    expect(config.configured, isFalse);
    expect(runtime.config.hasCachedConfig, isTrue);
    expect(runtime.config.config, same(config));
    expect(runtime.http.tenantId, isNull);
    expect(runtime.canManage, isFalse);
  });

  test(
      'invalid refresh preserves previously confirmed configuration and binding',
      () async {
    final saved = SangongMyConfig.fromJson(sangongConfig());
    await runtime.config.applySaved(saved);
    expect(runtime.http.tenantId, 'tenant-authorized');
    api.respond = (_) => {...sangongConfig(), 'configured': 'unknown'};
    await expectLater(runtime.config.refreshFromNetwork(force: true),
        throwsA(_invalidConfiguration));
    expect(runtime.config.hasCachedConfig, isTrue);
    expect(runtime.config.config, same(saved));
    expect(runtime.http.tenantId, 'tenant-authorized');
    expect(runtime.canManage, isFalse);
  });
}
