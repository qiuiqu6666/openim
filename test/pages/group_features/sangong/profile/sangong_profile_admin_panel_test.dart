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
      ...sangongState(1),
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
  if (call.path.endsWith('/user')) {
    return {
      'exists': true,
      'user': {
        'userId': 19,
        'imUserId': 'im_target',
        'nickname': '秋',
        'balance': 420,
        'rebatePer10000': 8
      },
      'parent': {'nickname': '上级甲'}
    };
  }
  if (call.path.endsWith('/snapshot')) return _session();
  return sangongFixtureResponse(call);
}

SangongProfileAdminLayout _layout(WidgetTester tester) => tester
    .widget<SangongProfileAdminLayout>(find.byType(SangongProfileAdminLayout));

Future<void> _mount(WidgetTester tester, SangongRuntime runtime,
        {String nickname = ''}) =>
    pumpSangongPage(
        tester,
        runtime,
        Scaffold(
            body: SingleChildScrollView(
                child: SangongProfilePanel(
                    userID: 'im_target', nickname: nickname))));

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
      ..respond = (call) => call.path.endsWith('/snapshot')
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
    expect(_layout(tester).sharePercent, 25);
    _layout(tester).onSetCoBank!();
    await tester.pump();
    expect(_layout(tester).coBankSummary, contains('未保存'));
    expect(api.count('/commands/round.co_bank'), 0);
    expect(api.count('/commands/round.co_bank_notice'), 0);
    expect(api.count('/snapshot'), 1);
    expect(api.count('/user'), 1);
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
        if (call.path.endsWith('/snapshot')) {
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
    expect(api.count('/commands/wallet.adjust'), 0);
    await unmountSangong(tester);
    runtime.dispose();
  });

  testWidgets('inline credit waits for confirmation and preserves IM identity',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) => call.path.endsWith('/commands/wallet.adjust')
          ? sangongReceipt(call, {'imUserId': 'im_target', 'balance': 430})
          : _readResponse(call);
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await _mount(tester, runtime);
    final layout = _layout(tester);
    layout.pointsController.text = '10';
    layout.onCredit!();
    await tester.pump(const Duration(milliseconds: 350));
    expect(api.count('/commands/wallet.adjust'), 0);
    await tester.tap(find.text('确认'));
    await tester.pump(const Duration(milliseconds: 350));
    await flushSangong(tester);
    expect(api.count('/commands/wallet.adjust'), 1);
    final call = api.calls
        .singleWhere((c) => c.path.endsWith('/commands/wallet.adjust'));
    expect(call.body?['input']['imUserId'], 'im_target');
    expect(call.body?['input']['delta'], 10);
    expect(layout.pointsController.text, isEmpty);
    await unmountSangong(tester);
    runtime.dispose();
  });

  testWidgets('door.limit uses one confirmed setup with the entered values',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) {
        if (call.path.endsWith('/commands/round.banker')) {
          final response = _session(banker: 'im_target');
          (response['round'] as Map)['bankerLimit'] = 5000;
          return sangongReceipt(call, {'state': response});
        }
        return _readResponse(call);
      };
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await _mount(tester, runtime, nickname: '资料页真实昵称');
    final layout = _layout(tester);
    layout.bankerController.text = '2.5000';
    await tester.pump();
    _layout(tester).onAssignBanker!();
    await tester.pump();
    expect(api.count('/commands/round.banker'), 0);
    expect(_layout(tester).bankerSummary, contains('未保存'));
    await _confirm(tester, _layout(tester).onSendBanker!);
    final call =
        api.calls.singleWhere((c) => c.path.endsWith('/commands/round.banker'));
    expect(call.body?['input'], {
      'roundId': 18,
      'openBetting': true,
      'imUserId': 'im_target',
      'door': 2,
      'bankerLimit': 5000,
      'nickname': '资料页真实昵称',
    });
    expect(layout.bankerController.text, isEmpty);
    expect(_layout(tester).error, isNull);
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
    _layout(tester).onSetLimit!();
    await tester.pump();
    expect(api.count('/commands/round.banker'), 0);
    expect(_layout(tester).error, isNull);
    await unmountSangong(tester);
    runtime.dispose();
  });

  testWidgets('debit reloads the round and refuses unsettled co-bank funds',
      (tester) async {
    var member = false;
    final api = SangongTestApi()
      ..respond = (call) => call.path.endsWith('/snapshot')
          ? _session(member: member)
          : _readResponse(call);
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await _mount(tester, runtime);
    final layout = _layout(tester);
    layout.pointsController.text = '10';
    member = true;
    await _confirm(tester, layout.onDebit!);
    expect(api.count('/snapshot'), 2);
    expect(api.count('/commands/wallet.adjust'), 0);
    expect(_layout(tester).error, contains('尚未结算'));
    await unmountSangong(tester);
    runtime.dispose();
  });

  testWidgets('banker and co-bank notices use the queued command',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) =>
          (call.path.endsWith('/commands/round.co_bank_notice') ||
                  call.path.endsWith('/commands/round.open'))
              ? sangongReceipt(call, {'queued': true})
              : _readResponse(call);
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await _mount(tester, runtime);
    await _confirm(tester, _layout(tester).onSendBanker!);
    expect(api.count('/commands/round.open'), 1);
    await _confirm(tester, _layout(tester).onSendCoBank!);
    expect(api.count('/commands/round.co_bank_notice'), 1);
    await unmountSangong(tester);
    runtime.dispose();
  });

  testWidgets('co-bank amount is only saved by Send in one command',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) => call.path.endsWith('/commands/round.co_bank_notice')
          ? sangongReceipt(call, {'state': _session(member: true)})
          : _readResponse(call);
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await _mount(tester, runtime);
    _layout(tester).jointController.text = '300';
    await tester.pump();
    _layout(tester).onSetCoBank!();
    await tester.pump();
    expect(api.calls.where((c) => c.method == 'POST'), isEmpty);
    expect(_layout(tester).coBankSummary, contains('未保存'));
    await _confirm(tester, _layout(tester).onSendCoBank!);
    final writes = api.calls.where((c) => c.method == 'POST').toList();
    expect(writes, hasLength(1));
    expect(writes.single.path, endsWith('/commands/round.co_bank_notice'));
    expect(writes.single.body?['input'],
        {'roundId': 18, 'userId': 19, 'amount': 300});
    expect(_layout(tester).coBankSummary, isNot(contains('未保存')));
    expect(_layout(tester).error, isNull);
    await unmountSangong(tester);
    runtime.dispose();
  });

  testWidgets('cancel co-bank checks membership and confirms its removal',
      (tester) async {
    var member = true;
    final api = SangongTestApi()
      ..respond = (call) {
        if (call.path.endsWith('/commands/round.co_bank_notice')) {
          member = false;
          return sangongReceipt(call, {'state': _session(member: member)});
        }
        if (call.path.endsWith('/snapshot')) return _session(member: member);
        return _readResponse(call);
      };
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await _mount(tester, runtime);
    _layout(tester).onRemoveCoBank!();
    await tester.pump();
    expect(api.count('/commands/round.co_bank_notice'), 0);
    expect(member, isTrue);
    expect(_layout(tester).coBankSummary, contains('未保存'));
    await _confirm(tester, _layout(tester).onSendCoBank!);
    final call = api.calls
        .singleWhere((c) => c.path.endsWith('/commands/round.co_bank_notice'));
    expect(call.body?['input'], {'roundId': 18, 'userId': 19, 'remove': true});
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
    expect(api.count('/commands/wallet.adjust'), 0);
    expect(tester.takeException(), isNull);
    await unmountSangong(tester);
    runtime.dispose();
  });

  testWidgets('late session after revocation never restores controls',
      (tester) async {
    final pending = Completer<dynamic>();
    final api = SangongTestApi()
      ..respond = (call) => call.path.endsWith('/snapshot')
          ? pending.future
          : _readResponse(call);
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
      ..respond = (call) => call.path.endsWith('/commands/round.banker')
          ? {'round': null}
          : _readResponse(call);
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await _mount(tester, runtime);
    final layout = _layout(tester);
    layout.bankerController.text = '2.5000';
    await tester.pump();
    _layout(tester).onAssignBanker!();
    await tester.pump();
    await _confirm(tester, _layout(tester).onSendBanker!);
    expect(_layout(tester).error, contains('结果尚未确认'));
    expect(_layout(tester).bankerSummary, contains('未保存'));
    _layout(tester).onRetry!();
    await flushSangong(tester);
    expect(api.count('/commands/round.banker'), 1);
    await unmountSangong(tester);
    runtime.dispose();
  });
}
