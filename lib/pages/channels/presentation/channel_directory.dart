import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import '../../contacts/group_list/index/group_indexed_list.dart';
import '../../contacts/empty/contact_list_placeholder.dart';
import '../../contacts/select_contacts/contact_card/contact_card_picker_tokens.dart';
import '../models/channel_preview.dart';
import 'channel_ui.dart';

/// Reuses the group directory's indexing and row metrics; no group SDK calls.
class ChannelDirectory extends StatelessWidget {
  const ChannelDirectory(
      {super.key,
      required this.channels,
      required this.searching,
      required this.onTap});
  final List<ChannelPreview> channels;
  final bool searching;
  final ValueChanged<ChannelPreview> onTap;

  @override
  Widget build(BuildContext context) {
    final footer = SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppTokens.s5, AppTokens.s5, AppTokens.s5, AppTokens.s7),
          child: Center(
              child: Text(
                  channelText(context, '共 ${channels.length} 个频道',
                      '${channels.length} channels'),
                  style: ContactCardPickerTokens.subtitleStyle(context))),
        ));
    if (channels.isEmpty) {
      return contactListPlaceholder(context,
          title: searching
              ? channelText(context, '没有找到频道', 'No channels found')
              : channelText(context, '暂无频道', 'No channels yet'),
          loading: false,
          failed: false,
          onRetry: () {},
          footer: footer);
    }
    final indexed = <String, ChannelPreview>{
      for (var i = 0; i < channels.length; i++) '$i': channels[i],
    };
    return GroupIndexedList(
      groups: indexed.entries
          .map((e) => GroupInfo(groupID: e.key, groupName: e.value.name))
          .toList(),
      footer: footer,
      itemBuilder: (info) {
        final channel = indexed[info.groupID]!;
        return Material(
            color: Styles.c_FFFFFF,
            child: Column(children: [
              ListTile(
                minVerticalPadding: AppTokens.s3,
                horizontalTitleGap: AppTokens.s5,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.s5, vertical: AppTokens.s2),
                leading: CircleAvatar(
                    radius: (AppTokens.s7 + AppTokens.s6) / 2,
                    backgroundImage: channel.avatar == null
                        ? null
                        : MemoryImage(channel.avatar!),
                    child: channel.avatar == null ? Icon(channel.icon) : null),
                title: Text(channel.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Styles.ts_0C1C33_17sp
                        .copyWith(fontWeight: FontWeight.w500)),
                subtitle: Text(
                    channelText(context, '${channel.members.length} 位订阅者',
                        '${channel.members.length} subscribers'),
                    style: Styles.ts_8E9AB0_14sp),
                trailing: Icon(Icons.chevron_right, color: Styles.c_8E9AB0),
                onTap: () => onTap(channel),
              ),
              Divider(
                  height: 1,
                  thickness: .5,
                  indent: AppTokens.s5 * 2 + AppTokens.s7 + AppTokens.s6,
                  endIndent: AppTokens.s5,
                  color: Styles.c_E8EAEF),
            ]));
      },
    );
  }
}
