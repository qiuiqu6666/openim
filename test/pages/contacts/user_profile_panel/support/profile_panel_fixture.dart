import 'package:get/get.dart';
import 'package:openim/pages/contacts/contacts_logic.dart';
import 'package:openim/pages/contacts/star_friend_store.dart';
import 'package:openim/pages/contacts/user_profile_panel/user_profile _panel_logic.dart';
import 'package:openim/services/moments_repository.dart';
import 'package:openim_common/openim_common.dart';

/// Profile state without constructing SDK controllers or registering listeners.
class ProfilePanelFixture extends GetxController
    implements UserProfilePanelLogic {
  ProfilePanelFixture({
    bool friend = true,
    this.self = false,
    this.group = false,
    this.allowMessaging = true,
    UserFullInfo? user,
  }) : userInfo = (user ??
                UserFullInfo(
                  userID: 'sdk-internal-peer-id',
                  account: 'public_peer_1024',
                  nickname: '小林',
                  remark: '周末咖啡搭子',
                  gender: 2,
                  allowAddFriend: 1,
                  ex: '{"signature":"生活很慢，咖啡很香。"}',
                  isFriendship: friend,
                ))
            .obs;

  final bool self;
  final bool group;
  @override
  String? get groupID => group ? 'fixture-group' : null;
  final bool allowMessaging;
  final groupAccount = RxnString('public_peer_1024');
  final actions = <String>[];
  final blacklistRequests = <bool>[];
  final copiedIds = <String>[];
  @override
  final profileLayoutReady = true.obs;
  @override
  final initialProfileFailed = false.obs;

  @override
  Future<void> retryInitialProfile() async {
    actions.add('retryInitialProfile');
    initialProfileFailed.value = false;
  }

  @override
  final Rx<UserFullInfo> userInfo;
  @override
  bool get isMyself => self;
  @override
  bool get isFriendship => userInfo.value.isFriendship;
  @override
  bool get isGroupMemberPage => group;
  final activeGroupContext = true.obs;
  @override
  bool get hasActiveGroupMemberContext => activeGroupContext.value;
  final friendAddEntry = true.obs;
  @override
  bool get hasFriendAddEntry => friendAddEntry.value;
  @override
  final preparingFriendAdd = false.obs;
  @override
  bool get canPrepareFriendAdd =>
      hasFriendAddEntry ||
      (!isGroupMemberPage &&
          normalizePublicAccountSearch(displayedUserID) != null);
  @override
  bool get isAllowAddFriend => userInfo.value.allowAddFriend == 1;
  @override
  bool get allowSendMsgNotFriend => allowMessaging;
  @override
  bool? forceCanAdd = false;
  @override
  final iAmOwner = false.obs;
  @override
  final iHaveAdminOrOwnerPermission = false.obs;
  @override
  final notAllowAddGroupMemberFriend = false.obs;
  @override
  final notAllowLookGroupMemberProfiles = false.obs;
  @override
  final updatingBlacklist = false.obs;
  @override
  final commonGroupCount = RxnInt(3);
  @override
  final loadingCommonGroups = false.obs;
  @override
  final commonGroupsFailed = false.obs;
  @override
  final joinGroupTime = 0.obs;
  @override
  final joinGroupMethod = ''.obs;
  @override
  final inviterID = ''.obs;
  @override
  final inviterName = ''.obs;
  @override
  final groupUserNickname = ''.obs;
  @override
  bool get showMemberIMID => false;
  @override
  String get displayedUserID => isGroupMemberPage
      ? groupAccount.value ?? ''
      : userInfo.value.account ?? '';

  @override
  void callDirectly({required bool video}) =>
      actions.add(video ? 'video' : 'voice');
  @override
  void toChat() => actions.add('chat');
  @override
  void addFriend() => actions.add('add');
  @override
  void copyID() {
    actions.add('copy');
    copiedIds.add(displayedUserID);
  }

  @override
  Future<void> editRemark() async => actions.add('remark');
  @override
  Future<void> openCommonGroups() async => actions.add('commonGroups');
  @override
  Future<void> loadCommonGroupCount() async => actions.add('commonGroupsRetry');
  @override
  Future<void> setChatBackground() async => actions.add('background');
  @override
  void viewInviter() => actions.add('inviter');
  @override
  void viewPersonalInfo() => actions.add('personalInfo');
  @override
  void friendSetup() => actions.add('more');
  @override
  Future<void> setBlacklist(bool enabled) async {
    if (updatingBlacklist.value) return;
    blacklistRequests.add(enabled);
    userInfo.update((user) => user?.isBlacklist = enabled);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ProfileStarStore extends StarFriendStore {
  final toggledIds = <String>[];

  @override
  Future<void> toggle(String id) async {
    toggledIds.add(id);
    apply(StarFriend.fromJson({
      'friendUserID': id,
      'starred': !isStarred(id),
      'version': (records[id]?.version ?? 0) + 1,
      'updatedAt': 1,
    }));
  }
}

class ProfileContactsFixture extends GetxController implements ContactsLogic {
  @override
  bool get isCurrentSession => true;
  @override
  final friends = <ISUserInfo>[].obs;
  @override
  final ProfileStarStore stars = ProfileStarStore();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ProfileMomentsApi extends MomentsApi {
  @override
  Future<MomentsCapabilities> capabilities() async =>
      MomentsCapabilities.fromJson({'supportsMoments': true});

  @override
  Future<MomentsSettings> settings() async => const MomentsSettings();
}

class ProfilePrivacyStore extends MomentsPrivacySelectionStore {
  ProfilePrivacyStore(this.value);
  MomentsPrivacySelections value;

  @override
  Future<MomentsPrivacySelections> load({
    required String ownerUserId,
    required String baseUrl,
  }) async =>
      value;

  @override
  Future<MomentsPrivacySelections> apply({
    required String ownerUserId,
    required String baseUrl,
    required List<MomentsPrivacyChange> changes,
  }) async =>
      value = value.apply(changes);
}

MomentsRepository profileMomentsRepository({
  String peerUserId = 'sdk-internal-peer-id',
  MomentsPrivacySelections selections = MomentsPrivacySelections.empty,
}) =>
    MomentsRepository(
      api: ProfileMomentsApi(),
      userIdProvider: () => 'profile-test-owner',
      environmentProvider: () => 'https://profile-preview.example',
      friendLoader: () async =>
          [MomentUser(userId: peerUserId, nickname: '小林')],
      privacySelectionStore: ProfilePrivacyStore(selections),
      subscribeToSdk: false,
    );
