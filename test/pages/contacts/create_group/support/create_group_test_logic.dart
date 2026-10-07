import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/pages/contacts/create_group/create_group_logic.dart';
import 'package:openim/pages/contacts/create_group/create_group_default_name.dart';

/// Owns editable test state without starting SDK or contact-picker requests.
class CreateGroupTestLogic extends GetxController implements CreateGroupLogic {
  CreateGroupTestLogic({List<UserInfo> members = const [], String name = ''}) {
    nameCtrl.text = name;
    allList.assignAll(members);
  }

  @override
  final nameCtrl = TextEditingController();
  @override
  final faceURL = ''.obs;
  @override
  final allList = <UserInfo>[].obs;
  @override
  final checkedList = <UserInfo>[];
  @override
  final defaultCheckedList = <UserInfo>[];

  final memberOperations = <bool>[];
  final submittedNames = <String>[];
  final submittedMembers = <List<String>>[];
  int avatarSelections = 0;
  List<UserInfo>? membersAfterSelection;
  Completer<void>? creationGate;
  bool failCreation = false;

  @override
  String get groupName => nameCtrl.text.trim();

  @override
  String get defaultGroupName => defaultCreateGroupName(allList.toList());

  @override
  void selectAvatar() => avatarSelections++;

  @override
  void opMember({bool isDel = false}) {
    memberOperations.add(isDel);
    if (membersAfterSelection case final members?) {
      allList.assignAll(members);
      membersAfterSelection = null;
    }
  }

  @override
  Future<void> completeCreation() async {
    submittedNames.add(nameCtrl.text);
    submittedMembers.add(allList.map((member) => member.userID!).toList());
    if (creationGate case final gate?) await gate.future;
    if (failCreation) throw StateError('creation unavailable');
  }

  @override
  int length() => allList.length;

  @override
  Widget itemBuilder({
    required int index,
    required Widget Function(UserInfo info) builder,
    required Widget Function() addButton,
    required Widget Function() delButton,
  }) =>
      builder(allList[index]);

  @override
  void onClose() {
    nameCtrl.dispose();
    super.onClose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

List<UserInfo> createGroupTestMembers(int count) => List.generate(
    count,
    (index) => UserInfo(
        userID: 'member-${index + 1}',
        nickname: '成员${(index + 1).toString().padLeft(2, '0')}'));
