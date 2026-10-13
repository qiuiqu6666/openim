import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../core/controller/im_controller.dart';
import '../../../routes/app_navigator.dart';
import '../../../services/legacy_identity/legacy_group_identity.dart';
import '../../conversation/conversation_logic.dart';

enum JoinGroupMethod { search, qrcode, invite }

class GroupProfilePanelLogic extends GetxController {
  final conversationLogic = Get.find<ConversationLogic>();
  final imLogic = Get.find<IMController>();
  final isJoined = false.obs;
  final members = <GroupMembersInfo>[].obs;
  late Rx<GroupInfo> groupInfo;
  late JoinGroupMethod joinGroupMethod;

  final _subscriptions = <StreamSubscription>[];
  final _accountID = OpenIM.iMManager.userID;
  final _token = DataSp.chatToken;
  bool _closed = false;
  int _membershipRevision = 0;
  int _infoRevision = 0;
  int _membersRevision = 0;
  bool get _active =>
      !_closed &&
      !isClosed &&
      _accountID == OpenIM.iMManager.userID &&
      _token == DataSp.chatToken;

  @override
  void onInit() {
    groupInfo = Rx(GroupInfo(
        groupID:
            LegacyGroupIdentity.canonical(Get.arguments['groupID'] as String)));
    joinGroupMethod = Get.arguments['joinGroupMethod'];
    _subscriptions.addAll([
      imLogic.groupApplicationChangedSubject.listen(_onChanged),
      imLogic.joinedGroupAddedSubject.listen(_onChanged),
      imLogic.memberAddedSubject.listen(_onChanged),
      imLogic.joinedGroupDeletedSubject.listen((group) {
        if (_active && group.groupID == groupInfo.value.groupID) {
          _setJoined(false);
        }
      }),
      imLogic.memberDeletedSubject.listen((member) {
        if (_active &&
            member.groupID == groupInfo.value.groupID &&
            member.userID == _accountID) {
          _setJoined(false);
        }
      }),
      imLogic.groupInfoUpdatedSubject.listen((group) {
        if (_active && group.groupID == groupInfo.value.groupID) {
          ++_infoRevision;
          groupInfo.value = group;
          if (group.status == 2) _setJoined(false);
        }
      }),
    ]);
    unawaited(_checkGroup());
    unawaited(_getGroupInfo());
    unawaited(_getMembers());
    super.onInit();
  }

  void _onChanged(dynamic value) {
    if (!_active) return;
    if (value is GroupApplicationInfo) {
      if (value.groupID == groupInfo.value.groupID &&
          value.userID == _accountID &&
          value.handleResult == 1) {
        _setJoined(true);
      }
    } else if (value is GroupInfo) {
      if (value.groupID == groupInfo.value.groupID) {
        _setJoined(true);
      }
    } else if (value is GroupMembersInfo) {
      if (value.groupID == groupInfo.value.groupID &&
          value.userID == _accountID) {
        _setJoined(true);
      }
    }
  }

  void _setJoined(bool joined) {
    ++_membershipRevision;
    ++_membersRevision;
    isJoined.value = joined;
    if (!joined) {
      members.clear();
      return;
    }
    unawaited(_getGroupInfo());
    unawaited(_getMembers());
  }

  Future<void> _getGroupInfo() async {
    final revision = ++_infoRevision;
    try {
      final list = await OpenIM.iMManager.groupManager.getGroupsInfo(
        groupIDList: [groupInfo.value.groupID],
      );
      if (!_active || revision != _infoRevision) return;
      final info =
          list.firstWhereOrNull((g) => g.groupID == groupInfo.value.groupID);
      if (null != info) {
        groupInfo.value = info;
        if (info.status == 2) _setJoined(false);
      }
    } catch (_) {
      if (_active) Logger.print('Group profile metadata is unavailable');
    }
  }

  Future<void> _checkGroup() async {
    final revision = ++_membershipRevision;
    try {
      final joined = await OpenIM.iMManager.groupManager.isJoinedGroup(
        groupID: groupInfo.value.groupID,
      );
      if (_active && revision == _membershipRevision) isJoined.value = joined;
    } catch (_) {
      if (_active) Logger.print('Group profile membership is unavailable');
    }
  }

  Future<void> _getMembers() async {
    final revision = ++_membersRevision;
    try {
      final list = await OpenIM.iMManager.groupManager.getGroupMemberList(
        groupID: groupInfo.value.groupID,
        count: 10,
      );
      if (_active && revision == _membersRevision) members.assignAll(list);
    } catch (_) {
      if (_active) Logger.print('Group profile members are unavailable');
    }
  }

  Future<void> enterGroup() async {
    if (!_active) return;
    if (isJoined.value) {
      conversationLogic.toChat(
        groupID: groupInfo.value.groupID,
        nickname: groupInfo.value.groupName,
        faceURL: groupInfo.value.faceURL,
        sessionType: groupInfo.value.sessionType,
      );
    } else {
      AppNavigator.startSendVerificationApplication(
        groupID: groupInfo.value.groupID,
        joinGroupMethod: joinGroupMethod,
      );
    }
  }

  @override
  void onClose() {
    _closed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    super.onClose();
  }
}
