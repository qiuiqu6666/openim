import 'dart:math' as math;

import 'package:azlistview/azlistview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../contacts_logic.dart';
import '../../presence/contact_presence_policy.dart';
import '../../presence_label.dart';
import '../select_contacts_logic.dart';
import 'friend_list_logic.dart';
import 'group_contact_picker.dart';
import '../contact_card/contact_card_friend_picker.dart';
import '../contact_card/contact_card_picker_tokens.dart';
import '../contact_card/contact_card_presence_visibility.dart';
import '../widgets/select_contacts_app_bar.dart';
import '../../../official_account/widgets/official_account_name_label.dart';
import '../selection/contact_selection_policy.dart';

class SelectContactsFromFriendsPage extends StatefulWidget {
  final logic = Get.find<SelectContactsFromFriendsLogic>();
  final selectContactsLogic = Get.find<SelectContactsLogic>();

  SelectContactsFromFriendsPage({super.key, this.title});

  final String? title;

  @override
  State<SelectContactsFromFriendsPage> createState() =>
      _SelectContactsFromFriendsPageState();
}

class _SelectContactsFromFriendsPageState
    extends State<SelectContactsFromFriendsPage> with WidgetsBindingObserver {
  final _visible = <Object, String>{};
  final _registered = <String>{};
  late final ContactsLogic? _contacts;
  bool _routeActive = true;
  bool _appActive = true;
  bool _disposing = false;
  bool _hasPresenceOwner = false;

  SelectContactsFromFriendsLogic get logic => widget.logic;
  SelectContactsLogic get selectContactsLogic => widget.selectContactsLogic;

  @override
  void initState() {
    super.initState();
    _contacts =
        Get.isRegistered<ContactsLogic>() ? Get.find<ContactsLogic>() : null;
    _appActive = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    FriendDisplayPreferences.changes.addListener(_syncPresence);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeActive = (ModalRoute.isCurrentOf(context) ?? true) &&
        TickerMode.valuesOf(context).enabled;
    _syncPresence();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    _syncPresence();
  }

  void _setVisibility(Object rowOwner, String id, bool shown) {
    if (_disposing || !mounted) return;
    if (shown) {
      _visible[rowOwner] = id;
    } else {
      _visible.remove(rowOwner);
    }
    _syncPresence();
  }

  bool get _canReadPresence =>
      _contacts != null &&
      !_contacts.isClosed &&
      _contacts.isCurrentSession &&
      FriendDisplayPreferences.showOnlineStatus;

  void _syncPresence() {
    final contacts = _contacts;
    if (contacts == null || contacts.isClosed) return;
    final enabled =
        !_disposing && _routeActive && _appActive && _canReadPresence;
    final next = enabled ? _visible.values.toSet() : const <String>{};
    if ((!_hasPresenceOwner && next.isEmpty) ||
        (_hasPresenceOwner &&
            next.length == _registered.length &&
            _registered.containsAll(next))) {
      return;
    }
    contacts.setDirectoryPresenceVisible(this, Set<String>.unmodifiable(next));
    _hasPresenceOwner = true;
    _registered
      ..clear()
      ..addAll(next);
  }

  @override
  void dispose() {
    _disposing = true;
    FriendDisplayPreferences.changes.removeListener(_syncPresence);
    WidgetsBinding.instance.removeObserver(this);
    if (_hasPresenceOwner) _contacts?.setDirectoryPresenceVisible(this, null);
    _registered.clear();
    _visible.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (selectContactsLogic.action == SelAction.carte) {
      return ContactCardFriendPicker(
        friends: logic,
        selection: selectContactsLogic,
      );
    }
    if (selectContactsLogic.action == SelAction.crateGroup) {
      return GroupContactPicker(friends: logic, selection: selectContactsLogic);
    }
    return ListenableBuilder(
      listenable: FriendDisplayPreferences.changes,
      builder: (context, _) => Scaffold(
        appBar: SelectContactsAppBar(
          title: widget.title ??
              (selectContactsLogic.action == SelAction.addMember
                  ? 'groupSelectContacts'.tr
                  : StrRes.myFriend),
        ),
        backgroundColor: selectContactsLogic.action == SelAction.addMember
            ? Styles.c_FFFFFF
            : Styles.c_F8F9FA,
        body: Column(
          children: [
            if (selectContactsLogic.action == SelAction.addMember)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 12.h),
                child: Row(children: [
                  Expanded(
                      child: ClipRRect(
                    borderRadius: BorderRadius.circular(10.r),
                    child: SearchBox(
                      controller: logic.searchController,
                      enabled: true,
                      height: 40.h,
                      hintText: 'groupMemberSearchHint'.tr,
                      backgroundColor: Styles.c_F0F2F6,
                      onChanged: logic.searchFriends,
                      onCleared: () => logic.searchFriends(''),
                      onSubmitted: logic.searchFriends,
                    ),
                  )),
                  if (selectContactsLogic.isMultiModel)
                    Obx(() => TextButton(
                          onPressed: logic.operableList.isEmpty
                              ? null
                              : logic.selectAll,
                          style: TextButton.styleFrom(
                            foregroundColor: Styles.c_0089FF,
                            minimumSize: Size(64.w, 48.h),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            ChatRadio(checked: logic.isSelectAll),
                            6.horizontalSpace,
                            Text(StrRes.selectAll),
                          ]),
                        )),
                ]),
              ),
            if (selectContactsLogic.isMultiModel &&
                selectContactsLogic.action != SelAction.addMember)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 10.h),
                child: Ink(
                  height: 64.h,
                  color: Styles.c_FFFFFF,
                  child: InkWell(
                    onTap: logic.selectAll,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 16.w),
                      child: Row(
                        children: [
                          Obx(() => Padding(
                                padding: EdgeInsets.only(right: 10.w),
                                child: ChatRadio(checked: logic.isSelectAll),
                              )),
                          10.horizontalSpace,
                          StrRes.selectAll.toText
                            ..style = Styles.ts_0C1C33_17sp,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Flexible(
              child: Obx(
                () {
                  final friends = logic.visibleFriends;
                  final tags = SuspensionUtil.getTagIndexList(friends);
                  return LayoutBuilder(builder: (context, constraints) {
                    final scaler = MediaQuery.textScalerOf(context);
                    final height = math.min(
                        ContactCardPickerTokens.indexHeight(context),
                        constraints.maxHeight / math.max(1, tags.length));
                    final indexFont = math.min(
                        ContactCardPickerTokens.indexSize,
                        math.max(1.0, height - AppTokens.s2) /
                            ((scaler.scale(ContactCardPickerTokens.indexSize) /
                                    ContactCardPickerTokens.indexSize) *
                                ContactCardPickerTokens.lineHeight));
                    final indexStyle = ContactCardPickerTokens.secondaryStyle(
                        context,
                        size: indexFont);
                    return WrapAzListView<ISUserInfo>(
                      data: friends,
                      itemCount: friends.length,
                      susItemHeight:
                          ContactCardPickerTokens.sectionHeight(context),
                      susTextStyle: ContactCardPickerTokens.secondaryStyle(
                          context,
                          size: ContactCardPickerTokens.sectionSize),
                      indexBarItemHeight: height,
                      indexBarWidth: ContactCardPickerTokens.indexBarWidth,
                      indexBarOptions: directoryIndexBarOptions(
                        textStyle: indexStyle,
                        selectTextStyle:
                            indexStyle.copyWith(color: AppTokens.onAccent),
                      ),
                      itemBuilder: (context, data, index) =>
                          _buildItemView(context, data),
                    );
                  });
                },
              ),
            ),
            selectContactsLogic.checkedConfirmView,
          ],
        ),
      ),
    );
  }

  Widget _buildItemView(BuildContext context, ISUserInfo info) {
    Widget buildChild() {
      // Read the shared cache reactively, but expose only the current session.
      final cached = _contacts?.presence.users[info.userID];
      final presence = _canReadPresence
          ? ContactPresencePolicy.resolve(
              userID: info.userID, ex: info.ex, presence: cached)
          : null;
      final readOnly = !ContactSelectionPolicy.allows(info);
      return Ink(
        color: Styles.c_FFFFFF,
        child: InkWell(
          key: ValueKey('friend-picker-row-${info.userID}'),
          onTap: selectContactsLogic.onTap(info),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: 64.h),
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: 16.w,
                  vertical: ContactCardPickerTokens.verticalPadding.h),
              child: Row(
                children: [
                  if (selectContactsLogic.isMultiModel)
                    Padding(
                      padding: EdgeInsets.only(right: 10.w),
                      child: Opacity(
                        opacity: readOnly ? .5 : 1,
                        child: ChatRadio(
                          checked: selectContactsLogic.isChecked(info),
                          enabled: !selectContactsLogic.isDefaultChecked(info),
                        ),
                      ),
                    ),
                  AvatarView(
                    url: info.faceURL,
                    text: info.showName,
                  ),
                  10.horizontalSpace,
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OfficialAccountNameLabel(
                          name: info.showName,
                          userID: info.userID,
                          ex: info.ex,
                          style: Styles.ts_0C1C33_17sp,
                        ),
                        const SizedBox(height: ContactCardPickerTokens.textGap),
                        if (readOnly)
                          Text(
                            Localizations.localeOf(context).languageCode == 'zh'
                                ? '仅接收通知'
                                : 'Notifications only',
                            style:
                                ContactCardPickerTokens.subtitleStyle(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        else if (presence != null)
                          PresenceLabel(
                            key: ValueKey(
                                'friend-picker-presence-${info.userID}'),
                            presence: presence,
                            textStyle:
                                ContactCardPickerTokens.subtitleStyle(context),
                          )
                        else
                          SizedBox(
                              height: MediaQuery.textScalerOf(context).scale(
                                      ContactCardPickerTokens.subtitleSize) *
                                  ContactCardPickerTokens.lineHeight),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final row = selectContactsLogic.isMultiModel || _contacts != null
        ? Obx(buildChild)
        : buildChild();
    final id = info.userID;
    if (id == null || id.isEmpty) return row;
    return ContactCardPresenceVisibility(
      key: ValueKey('friend-picker-presence-row-$id'),
      userID: id,
      onVisibilityChanged: _setVisibility,
      child: row,
    );
  }
}
