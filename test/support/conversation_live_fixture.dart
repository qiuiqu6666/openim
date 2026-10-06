import 'package:get/get.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';

/// Presentation tests have no logged-in business session. Real list status
/// networking is covered by the live-list integration fixtures separately.
mixin ConversationLiveFixture on GetxController {
  bool get canShowEmptyFeed => true;

  Future<void> onRefresh() async {}

  final groupFeatures = GroupFeatureStore(
    api: GroupFeatureApi(
      baseUrl: 'https://fixture.example',
      tokenProvider: () => '',
      userProvider: () => '',
    ),
    sessionCurrent: () => false,
    fetchGroups: (_) async => [],
  );

  @override
  void onClose() {
    groupFeatures.dispose();
    super.onClose();
  }
}
