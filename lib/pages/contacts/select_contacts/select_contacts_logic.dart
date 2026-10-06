import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim_common/openim_common.dart';

import 'select_contacts_view.dart';
import 'recent_conversations/recent_conversation_preview_controller.dart';
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
  final checkedList = <String, dynamic>{}.obs;
  final defaultCheckedIDList = <String>{}.obs;
  List<String>? excludeIDList;
  late SelAction action;
  late bool openSelectedSheet;
  String? groupID;
  final conversationList = <ConversationInfo>[].obs;
  String? ex;
  UserInfo? sharedContact;
  String? cardRecipientName;
  String? cardRecipientFaceURL;
  bool cardRecipientIsGroup = false;
  final inputCtrl = TextEditingController();
  bool _confirmingCard = false;
  RecentConversationPreviewController? _recentPreviews;
  RecentConversationPreviewController get recentPreviews =>
      _recentPreviews ??= RecentConversationPreviewController();

  @override
  void onInit() {
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
    sharedContact = Get.arguments['sharedContact'];
    cardRecipientName = Get.arguments['cardRecipientName'];
    cardRecipientFaceURL = Get.arguments['cardRecipientFaceURL'];
    cardRecipientIsGroup = Get.arguments['cardRecipientIsGroup'] == true;
    super.onInit();
  }

  @override
  void onClose() {
    _recentPreviews?.dispose();
    inputCtrl.dispose();
    super.onClose();
  }

  @override
  void onReady() {
    _queryConversationList();
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

  bool allowsSelection(Object? info) => _selectingGroupMembers
      ? ContactSelectionPolicy.allowsGroupMember(info)
      : ContactSelectionPolicy.allows(info);

  bool allowsUserID(String userID) => _selectingGroupMembers
      ? ContactSelectionPolicy.allowsGroupMemberUserID(userID)
      : ContactSelectionPolicy.allowsUserID(userID);

  bool isVisible(Object? info) => _selectingGroupMembers
      ? allowsSelection(info)
      : ContactSelectionPolicy.allowsVisible(info,
          showNotificationAccounts: action == SelAction.forward);

  _queryConversationList() async {
    if (!hiddenConversations) {
      final cons = Get.find<ConversationLogic>().list;

      final futures = cons.map((con) async {
        if (!isVisible(con)) return null;
        if (con.isGroupChat) {
          final result = await OpenIM.iMManager.groupManager
              .isJoinedGroup(groupID: con.groupID!);
          return result ? con : null;
        }
        return con.conversationType == ConversationType.notification
            ? null
            : con;
      }).toList();

      final results = await Future.wait(futures);
      final filteredCons =
          results.where((con) => con != null).cast<ConversationInfo>().toList();

      conversationList.addAll(filteredCons);
    }
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

  confirmSelectedList() async {
    _removeUnavailableSelections();
    if (action == SelAction.recommend &&
        sharedContact != null &&
        !allowsSelection(sharedContact)) {
      return;
    }
    if (action == SelAction.forward || action == SelAction.recommend) {
      final recipients = checkedList.values.toList();
      if (recipients.isEmpty) return;
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
                  checkedList: checkedList.values.toList(),
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
      if (sure == true) {
        _removeUnavailableSelections();
        if (checkedList.isEmpty) return;
        Get.back(result: {
          "checkedList": checkedList.values,
        });
      }
    } else {
      Get.back(result: Map<String, dynamic>.from(checkedList));
    }
  }

  Future<void> confirmSelectedItem(dynamic info) async {
    if (!allowsSelection(info)) return;
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
