import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_game_settings.dart';

import '../sangong_test_support.dart';

void main() {
  for (final operation in ['member', 'transfer', 'settings']) {
    testWidgets('$operation pins scope before interceptor dispatch',
        (tester) async {
      final api = SangongTestApi();
      final runtime =
          sangongTestRuntime(sangongTestContext(api, tenantID: 'A'));
      addTearDown(runtime.dispose);
      final Future<dynamic> request = switch (operation) {
        'member' => runtime.admin.upsertMyConfigMember(imUserId: 'helper-id'),
        'transfer' =>
          runtime.agent.transferToChild(toImUserId: 'child-id', amount: 100),
        _ => runtime.settings.save(SangongGameSettings.defaults()),
      };
      final expectation = expectLater(request, throwsA(isA<DioException>()));
      // A synchronous context replacement precedes Dio's scheduled interceptor.
      runtime.updateContext(
          sangongTestContext(api, tenantID: 'B', capabilityVersion: 2));
      await flushSangong(tester);
      await expectation;
      expect(api.calls, isEmpty);
    });
  }

  testWidgets('configuration discovery response cannot cross tenant scope',
      (tester) async {
    final gate = Completer<dynamic>();
    final api = SangongTestApi()..respond = (_) => gate.future;
    final runtime = sangongTestRuntime(sangongTestContext(api, tenantID: 'A'));
    addTearDown(runtime.dispose);
    final request = runtime.admin.fetchMyConfigMembers();
    final expectation = expectLater(request, throwsA(isA<DioException>()));
    await flushSangong(tester);
    final tenant =
        expectedSangongRequestTenant(verifiedTenant: 'A', skipTenant: true);
    expect(
        api.calls.single.headers?.containsKey('X-Tenant-Id'), tenant != null);
    expect(api.calls.single.headers?['X-Tenant-Id'], tenant);
    runtime.updateContext(
        sangongTestContext(api, tenantID: 'B', capabilityVersion: 2));
    gate.complete({'members': []});
    await flushSangong(tester);
    await expectation;
  });

  testWidgets('same tenant with new capability context rejects old response',
      (tester) async {
    final gate = Completer<dynamic>();
    final api = SangongTestApi()..respond = (_) => gate.future;
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    final request = runtime.admin.fetchSession();
    final expectation = expectLater(request, throwsA(isA<DioException>()));
    await flushSangong(tester);
    runtime.updateContext(sangongTestContext(api, capabilityVersion: 2));
    gate.complete({'status': 'running', 'round': null});
    await flushSangong(tester);
    await expectation;
  });

  testWidgets('pinned wrapper preserves discovery and report query options',
      (tester) async {
    final api = SangongTestApi();
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    await completeSangongRequest(tester, runtime.admin.fetchMyConfig());
    final tenant = expectedSangongRequestTenant(skipTenant: true);
    expect(
        api.calls.single.headers?.containsKey('X-Tenant-Id'), tenant != null);
    expect(api.calls.single.headers?['X-Tenant-Id'], tenant);
    expect(api.calls.single.useBearerAuth, isTrue);
    api.calls.clear();
    api.respond = (_) => sangongUserReport(imUserId: 'im-target');
    await completeSangongRequest(
        tester, runtime.admin.fetchUserFlowResult(imUserId: 'im-target'));
    expect(api.calls.single.headers?['X-Tenant-Id'],
        expectedSangongRequestTenant());
    expect(api.calls.single.query?['imUserId'], 'im-target');
  });
}
