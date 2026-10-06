import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:sprintf/sprintf.dart';

import 'select_contacts_logic.dart';
import 'friend_list/friend_list_view.dart';
import 'friend_list/friend_list_logic.dart';
import 'contact_card/contact_card_friend_picker.dart';
import 'contact_card/contact_card_picker_tokens.dart';
import 'widgets/select_contacts_app_bar.dart';
import '../../official_account/widgets/official_account_name_label.dart';
import 'selection/contact_selection_policy.dart';

class SelectContactsPage extends StatelessWidget {
  final logic = Get.find<SelectContactsLogic>();

  SelectContactsPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (logic.action == SelAction.carte) {
      return ContactCardFriendPicker(
        friends: Get.find<SelectContactsFromFriendsLogic>(),
        selection: logic,
      );
    }
    if (logic.action == SelAction.crateGroup) {
      return SelectContactsFromFriendsPage(title: StrRes.createGroup);
    }
    if (logic.action == SelAction.addMember) {
      return SelectContactsFromFriendsPage(title: 'groupSelectContacts'.tr);
    }
    return Scaffold(
      appBar: SelectContactsAppBar(
        title: logic.action == SelAction.recommend
            ? StrRes.recommendToFriend
            : Localizations.localeOf(context).languageCode == 'zh'
                ? '选择多个会话'
                : 'Select conversations',
      ),
      backgroundColor: Styles.c_F8F9FA,
      body: Column(
        children: [
          10.verticalSpace,
          Flexible(
            child: Obx(() => CustomScrollView(
                  slivers: [
                    SliverFixedExtentList(
                      delegate: SliverChildListDelegate(
                        [
                          _buildCategoryItemView(
                            label: StrRes.myFriend,
                            onTap: logic.selectFromMyFriend,
                          ),
                          if (!logic.hiddenGroup)
                            _buildCategoryItemView(
                              label: StrRes.myGroup,
                              onTap: logic.selectFromMyGroup,
                            ),
                        ],
                      ),
                      itemExtent: 56.h,
                    ),
                    if (logic.conversationList.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Container(
                          constraints: BoxConstraints(minHeight: 29.h),
                          alignment: Alignment.centerLeft,
                          margin: EdgeInsets.symmetric(horizontal: 16.w),
                          padding: EdgeInsets.symmetric(
                              vertical:
                                  ContactCardPickerTokens.verticalPadding.h),
                          child: StrRes.recentConversations.toText
                            ..style = Styles.ts_8E9AB0_12sp,
                        ),
                      ),
                    SliverList.separated(
                      itemCount: logic.conversationList.length,
                      itemBuilder: (context, index) =>
                          _buildRecentConversationsItemView(
                        context,
                        logic.conversationList.elementAt(index),
                      ),
                      separatorBuilder: (context, index) => ColoredBox(
                        color: Styles.c_FFFFFF,
                        child: Divider(
                          height: ContactCardPickerTokens.dividerThickness,
                          thickness: ContactCardPickerTokens.dividerThickness,
                          color: ContactCardPickerTokens.divider(context),
                          indent: 16.w +
                              (logic.isMultiModel ? 30.w : 0) +
                              math.min(44.w, 44.h) +
                              10.w,
                          endIndent: 16.w,
                        ),
                      ),
                    ),
                  ],
                )),
          ),
          logic.checkedConfirmView,
        ],
      ),
    );
  }

  Widget _buildCategoryItemView({
    required String label,
    Function()? onTap,
  }) =>
      Ink(
        height: 56.h,
        color: Styles.c_FFFFFF,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: Row(
              children: [
                Expanded(
                  child: label.toText
                    ..style = Styles.ts_0C1C33_17sp
                    ..maxLines = 1
                    ..overflow = TextOverflow.ellipsis,
                ),
                ImageRes.rightArrow.toImage
                  ..width = 24.w
                  ..height = 24.h,
              ],
            ),
          ),
        ),
      );

  Widget _buildRecentConversationsItemView(
      BuildContext context, ConversationInfo info) {
    Widget buildChild() {
      final preview = logic.recentPreviews.data(info);
      final readOnly = !ContactSelectionPolicy.allows(info);
      return Ink(
        color: Styles.c_FFFFFF,
        child: InkWell(
          key: ValueKey('recent-conversation-row-${info.conversationID}'),
          onTap: logic.onTap(info),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: 64.h),
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: 16.w,
                  vertical: ContactCardPickerTokens.verticalPadding.h),
              child: Row(
                children: [
                  if (logic.isMultiModel)
                    Padding(
                      padding: EdgeInsets.only(right: 10.w),
                      child: Opacity(
                        opacity: readOnly ? .5 : 1,
                        child: ChatRadio(checked: logic.isChecked(info)),
                      ),
                    ),
                  AvatarView(
                    url: info.faceURL,
                    text: info.showName,
                    isGroup: !info.isSingleChat,
                    isCircle: true,
                  ),
                  10.horizontalSpace,
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OfficialAccountNameLabel(
                          name: info.showName ?? '',
                          userID: info.userID,
                          ex: info.ex,
                          isSingleChat: info.isSingleChat,
                          style: Styles.ts_0C1C33_17sp,
                        ),
                        const SizedBox(height: ContactCardPickerTokens.textGap),
                        Text.rich(
                            TextSpan(children: [
                              if (readOnly)
                                TextSpan(
                                    text: Localizations.localeOf(context)
                                                .languageCode ==
                                            'zh'
                                        ? '仅接收通知 · '
                                        : 'Notifications only · '),
                              TextSpan(text: preview.unread),
                              TextSpan(
                                text: preview.mention,
                                style: TextStyle(color: Styles.c_FF381F),
                              ),
                              TextSpan(
                                text: preview.prefix,
                                style: preview.isDraft
                                    ? TextStyle(color: Styles.c_FF381F)
                                    : null,
                              ),
                              TextSpan(text: preview.content),
                            ]),
                            key: ValueKey(
                                'recent-conversation-preview-${info.conversationID}'),
                            style:
                                ContactCardPickerTokens.subtitleStyle(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
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

    return Obx(buildChild);
  }
}

class CheckedConfirmView extends StatelessWidget {
  CheckedConfirmView({super.key});
  final logic = Get.find<SelectContactsLogic>();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: 66.h),
      decoration: BoxDecoration(
        color: Styles.c_FFFFFF,
        boxShadow: [
          BoxShadow(
            offset: Offset(0, -1.h),
            blurRadius: 4.r,
            spreadRadius: 1.r,
            color: Styles.c_000000_opacity4,
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      child: SafeArea(
        top: false,
        child: Obx(() {
          final count = logic.checkedList.length;
          final selectedText = sprintf(StrRes.selectedPeopleCount, [count]);
          final confirmText =
              sprintf(StrRes.confirmSelectedPeople, [count, '999']);
          final selectedStyle = Styles.ts_0089FF_14sp;
          final confirmStyle = Styles.ts_FFFFFF_14sp;
          return LayoutBuilder(builder: (context, constraints) {
            Size measure(String text, TextStyle style) {
              var effectiveStyle =
                  DefaultTextStyle.of(context).style.merge(style);
              if (MediaQuery.boldTextOf(context)) {
                effectiveStyle = effectiveStyle
                    .merge(const TextStyle(fontWeight: FontWeight.bold));
              }
              final painter = TextPainter(
                text: TextSpan(text: text, style: effectiveStyle),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
                locale: Localizations.localeOf(context),
                maxLines: 1,
              )..layout();
              final size = painter.size;
              painter.dispose();
              return size;
            }

            final confirmSize = measure(confirmText, confirmStyle);
            final buttonWidth = confirmSize.width + 28.w;
            final buttonHeight = confirmSize.height + 16.h;
            final stacked = measure(selectedText, selectedStyle).width +
                    24.w +
                    AppTokens.s3 +
                    buttonWidth >
                constraints.maxWidth;
            final selected = GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: logic.viewSelectedContactsList,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(selectedText,
                            style: selectedStyle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      ImageRes.expandUpArrow.toImage
                        ..width = 24.w
                        ..height = 24.h,
                    ],
                  ),
                  if (count > 0) ...[
                    4.verticalSpace,
                    logic.checkedStrTips.toText
                      ..style = Styles.ts_8E9AB0_14sp
                      ..maxLines = 1
                      ..overflow = TextOverflow.ellipsis,
                  ],
                ],
              ),
            );
            final confirm = Button(
              height: buttonHeight > 40.h ? buttonHeight : 40.h,
              enabled: logic.enabledConfirmButton,
              padding: EdgeInsets.symmetric(horizontal: 14.w),
              text: confirmText,
              textStyle: confirmStyle,
              onTap: logic.confirmSelectedList,
            );
            if (stacked) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  selected,
                  const SizedBox(height: AppTokens.s2),
                  confirm,
                ],
              );
            }
            return Row(children: [
              Expanded(child: selected),
              const SizedBox(width: AppTokens.s3),
              SizedBox(width: buttonWidth, child: confirm),
            ]);
          });
        }),
      ),
    );
  }
}

