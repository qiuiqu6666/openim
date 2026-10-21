import 'package:flutter/material.dart';
import '../contacts/group_list/group_list_logic.dart';
import '../contacts/group_list/group_list_view.dart';
import 'presentation/channel_ui.dart';

class ChannelLiveListPage extends StatefulWidget {
  const ChannelLiveListPage({super.key});
  @override
  State<ChannelLiveListPage> createState() => _ChannelLiveListPageState();
}

class _ChannelLiveListPageState extends State<ChannelLiveListPage> {
  late final GroupListLogic _logic;
  @override
  void initState() {
    super.initState();
    _logic = GroupListLogic()..onStart();
  }

  @override
  void dispose() {
    _logic.onDelete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GroupListPage(
      logic: _logic,
      channelsOnly: true,
      title: channelText(context, '频道', 'Channels'));
}
