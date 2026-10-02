import 'package:azlistview/azlistview.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../../contacts_logic.dart';
import '../../presence_label.dart';
import '../select_contacts_logic.dart';
import 'friend_list_logic.dart';

class GroupContactPicker extends StatefulWidget {
  const GroupContactPicker(
      {super.key, required this.friends, required this.selection});
  final SelectContactsFromFriendsLogic friends;
  final SelectContactsLogic selection;
  @override
  State<GroupContactPicker> createState() => _GroupContactPickerState();
}

class _GroupContactPickerState extends State<GroupContactPicker> {
  final search = TextEditingController();
  final visible = <String>{};
  late final contacts =
      Get.isRegistered<ContactsLogic>() ? Get.find<ContactsLogic>() : null;
  String query = '';
  static const limit = 999;

  @override
  void dispose() {
    search.dispose();
    for (final id in visible) {
      contacts?.setPresenceVisible(id, false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: FriendDisplayPreferences.changes,
      builder: (context, _) => _build(context));
  Widget _build(BuildContext context) => Scaffold(
        backgroundColor: Styles.c_FFFFFF,
        appBar: AppBar(
          backgroundColor: Styles.c_FFFFFF,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          leading: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              icon: Icon(CupertinoIcons.back, color: Styles.c_0089FF)),
          title: Column(children: [
            Text('groupSelectContacts'.tr,
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Styles.c_0C1C33)),
            Obx(() => Text('${widget.selection.checkedList.length}/$limit',
                style: TextStyle(fontSize: 12, color: Styles.c_8E9AB0))),
          ]),
          actions: [
            Obx(() => TextButton(
                  onPressed: widget.selection.enabledConfirmButton
                      ? widget.selection.confirmSelectedList
                      : null,
                  child: Text(StrRes.nextStep,
                      style: const TextStyle(fontSize: 16)),
                ))
          ],
        ),
        body: SafeArea(
            top: false,
            child: Column(children: [
              Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: TextField(
                    controller: search,
                    onChanged: (value) =>
                        setState(() => query = value.trim().toLowerCase()),
                    decoration: InputDecoration(
                      hintText: StrRes.search,
                      hintStyle: TextStyle(color: Styles.c_8E9AB0),
                      filled: true,
                      fillColor: Styles.c_F4F5F7,
                      prefixIcon: Icon(CupertinoIcons.search,
                          size: 20, color: Styles.c_8E9AB0),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: MaterialLocalizations.of(context)
                                  .deleteButtonTooltip,
                              icon: const Icon(
                                  CupertinoIcons.clear_circled_solid,
                                  size: 18),
                              onPressed: () {
                                search.clear();
                                setState(() => query = '');
                              }),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  )),
              Expanded(child: Obx(() {
                final data = widget.friends.friendList
                    .where((friend) =>
                        query.isEmpty ||
                        [
                          friend.showName,
                          friend.nickname,
                          friend.userID,
                          friend.namePinyin
                        ].any((value) =>
                            value?.toLowerCase().contains(query) == true))
                    .map((friend) => ISUserInfo.fromJson(friend.toJson()))
                    .toList();
                SuspensionUtil.setShowSuspensionStatus(data);
                if (data.isEmpty && query.isNotEmpty) {
                  return Center(
                      child: Text(StrRes.searchNotResult,
                          style: Styles.ts_8E9AB0_14sp));
                }
                return AzListView(
                  data: data,
                  itemCount: data.length,
                  itemBuilder: (_, index) => _friend(data[index]),
                  susItemHeight: 28,
                  susItemBuilder: (_, index) => Container(
                      color: Styles.c_FFFFFF,
                      height: 28,
                      padding: const EdgeInsets.only(left: 12),
                      alignment: Alignment.centerLeft,
                      child: Text(data[index].getSuspensionTag(),
                          style:
                              TextStyle(fontSize: 12, color: Styles.c_8E9AB0))),
                  indexBarData: SuspensionUtil.getTagIndexList(data),
                  indexBarWidth: 20,
                  indexBarItemHeight: 16,
                  indexBarOptions: IndexBarOptions(
                    needRebuild: true,
                    textStyle: TextStyle(fontSize: 11, color: Styles.c_8E9AB0),
                    selectTextStyle: Styles.ts_FFFFFF_12sp,
                    downItemDecoration: BoxDecoration(
                        color: Styles.c_0089FF, shape: BoxShape.circle),
                  ),
                );
              })),
            ])),
      );

  Widget _friend(ISUserInfo friend) => VisibilityDetector(
        key: ValueKey('group-picker-${friend.userID}'),
        onVisibilityChanged: (info) {
          if (!mounted || friend.userID == null) return;
          final id = friend.userID!;
          final shown = info.visibleFraction > 0;
          shown ? visible.add(id) : visible.remove(id);
          contacts?.setPresenceVisible(id, shown);
        },
        child: Obx(() {
          final selected = widget.selection.isChecked(friend);
          final enabled = !widget.selection.isDefaultChecked(friend) &&
              (selected || widget.selection.checkedList.length < limit);
          final presence = contacts?.presence.users[friend.userID];
          return Semantics(
            selected: selected,
            button: true,
            child: Material(
                color: Styles.c_FFFFFF,
                child: InkWell(
                  onTap: enabled ? widget.selection.onTap(friend) : null,
                  child: Padding(
                      padding: const EdgeInsets.only(left: 16, right: 24),
                      child: Row(children: [
                        Icon(
                            selected
                                ? CupertinoIcons.checkmark_circle_fill
                                : CupertinoIcons.circle,
                            size: 23,
                            color:
                                selected ? Styles.c_0089FF : Styles.c_8E9AB0),
                        const SizedBox(width: 12),
                        Stack(clipBehavior: Clip.none, children: [
                          AvatarView(
                              width: 44,
                              height: 44,
                              isCircle: true,
                              url: friend.faceURL,
                              text: friend.showName),
                          if (FriendDisplayPreferences.showOnlineStatus &&
                              presence?.displayOnline == true)
                            Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                        color: const Color(0xFF4CAF50),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: Styles.c_FFFFFF,
                                            width: 1.5)))),
                        ]),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Container(
                          constraints: const BoxConstraints(minHeight: 68),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                              border: Border(
                                  bottom: BorderSide(
                                      color: Styles.c_E8EAEF, width: .5))),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(friend.showName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 16, color: Styles.c_0C1C33)),
                                if (presence != null) ...[
                                  const SizedBox(height: 3),
                                  PresenceLabel(presence: presence)
                                ],
                              ]),
                        )),
                      ])),
                )),
          );
        }),
      );
}
