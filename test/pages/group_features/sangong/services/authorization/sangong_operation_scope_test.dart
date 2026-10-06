import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'package:openim/pages/group_features/sangong/services/authorization/sangong_operation_scope.dart';

import '../../sangong_test_support.dart';

void main() {
  test('revocation then regrant cannot revive an original operation scope', () {
    final api = SangongTestApi();
    final context = sangongTestContext(api);
    final scope = SangongOperationScope.capture(context, 'tenant-authorized');
    api.privilege.setAllowed(false);
    expect(scope.matches(context, 'tenant-authorized'), isFalse);
    api.privilege.setAllowed(true);
    expect(scope.matches(context, 'tenant-authorized'), isFalse);
    expect(
        SangongOperationScope.capture(context, 'tenant-authorized')
            .matches(context, 'tenant-authorized'),
        isTrue);
  });

  test(
      'same semantic authorization accepts rebuilt context and unrelated revision',
      () {
    final api = SangongTestApi();
    final initial = sangongTestContext(api);
    final scope = SangongOperationScope.capture(initial, 'tenant-authorized');
    final rebuilt = GroupFeatureContext(
        groupID: initial.groupID,
        groupName: '改名后的群',
        currentUserID: initial.currentUserID,
        api: api,
        accountPrivilege: initial.privilege,
        features: GroupFeatures(
            valid: true, revision: 99, sangong: initial.features.sangong),
        capabilities: initial.capabilities,
        sessionCurrent: () => true,
        capabilitiesCurrent: () => true,
        onFeaturesChanged: (_) {});
    expect(scope.matches(rebuilt, 'tenant-authorized'), isTrue);
  });

  test('tenant or capability change with same operator role rejects old scope',
      () {
    final api = SangongTestApi();
    final initial = sangongTestContext(api);
    final scope = SangongOperationScope.capture(initial, 'tenant-authorized');
    expect(
        scope.matches(
            sangongTestContext(api, tenantID: 'tenant-B'), 'tenant-B'),
        isFalse);
    expect(
        scope.matches(
            sangongTestContext(api, capabilityVersion: 2), 'tenant-authorized'),
        isFalse);
  });

  for (final dimension in ['session', 'capabilities']) {
    test(
        'invalidated original $dimension epoch rejects a fresh matching context',
        () {
      var originalCurrent = true;
      final api = SangongTestApi();
      final initial = sangongTestContext(api,
          current: dimension == 'session' ? () => originalCurrent : () => true,
          capabilitiesCurrent:
              dimension == 'capabilities' ? () => originalCurrent : () => true);
      final scope = SangongOperationScope.capture(initial, 'tenant-authorized');
      originalCurrent = false;
      expect(
          scope.matches(sangongTestContext(api), 'tenant-authorized'), isFalse);
    });
  }
}