class SelectedContactsListView extends StatelessWidget {
  SelectedContactsListView({super.key});
  final logic = Get.find<SelectContactsLogic>();

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: 548.h),
      decoration: BoxDecoration(
        color: Styles.c_FFFFFF,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(6.r),
          topRight: Radius.circular(6.r),
        ),
      ),
      child: Obx(() => Column(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                decoration: BoxDecoration(
                  border: BorderDirectional(
                    bottom: BorderSide(color: Styles.c_E8EAEF, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    sprintf(StrRes.selectedPeopleCount,
                        [logic.checkedList.length]).toText
                      ..style = Styles.ts_0C1C33_17sp_medium,
                    const Spacer(),
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => Get.back(),
                      child: Container(
                        height: 52.h,
                        alignment: Alignment.center,
                        child: StrRes.confirm.toText
                          ..style = Styles.ts_0089FF_17sp,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: logic.checkedList.length,
                  shrinkWrap: true,
                  itemBuilder: (_, index) => _buildItemView(index),
                ),
              ),
            ],
          )),
    );
  }

  Widget _buildItemView(int index) {
    final info = logic.checkedList.values.elementAt(index);
    String? name;
    String? faceURL;
    bool isGroup = false;
    name = SelectContactsLogic.parseName(info);
    faceURL = SelectContactsLogic.parseFaceURL(info);
    if (info is ConversationInfo) {
      isGroup = !info.isSingleChat;
    } else if (info is GroupInfo) {
      isGroup = true;
      name = info.groupName;
      faceURL = info.faceURL;
    } else if (info is UserInfo) {
      name = info.nickname;
      faceURL = info.faceURL;
    }
    return Container(
      height: 64.h,
      padding: EdgeInsets.symmetric(horizontal: 16.w),
      color: Styles.c_FFFFFF,
      child: Row(
        children: [
          AvatarView(
              url: faceURL, text: name, isGroup: isGroup, isCircle: true),
          10.horizontalSpace,
          Expanded(
            child: OfficialAccountNameLabel(
              name: name ?? '',
              userID: SelectContactsLogic.parseID(info),
              ex: ContactSelectionPolicy.userExtension(info),
              isSingleChat: !isGroup,
              style: Styles.ts_0C1C33_17sp,
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => logic.removeItem(info),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 13.w, vertical: 4.h),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2.r),
                border: Border.all(
                  color: Styles.c_E8EAEF,
                  width: 1,
                ),
              ),
              child: StrRes.remove.toText..style = Styles.ts_0089FF_17sp,
            ),
          ),
        ],
      ),
    );
  }
}
