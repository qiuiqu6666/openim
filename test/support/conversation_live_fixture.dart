import 'package:get/get.dart';
import 'package:openim/core/im_callback.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim/pages/conversation/conversation_organizer.dart';
import 'package:openim/pages/conversation/editing/conversation_read_batch.dart';
import 'package:openim/pages/conversation/summary/conversation_feed_snapshot.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';

/// Presentation tests have no logged-in business session. Real list status
/// networking is covered by the live-list integration fixtures separately.
mixin ConversationLiveFixture on GetxController {
  final activeFeedViews = <Object>{};
  void setFeedViewActive(Object owner, bool active) {
    active ? activeFeedViews.add(owner) : activeFeedViews.remove(owner);
  }
  void removeFeedView(Object owner) => activeFeedViews.remove(owner);
  final imStatus = IMSdkStatus.connectionSucceeded.obs;
  RxList<ConversationInfo> get list;
  bool isArchived(ConversationInfo info);
  String? folderID(ConversationInfo info);

  // Match the production feed projection, while keeping each fixture's own
  // archive/folder state as the source used by its interaction assertions.
  ConversationFeedSnapshot get feedSnapshot => ConversationFeedSnapshot(list, {
        for (final row in list)
          row.conversationID: ChatConversationState.fromJson({
            'conversationID': row.conversationID,
            'archived': isArchived(row),
            'folderID': folderID(row),
            'version': 0,
          }),
      });
  bool get canShowEmptyFeed => true;

  Future<void> onRefresh() async {}

  final markingAllRead = false.obs;
  final readBatchProgress = ''.obs;
  int readBatchFailures = 0;
  Future<void> markConversationRead(ConversationInfo info);

  Future<void> markAllConversationsRead(String scope) => markReadScope((info) =>
      scope == 'all' ||
      (scope == 'group' ? info.isGroupChat : info.isSingleChat));

  Future<void> markSelectedConversationsRead(List<String> ids) =>
      markReadScope((info) => ids.contains(info.conversationID));

  Future<void> markReadScope(bool Function(ConversationInfo) includes) async {
    if (markingAllRead.value) return;
    markingAllRead.value = true;
    try {
      readBatchFailures = await runConversationReadBatch(
        conversations: list.where(includes).toList(),
        isCurrent: () => !isClosed,
        markRead: markConversationRead,
        progress: (done, total) => readBatchProgress.value = '$done / $total',
      );
    } finally {
      markingAllRead.value = false;
      readBatchProgress.value = '';
    }
  }

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
