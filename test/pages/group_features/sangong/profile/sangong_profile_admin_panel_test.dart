import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_profile_admin_layout.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_profile_admin_panel.dart';
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import 'package:openim/pages/group_features/sangong/utils/sangong_banker_setup_input.dart';
import '../sangong_test_support.dart';

Map<String, dynamic> _session({bool member = false, String banker = 'other'}) =>
    {
      'status': 'running',
      'round': {
        'id': 18,
        'periodNo': 3,
        'status': 'betting',
        'bankerImUserId': banker,
        'bankerDoor': 2,
        'bankerLimit': 2000,
        'coBank': {
          'poolTotal': 800,
          'members': [
            if (member)
              {
                'userId': 19,
                'imUserId': 'im_target',
                'nickname': '秋',
                'amount': 200,
                'sharePercent': 25,
              }
          ]
        }
      }
    };

dynamic _readResponse(SangongCall call) {
  if (call.path.endsWith('/reports/users')) {
    return {
      'users': [
        {
          'userId': 19,
          'imUserId': 'im_target',
          'nickname': '秋',
          'balance': 420,
          'rebatePer10000': 8,
        }
      ],
      'page': 1,
      'totalPages': 1,
    };
  }
  if (call.path.endsWith('/user-detail')) {
    return {
      'user': {'imUserId': 'im_target'},
      'parent': {'nickname': '上级甲'}
    };
  }
  if (call.path.endsWith('/session')) return _session();
  return sangongFixtureResponse(call);
}

SangongProfileAdminLayout _layout(WidgetTester tester) => tester
    .widget<SangongProfileAdminLayout>(find.byType(SangongProfileAdminLayout));

Future<void> _mount(
        WidgetTester tester, SangongRuntime runtime) =>
    pumpSangongPage(
        tester,
        runtime,
        const Scaffold(
            body: SingleChildScrollView(
                child: SangongProfilePanel(userID: 'im_target'))));

Future<void> _confirm(WidgetTester tester, VoidCallback action) async {
  action();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.tap(find.text('确认'));
  await tester.pump(const Duration(milliseconds: 350));
  await flushSangong(tester);
}

