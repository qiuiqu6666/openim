import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim_common/openim_common.dart';

import 'select_contacts_view.dart';
import 'recent_conversations/recent_conversation_preview_controller.dart';
import 'recent_conversations/recent_conversation_directory.dart';
import 'recent_conversations/recent_membership_cache.dart';
import 'selection/contact_selection_policy.dart';
import '../../official_account/widgets/official_account_name_label.dart';

enum SelAction {
  forward,

  carte,

  crateGroup,

  addMember,

  recommend,
}

class SelectContactsLogic extends GetxController
    implements OrganizationMultiSelBridge {
  SelectContactsLogic({Future<bool> Function(String)? isJoinedGroup})
      : _onPicked = null,
        _selectionCurrent = null,
        _recentDirectory = RecentConversationDirectory(isJoinedGroup ??
            ((id) => OpenIM.iMManager.groupManager.isJoinedGroup(groupID: id)));

  /// Reuses the existing single-contact/group pages without a send dialog.
  /// This controller is owned by the caller, not registered over an active
  /// forwarding controller in Get's global registry.
  SelectContactsLogic.single({
    required ValueChanged<Object> onPicked,
    required bool Function() isCurrent,
  })  : _onPicked = onPicked,
        _selectionCurrent = isCurrent,
        _recentDirectory = RecentConversationDirectory(
            (id) => OpenIM.iMManager.groupManager.isJoinedGroup(groupID: id)) {
    action = SelAction.carte;
    openSelectedSheet = false;
  }

  final ValueChanged<Object>? _onPicked;
  final bool Function()? _selectionCurrent;
  bool get isSingleSelection => _onPicked != null;
  late final _accountID = OpenIM.iMManager.userID;
  late final _sessionToken = DataSp.chatToken;
  bool get selectionCurrent =>
      !isClosed &&
      _accountID == OpenIM.iMManager.userID &&
      _sessionToken == DataSp.chatToken &&
      (_selectionCurrent?.call() ?? true);
  final checkedList = <String, dynamic>{}.obs;
  final defaultCheckedIDList = <String>{}.obs;
  List<String>? excludeIDList;
  late SelAction action;
  late bool openSelectedSheet;
  String? groupID;
  final conversationList = <ConversationInfo>[].obs;
  final recentLoading = false.obs;
  final recentLoadFailed = false.obs;
  final RecentConversationDirectory _recentDirectory;
  int _recentGeneration = 0;
  final _confirmingSelection = false.obs;
  final _localMembershipCache = RecentMembershipCache();
  RecentMembershipCache get _membershipCache =>
      Get.isRegistered<ConversationLogic>()
          ? RecentMembershipCache.forSession(
              Get.find<ConversationLogic>(), _accountID, _sessionToken)
          : _localMembershipCache;
  String? ex;
  ForwardPreviewData? forwardPreview;
  UserInfo? sharedContact;
  String? cardRecipientName;
  String? cardRecipientFaceURL;
  bool cardRecipientIsGroup = false;
  final inputCtrl = TextEditingController();
  final recentScrollController = ScrollController();
  final conversationSearch = ''.obs;

  List<ConversationInfo> get visibleConversations {
    final query = conversationSearch.value;
    if (query.isEmpty) return conversationList;
    return conversationList
        .where((info) => (info.showName ?? '').toLowerCase().contains(query))
        .toList(growable: false);
  }

  void searchConversations(String value) {
    final query = graphemeTrim(value).toLowerCase();
    if (query == conversationSearch.value) return;
    conversationSearch.value = query;
    if (recentScrollController.hasClients) recentScrollController.jumpTo(0);
  }

  bool _confirmingCard = false;
  RecentConversationPreviewController? _recentPreviews;
  RecentConversationPreviewController get recentPreviews =>
      _recentPreviews ??= RecentConversationPreviewController();

  @override
  void onInit() {
    // Routes bind after login; constructing an unmounted picker needs no SDK.
    _accountID;
    _sessionToken;
    if (isSingleSelection) {
      super.onInit();
      return;
    }
    action = Get.arguments['action'];
    groupID = Get.arguments['groupID'];
    excludeIDList = Get.arguments['excludeIDList'];
    defaultCheckedIDList.addAll(
        List<String>.from(Get.arguments['defaultCheckedIDList'] ?? [])
            .where(allowsUserID));
    checkedList.addAll(Get.arguments['checkedList'] ?? {});
    _removeUnavailableSelections();
    openSelectedSheet = Get.arguments['openSelectedSheet'];
    ex = Get.arguments['ex'];
    forwardPreview = Get.arguments['forwardPreview'];
    sharedContact = Get.arguments['sharedContact'];
    cardRecipientName = Get.arguments['cardRecipientName'];
    cardRecipientFaceURL = Get.arguments['cardRecipientFaceURL'];
    cardRecipientIsGroup = Get.arguments['cardRecipientIsGroup'] == true;
    super.onInit();
  }

  @override
  void onClose() {
    ++_recentGeneration;
    _recentPreviews?.dispose();
    inputCtrl.dispose();
    recentScrollController.dispose();
    super.onClose();
  }

  @override
  void onReady() {
    unawaited(reloadRecentConversations());
    if (openSelectedSheet) viewSelectedContactsList();
    super.onReady();
  }

  @override
  bool get isMultiModel => action != SelAction.carte;

  bool get hiddenGroup =>
      action == SelAction.carte ||
      action == SelAction.crateGroup ||
      action == SelAction.addMember;

  bool get hiddenConversations =>
      action == SelAction.carte ||
      action == SelAction.crateGroup ||
      action == SelAction.addMember;

  bool get _selectingGroupMembers =>
      action == SelAction.crateGroup || action == SelAction.addMember;

  bool allowsSelection(Object? info) => isSingleSelection
      ? selectionCurrent && parseID(info)?.trim().isNotEmpty == true
      : _selectingGroupMembers
          ? ContactSelectionPolicy.allowsGroupMember(info)
          : ContactSelectionPolicy.allows(info);

  bool allowsUserID(String userID) => isSingleSelection
      ? selectionCurrent && userID.trim().isNotEmpty
      : _selectingGroupMembers
          ? ContactSelectionPolicy.allowsGroupMemberUserID(userID)
          : ContactSelectionPolicy.allowsUserID(userID);

  bool isVisible(Object? info) => isSingleSelection || _selectingGroupMembers
      ? allowsSelection(info)
      : ContactSelectionPolicy.allowsVisible(info,
          showNotificationAccounts: action == SelAction.forward);

  Future<void> reloadRecentConversations() async {
    if (!selectionCurrent ||
        hiddenConversations ||
        _confirmingSelection.value) {
      return;
    }
    final generation = ++_recentGeneration;
    bool current() => selectionCurrent && generation == _recentGeneration;
    recentLoading.value = true;
    recentLoadFailed.value = false;
    try {
      final result = await _recentDirectory.load(
        List<ConversationInfo>.of(Get.find<ConversationLogic>().list),
        isVisible: isVisible,
        isCurrent: current,
        cache: _membershipCache,
        onUpdate: (rows) {
          if (current()) conversationList.assignAll(rows);
        },
        onExcluded: _excludeRecentGroup,
      );
      if (!current()) return;
      recentLoadFailed.value = result.failed;
    } catch (_) {
      if (current()) recentLoadFailed.value = true;
    } finally {
      if (current()) recentLoading.value = false;
    }
  }

  void _excludeRecentGroup(String groupID) {
    if (!selectionCurrent) return;
    conversationList.removeWhere((row) => row.groupID == groupID);
    checkedList.removeWhere(
        (_, info) => IMUtils.convertCheckedToGroupID(info) == groupID);
  }

  static String? parseID(e) {
    if (e is ConversationInfo) {
      return e.isSingleChat ? e.userID : e.groupID;
    } else if (e is GroupInfo) {
      return e.groupID;
    } else if (e is UserInfo || e is FriendInfo || e is UserFullInfo) {
      return e.userID;
    } else {
      return null;
    }
  }

  static String? parseName(e) {
    if (e is ConversationInfo) {
      return e.showName;
    } else if (e is GroupInfo) {
      return e.groupName;
    } else if (e is UserInfo || e is FriendInfo || e is UserFullInfo) {
      return e.nickname;
    } else {
      return null;
    }
  }

  static String? parseFaceURL(e) {
    if (e is ConversationInfo) {
      return e.faceURL;
    } else if (e is GroupInfo) {
      return e.faceURL;
    } else if (e is UserInfo || e is FriendInfo || e is UserFullInfo) {
      return e.faceURL;
    } else {
      return null;
    }
  }

  @override
  bool isChecked(info) =>
      allowsSelection(info) && checkedList.containsKey(parseID(info));

  @override
  bool isDefaultChecked(info) => defaultCheckedIDList.contains(parseID(info));

  @override
  Function()? onTap(dynamic info) =>
      !allowsSelection(info) || isDefaultChecked(info)
          ? null
          : () => toggleChecked(info);

  @override
  removeItem(dynamic info) {
    checkedList.remove(parseID(info));
  }

  @override
  toggleChecked(dynamic info) {
    if (!allowsSelection(info)) return;
    if (isMultiModel) {
      final key = parseID(info);
      if (checkedList.containsKey(key)) {
        checkedList.remove(key);
      } else {
        checkedList.putIfAbsent(key ?? '', () => info);
      }
    } else {
      confirmSelectedItem(info);
    }
  }

  @override
  updateDefaultCheckedList(List<String> userIDList) async {
    if (groupID != null) {
      var list = await OpenIM.iMManager.groupManager.getGroupMembersInfo(
        groupID: groupID!,
        userIDList: userIDList,
      );
      defaultCheckedIDList
          .addAll(list.where(allowsSelection).map((e) => e.userID!));
    }
  }

  String get checkedStrTips => checkedList.values.map(parseName).join('、');

  viewSelectedContactsList() => Get.bottomSheet(
        SelectedContactsListView(),
        isScrollControlled: true,
      );

  selectFromMyFriend() async {
    final result = await AppNavigator.startSelectContactsFromFriends();
    if (null != result) {
      Get.back(result: result);
    }
  }

  selectFromMyGroup() async {
    final result = await AppNavigator.startSelectContactsFromGroup();
    if (null != result) {
      Get.back(result: result);
    }
  }

  selectTagGroup() async {
    final result = await await AppNavigator.startSelectContactsFromTag();
    if (null != result) {
      Get.back(result: result);
    }
  }

  Future<void> confirmSelectedList() async {
    if (!enabledConfirmButton || !selectionCurrent) return;
    final resumeLoading = recentLoading.value;
    // Confirmation owns the selected recipients. Unrelated directory checks
    // must neither delay it nor change its selection while the dialog is open.
    ++_recentGeneration;
    recentLoading.value = false;
    _confirmingSelection.value = true;
    var submitted = false;
    try {
      submitted = await _confirmSelectedList();
    } finally {
      if (!isClosed) {
        _confirmingSelection.value = false;
        if (!submitted &&
            selectionCurrent &&
            (resumeLoading || recentLoadFailed.value)) {
          unawaited(reloadRecentConversations());
        }
      }
    }
  }

  Future<bool> _confirmSelectedList() async {
    _removeUnavailableSelections();
    if (action == SelAction.recommend &&
        sharedContact != null &&
        !allowsSelection(sharedContact)) {
      return false;
    }
    if (action == SelAction.forward || action == SelAction.recommend) {
      final recipients = checkedList.values.toList();
      if (recipients.isEmpty) return false;
      final contact = sharedContact;
      final sure =
          await Get.dialog(action == SelAction.recommend && contact != null
              ? ContactCardSendDialog(
                  name: contact.nickname?.trim().isNotEmpty == true
                      ? contact.nickname!
                      : contact.userID ?? '',
                  faceURL: contact.faceURL,
                  recipientName: recipients
                      .map((item) => parseName(item) ?? parseID(item) ?? '')
                      .join('、'),
                  recipientFaceURL: parseFaceURL(recipients.first),
                  recipientIsGroup:
                      IMUtils.convertCheckedToGroupID(recipients.first) != null,
                  recipients: recipients
                      .map((item) => (
                            name: parseName(item) ?? parseID(item) ?? '',
                            faceURL: parseFaceURL(item),
                            isGroup:
                                IMUtils.convertCheckedToGroupID(item) != null,
                          ))
                      .toList(),
                )
              : ForwardHintDialog(
                  title: ex ?? '',
                  preview: forwardPreview,
                  checkedList: recipients,
                  nameMinHeight:
                      recipients.any(ContactSelectionPolicy.hasVerifiedIdentity)
                          ? 16
                          : 0,
                  nameBuilder: (context, info, style) =>
                      OfficialAccountNameLabel(
                    name: parseName(info) ?? parseID(info) ?? '',
                    userID: parseID(info),
                    ex: ContactSelectionPolicy.userExtension(info),
                    isSingleChat: IMUtils.convertCheckedToGroupID(info) == null,
                    style: style,
                  ),
                ));
      if (sure == true && selectionCurrent) {
        // Visible recipients can proceed immediately. The actual send handles
        // membership errors; another SDK lookup here can block on sync/offline.
        _removeUnavailableSelections();
        if (recipients.any((info) =>
            !allowsSelection(info) ||
            !checkedList.containsKey(parseID(info)))) {
          return false;
        }
        Get.back(result: {
          "checkedList": recipients,
        });
        return true;
      }
    } else {
      Get.back(result: Map<String, dynamic>.from(checkedList));
      return true;
    }
    return false;
  }

  Future<void> confirmSelectedItem(dynamic info) async {
    if (!allowsSelection(info)) return;
    if (isSingleSelection) {
      _onPicked!(info as Object);
      return;
    }
    if (action == SelAction.carte) {
      if (isClosed ||
          _confirmingCard ||
          parseID(info)?.trim().isNotEmpty != true) {
        return;
      }
      _confirmingCard = true;
      try {
        final sure = await Get.dialog<bool>(
            ContactCardSendDialog(
              name: parseName(info)?.trim().isNotEmpty == true
                  ? parseName(info)!.trim()
                  : parseID(info)!,
              faceURL: parseFaceURL(info),
              recipientName: cardRecipientName?.trim().isNotEmpty == true
                  ? cardRecipientName!.trim()
                  : 'thisChat'.tr,
              recipientFaceURL: cardRecipientFaceURL,
              recipientIsGroup: cardRecipientIsGroup,
            ),
            barrierDismissible: false);
        if (sure == true && !isClosed && allowsSelection(info)) {
          Get.back(result: UserInfo.fromJson(info.toJson()));
        }
      } finally {
        _confirmingCard = false;
      }
    }
  }

  void _removeUnavailableSelections() =>
      checkedList.removeWhere((_, info) => !allowsSelection(info));

  bool get enabledConfirmButton =>
      !_confirmingSelection.value &&
      checkedList.values.any(allowsSelection) &&
      (action != SelAction.recommend ||
          sharedContact == null ||
          allowsSelection(sharedContact));

  @override
  Widget get checkedConfirmView => isMultiModel
      ? ColoredBox(
          color: Styles.c_FFFFFF,
          child: SafeArea(top: false, child: CheckedConfirmView()),
        )
      : const SizedBox();
}
