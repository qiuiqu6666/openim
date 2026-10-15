import 'dart:math' as math;

import 'package:azlistview/azlistview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:lpinyin/lpinyin.dart';
import 'package:openim_common/openim_common.dart';

import '../../select_contacts/contact_card/contact_card_picker_tokens.dart';

class IndexedGroup extends ISuspensionBean {
  IndexedGroup(this.group) {
    sortName =
        PinyinHelper.getPinyinE((group.groupName ?? '').trim()).toUpperCase();
    tag = RegExp(r'^[A-Z]').hasMatch(sortName) ? sortName[0] : '#';
  }
  final GroupInfo group;
  late final String sortName;
  late final String tag;
  @override
  String getSuspensionTag() => tag;
}

List<IndexedGroup> indexGroups(Iterable<GroupInfo> groups) {
  final rows = {for (final group in groups) group.groupID: IndexedGroup(group)}
      .values
      .toList();
  rows.sort((a, b) {
    if (a.tag != b.tag) {
      if (a.tag == '#') return 1;
      if (b.tag == '#') return -1;
      return a.tag.compareTo(b.tag);
    }
    final nameOrder = a.sortName.compareTo(b.sortName);
    return nameOrder != 0
        ? nameOrder
        : a.group.groupID.compareTo(b.group.groupID);
  });
  SuspensionUtil.setShowSuspensionStatus(rows);
  return rows;
}

class GroupIndexedList extends StatelessWidget {
  const GroupIndexedList(
      {super.key,
      required this.groups,
      required this.itemBuilder,
      this.footer});
  final List<GroupInfo> groups;
  final Widget Function(GroupInfo) itemBuilder;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final rows = indexGroups(groups);
    final groupCount = rows.length;
    if (footer != null) {
      rows.add(IndexedGroup(GroupInfo(groupID: '__footer__')));
    }
    final sectionHeight = ContactCardPickerTokens.sectionHeight(context);
    return LayoutBuilder(builder: (context, constraints) {
      final indexHeight = math.min(ContactCardPickerTokens.indexHeight(context),
          constraints.maxHeight / 27);
      return AzListView(
        data: rows,
        itemCount: rows.length,
        itemBuilder: (_, index) =>
            index == groupCount ? footer! : itemBuilder(rows[index].group),
        padding: EdgeInsets.only(
            right: ContactCardPickerTokens.indexBarWidth,
            bottom: MediaQuery.paddingOf(context).bottom),
        physics: const AlwaysScrollableScrollPhysics(),
        susItemHeight: sectionHeight,
        susItemBuilder: (_, index) => Container(
          height: sectionHeight,
          padding: const EdgeInsets.only(left: AppTokens.s5),
          alignment: Alignment.centerLeft,
          color: Styles.c_F8F9FA,
          child: Text(rows[index].tag, style: Styles.ts_8E9AB0_12sp),
        ),
        indexBarData: const [
          'A',
          'B',
          'C',
          'D',
          'E',
          'F',
          'G',
          'H',
          'I',
          'J',
          'K',
          'L',
          'M',
          'N',
          'O',
          'P',
          'Q',
          'R',
          'S',
          'T',
          'U',
          'V',
          'W',
          'X',
          'Y',
          'Z',
          '#'
        ],
        indexBarWidth: ContactCardPickerTokens.indexBarWidth,
        indexBarItemHeight: indexHeight,
        indexBarOptions: directoryIndexBarOptions(
          highlightSelection: true,
          hapticFeedback: true,
          textStyle: ContactCardPickerTokens.secondaryStyle(context,
              size: math.min(
                  ContactCardPickerTokens.indexSize, indexHeight * .8)),
        ),
      );
    });
  }
}