void main() {
  test('banker input follows all reference separators without guessing text',
      () {
    for (final separator in ['.', '/', '、', '-', '+']) {
      final result = parseSangongBankerSetupText(' 2 $separator 5000 ');
      expect(result.door, 2);
      expect(result.limit, 5000);
      expect(result.hasExplicitLimit, isTrue);
    }
    final door = parseSangongBankerSetupText('2');
    expect(door.door, 2);
    expect(door.limit, isNull);
    expect(door.hasExplicitLimit, isFalse);
    expect(parseSangongBankerSetupText('abc').door, isNull);
    expect(parseSangongBankerSetupText('2.-5').limit, -5,
        reason: 'Parsing preserves the value; the action rejects negatives.');
  });

  testWidgets('reference controls read real data and preview the real pool',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) => call.path.endsWith('/session')
          ? _session(member: true)
          : _readResponse(call);
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await _mount(tester, runtime);
    final layout = _layout(tester);
    expect(layout.points, 420);
    expect(layout.parentLabel, '上级甲');
    expect(layout.rebatePer10000, 8);
    expect(layout.sharePercent, 25);
    expect(layout.disabled, isFalse);
    layout.jointController.text = '200';
    await tester.pump();
    expect(_layout(tester).sharePercent, 20);
    expect(api.count('/session'), 1);
    expect(api.count('/settings'), 1);
    expect(
        api.calls.every(
            (c) => c.headers?['X-Tenant-Id'] == expectedSangongRequestTenant()),
        isTrue);
    await unmountSangong(tester);
    runtime.dispose();
  });

  testWidgets('load failure keeps unknown values and disables writes',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) {
        if (call.path.endsWith('/settings')) {
          throw const GroupFeatureException('规则暂不可用');
        }
        return _readResponse(call);
      };
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await _mount(tester, runtime);
    final layout = _layout(tester);
    expect(layout.error, '规则暂不可用');
    expect(layout.points, isNull);
    expect(layout.sharePercent, isNull);
    expect(layout.disabled, isTrue);
    layout.pointsController.text = '10';
    layout.onCredit!();
    await flushSangong(tester);
    expect(api.count('/credit'), 0);
    await unmountSangong(tester);
    runtime.dispose();
  });

  testWidgets('inline credit waits for confirmation and preserves IM identity',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) => call.path.endsWith('/credit')
          ? {'balance': 430}
          : _readResponse(call);
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await _mount(tester, runtime);
    final layout = _layout(tester);
    layout.pointsController.text = '10';
    layout.onCredit!();
    await tester.pump(const Duration(milliseconds: 350));
    expect(api.count('/credit'), 0);
    await tester.tap(find.text('确认'));
    await tester.pump(const Duration(milliseconds: 350));
    await flushSangong(tester);
    expect(api.count('/credit'), 1);
    final call = api.calls.singleWhere((c) => c.path.endsWith('/credit'));
    expect(call.body?['imUserId'], 'im_target');
    expect(call.body?['amount'], 10);
    expect(layout.pointsController.text, isEmpty);
    await unmountSangong(tester);
    runtime.dispose();
  });

  testWidgets('door.limit uses one confirmed setup with the entered values',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) {
        if (call.path.endsWith('/banker/setup')) {
          final response = _session(banker: 'im_target');
          (response['round'] as Map)['bankerLimit'] = 5000;
          return response;
        }
        return _readResponse(call);
      };
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await _mount(tester, runtime);
    final layout = _layout(tester);
    layout.bankerController.text = '2.5000';
    await tester.pump();
    await _confirm(tester, _layout(tester).onAssignBanker!);
    final call = api.calls.singleWhere((c) => c.path.endsWith('/banker/setup'));
    expect(call.body, {
      'imUserId': 'im_target',
      'door': 2,
      'limit': 5000,
      'nickname': '秋',
    });
    expect(layout.bankerController.text, isEmpty);
    await unmountSangong(tester);
    runtime.dispose();
  });

  testWidgets('single limit cannot silently replace another current banker',
      (tester) async {
    final api = SangongTestApi()..respond = _readResponse;
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await _mount(tester, runtime);
    final layout = _layout(tester);
    layout.bankerController.text = '5000';
    await tester.pump();
    await _confirm(tester, _layout(tester).onSetLimit!);
    expect(api.count('/banker/setup'), 0);
    expect(_layout(tester).error, contains('定庄信息已变化'));
    await unmountSangong(tester);
    runtime.dispose();
  });

  testWidgets('debit reloads the round and refuses unsettled co-bank funds',
      (tester) async {
    var member = false;
    final api = SangongTestApi()
      ..respond = (call) => call.path.endsWith('/session')
          ? _session(member: member)
          : _readResponse(call);
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await _mount(tester, runtime);
    final layout = _layout(tester);
    layout.pointsController.text = '10';
    member = true;
    await _confirm(tester, layout.onDebit!);
    expect(api.count('/session'), 2);
    expect(api.count('/debit'), 0);
    expect(_layout(tester).error, contains('尚未结算'));
    await unmountSangong(tester);
    runtime.dispose();
  });

  testWidgets('notification controls use both existing send endpoints',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) => call.path.endsWith('/send')
          ? <String, dynamic>{}
          : _readResponse(call);
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await _mount(tester, runtime);
    await _confirm(tester, _layout(tester).onSendBanker!);
    expect(api.count('/banker/send'), 1);
    await _confirm(tester, _layout(tester).onSendCoBank!);
    expect(api.count('/co-bank/send'), 1);
    await unmountSangong(tester);
    runtime.dispose();
  });

  testWidgets('cancel co-bank checks membership and confirms its removal',
      (tester) async {
    var member = true;
    final api = SangongTestApi()
      ..respond = (call) {
        if (call.path.endsWith('/co-bank/remove')) {
          member = false;
          return _session(member: member);
        }
        if (call.path.endsWith('/session')) return _session(member: member);
        return _readResponse(call);
      };
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await _mount(tester, runtime);
    await _confirm(tester, _layout(tester).onRemoveCoBank!);
    final call =
        api.calls.singleWhere((c) => c.path.endsWith('/co-bank/remove'));
    expect(call.body, {'userId': 19});
    expect(_layout(tester).sharePercent, 0);
    expect(_layout(tester).error, isNull);
    await unmountSangong(tester);
    runtime.dispose();
  });

  testWidgets('revocation closes confirmation and clears all private inputs',
      (tester) async {
    final api = SangongTestApi()..respond = _readResponse;
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await _mount(tester, runtime);
    final layout = _layout(tester);
    layout.pointsController.text = '10';
    layout.bankerController.text = '2.5000';
    layout.jointController.text = '200';
    layout.onCredit!();
    await tester.pump(const Duration(milliseconds: 350));
    api.privilege.setAllowed(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(SangongProfileAdminLayout), findsNothing);
    expect(find.text('确认'), findsNothing);
    expect(layout.pointsController.text, isEmpty);
    expect(layout.bankerController.text, isEmpty);
    expect(layout.jointController.text, isEmpty);
    expect(api.count('/credit'), 0);
    expect(tester.takeException(), isNull);
    await unmountSangong(tester);
    runtime.dispose();
  });

  testWidgets('late session after revocation never restores controls',
      (tester) async {
    final pending = Completer<dynamic>();
    final api = SangongTestApi()
      ..respond = (call) =>
          call.path.endsWith('/session') ? pending.future : _readResponse(call);
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await _mount(tester, runtime);
    expect(_layout(tester).points, isNull);
    api.privilege.setAllowed(false);
    await tester.pump();
    pending.complete(_session(member: true));
    await flushSangong(tester);
    expect(find.byType(SangongProfileAdminLayout), findsNothing);
    expect(tester.takeException(), isNull);
    await unmountSangong(tester);
    runtime.dispose();
  });

  testWidgets('unconfirmed setup does not clear input or repeat the write',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) => call.path.endsWith('/banker/setup')
          ? {'round': null}
          : _readResponse(call);
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await _mount(tester, runtime);
    final layout = _layout(tester);
    layout.bankerController.text = '2.5000';
    await tester.pump();
    await _confirm(tester, _layout(tester).onAssignBanker!);
    expect(_layout(tester).error, contains('结果尚未确认'));
    expect(layout.bankerController.text, '2.5000');
    _layout(tester).onRetry!();
    await flushSangong(tester);
    expect(api.count('/banker/setup'), 1);
    await unmountSangong(tester);
    runtime.dispose();
  });
}
