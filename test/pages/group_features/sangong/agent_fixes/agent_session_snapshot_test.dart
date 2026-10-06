import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import '../sangong_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a current agent snapshot survives notifications of the same context',
      () {
    final api = SangongTestApi();
    final context = sangongTestContext(api);
    final runtime = SangongRuntime(context);
    addTearDown(runtime.dispose);
    final session = AgentSessionSnapshot(runtime);
    runtime.changed();
    runtime.updateContext(context);
    expect(session.isCurrent, isTrue);
  });

  test('an equivalent context refresh keeps the agent snapshot current', () {
    final api = SangongTestApi();
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    final session = AgentSessionSnapshot(runtime);
    runtime.updateContext(sangongTestContext(api));
    expect(runtime.canOpenAgent, isTrue);
    expect(session.isCurrent, isTrue);
    expect(AgentSessionSnapshot(runtime).isCurrent, isTrue);
  });

  test(
      'an expired original capability epoch cannot revive with the same grants',
      () {
    final api = SangongTestApi();
    var originalCapabilitiesCurrent = true;
    final runtime = SangongRuntime(sangongTestContext(api,
        capabilitiesCurrent: () => originalCapabilitiesCurrent));
    addTearDown(runtime.dispose);
    final session = AgentSessionSnapshot(runtime);
    originalCapabilitiesCurrent = false;
    runtime.updateContext(sangongTestContext(api));
    expect(runtime.canOpenAgent, isTrue);
    expect(session.isCurrent, isFalse);
    expect(AgentSessionSnapshot(runtime).isCurrent, isTrue);
  });

  test('a same-group capability update preserving access expires old snapshots',
      () {
    final api = SangongTestApi();
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    final session = AgentSessionSnapshot(runtime);
    runtime.updateContext(sangongTestContext(api, capabilityVersion: 2));
    expect(runtime.canOpenAgent, isTrue);
    expect(session.isCurrent, isFalse);
  });

  test('a changed confirmed tenant expires an agent snapshot without logout',
      () {
    final api = SangongTestApi();
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    final session = AgentSessionSnapshot(runtime);
    runtime.http.setTenantId('tenant-other');
    expect(runtime.canOpenAgent, isTrue);
    expect(session.isCurrent, isFalse);
  });

  test('the snapshot pins environment, account, group and API identity', () {
    final originalApi = SangongTestApi();
    for (final next in [
      sangongTestContext(originalApi, userID: 'another-user'),
      sangongTestContext(originalApi, groupID: 'another-group'),
      sangongTestContext(SangongTestApi()),
    ]) {
      final runtime = SangongRuntime(sangongTestContext(originalApi));
      final session = AgentSessionSnapshot(runtime);
      runtime.updateContext(next);
      expect(runtime.canOpenAgent, isTrue);
      expect(session.isCurrent, isFalse);
      runtime.dispose();
    }
  });

  test('permission values are pinned even if a raw grant map mutates in place',
      () {
    final api = SangongTestApi();
    final base = sangongTestContext(api);
    final raw = <String, dynamic>{'canManageMembers': true};
    final context = GroupFeatureContext(
      groupID: base.groupID,
      groupName: base.groupName,
      currentUserID: base.currentUserID,
      api: api,
      accountPrivilege: base.privilege,
      features: base.features,
      capabilities: GroupFeatureCapabilities(
        version: 1,
        sangong: GroupGameCapabilities(
          canConfigure: true,
          canManage: true,
          canOpenAgent: true,
          canViewRebateHistory: true,
          tenantID: 'tenant-authorized',
          raw: raw,
        ),
      ),
      sessionCurrent: () => true,
      capabilitiesCurrent: () => true,
      onFeaturesChanged: (_) {},
    );
    final runtime = SangongRuntime(context);
    addTearDown(runtime.dispose);
    final session = AgentSessionSnapshot(runtime);
    raw['canManageMembers'] = false;
    expect(runtime.canOpenAgent, isTrue);
    expect(session.isCurrent, isFalse);
  });

  test('logout and disposal reject the snapshot', () {
    var current = true;
    final runtime = SangongRuntime(
        sangongTestContext(SangongTestApi(), current: () => current));
    final session = AgentSessionSnapshot(runtime);
    current = false;
    expect(session.isCurrent, isFalse);
    current = true;
    runtime.dispose();
    expect(session.isCurrent, isFalse);
  });
}
