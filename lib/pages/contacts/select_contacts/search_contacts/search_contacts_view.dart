import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:search_keyword_text/search_keyword_text.dart';

import '../select_contacts_logic.dart';
import '../contact_card/contact_card_picker_tokens.dart';
import '../widgets/select_contacts_app_bar.dart';
import 'search_contacts_logic.dart';
import '../../../official_account/widgets/official_account_name_label.dart';
import '../selection/contact_selection_policy.dart';

class SelectContactsFromSearchPage extends StatelessWidget {
  final logic = Get.find<SelectContactsFromSearchLogic>();
  final selectContactsLogic = Get.find<SelectContactsLogic>();

  SelectContactsFromSearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return TouchCloseSoftKeyboard(
      child: Scaffold(
        appBar: SelectContactsAppBar.search(
          search: SearchBox(
            focusNode: logic.focusNode,
            controller: logic.searchCtrl,
            enabled: true,
            autofocus: true,
            textStyle: ContactCardPickerTokens.searchStyle(context),
            hintStyle: ContactCardPickerTokens.searchStyle(context, hint: true),
            backgroundColor: ContactCardPickerTokens.searchBackground(context),
            onSubmitted: (_) => logic.search(),
            onCleared: () => logic.focusNode.requestFocus(),
          ),
        ),
        backgroundColor: Styles.c_F8F9FA,
        body: Obx(() => logic.isSearchNotResult
            ? _emptyListView
            : ListView.builder(
                itemCount: logic.resultList.length,
                itemBuilder: (context, index) =>
                    _buildItemView(context, logic.resultList.elementAt(index)),
              )),
      ),
    );
  }

  Widget _buildItemView(BuildContext context, dynamic info) {
    final readOnly = !ContactSelectionPolicy.allows(info);
    Widget buildChild() => Ink(
          height: readOnly ? null : 64.h,
          color: Styles.c_FFFFFF,
          child: InkWell(
            key: ValueKey(
                'search-contact-row-${SelectContactsLogic.parseID(info)}'),
            onTap: selectContactsLogic.onTap(info),
            child: Container(
              constraints: readOnly ? BoxConstraints(minHeight: 64.h) : null,
              padding: EdgeInsets.symmetric(
                  horizontal: 16.w, vertical: readOnly ? 8.h : 0),
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
                    url: logic.parseFaceURL(info),
                    text: logic.parseNickname(info),
                    isGroup: info is GroupInfo,
                    isCircle: true,
                  ),
                  10.horizontalSpace,
                  Expanded(
                    child: Column(
                      mainAxisSize:
                          readOnly ? MainAxisSize.min : MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (ContactSelectionPolicy.hasVerifiedIdentity(info))
                          OfficialAccountNameLabel(
                            name: logic.parseNickname(info) ?? '',
                            userID: SelectContactsLogic.parseID(info),
                            ex: ContactSelectionPolicy.userExtension(info),
                            isSingleChat: info is! GroupInfo,
                            style: Styles.ts_0C1C33_17sp,
                          )
                        else
                          SearchKeywordText(
                            text: logic.parseNickname(info) ?? '',
                            keyText: logic.searchCtrl.text.trim(),
                            style: Styles.ts_0C1C33_17sp,
                            keyStyle: Styles.ts_0089FF_17sp,
                          ),
                        if (readOnly) ...[
                          const SizedBox(
                              height: ContactCardPickerTokens.textGap),
                          Text(
                            Localizations.localeOf(context).languageCode == 'zh'
                                ? '仅接收通知'
                                : 'Notifications only',
                            style:
                                ContactCardPickerTokens.subtitleStyle(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
    return selectContactsLogic.isMultiModel ? Obx(buildChild) : buildChild();
  }

  Widget get _emptyListView => SizedBox(
        width: 1.sw,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            44.verticalSpace,
            StrRes.searchNotFound.toText..style = Styles.ts_8E9AB0_17sp,
          ],
        ),
      );
}
