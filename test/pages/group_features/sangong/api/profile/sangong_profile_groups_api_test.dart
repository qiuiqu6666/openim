import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/sangong/api/profile/sangong_profile_groups_api.dart';
import '../../sangong_test_support.dart';

void main() {
  for (final role in ['owner', 'admin']) {
    test('discovers the configured group for $role without joined groups',
        () async {
      final api = SangongTestApi()
        ..respond = (_) => {
              'tenants': [
                {
                  'imGroupGameId': 'game',
                  'name': '游戏群',
                  'myRole': role,
                  'active': true
                },
                {'imGroupGameId': 'disabled', 'myRole': role, 'active': false},
                {'imGroupGameId': 'unclaimed', 'myRole': '', 'active': true},
              ]
            };
      final groups = await SangongProfileGroupsApi(api).load();
      expect(groups.map((group) => group.groupID), ['game']);
      expect(groups.single.groupName, '游戏群');
      expect(api.calls.single.path, '/sangong/api/v1/admin/tenants');
      expect(api.calls.single.useBearerAuth, isTrue);
    });
  }
  test('malformed discovery cannot grant an unrelated group', () async {
    final api = SangongTestApi()
      ..respond = (_) => {
            'tenants': [{}, 'bad']
          };
    await expectLater(SangongProfileGroupsApi(api).load(),
        throwsA(isA<GroupFeatureException>()));
  });
}
