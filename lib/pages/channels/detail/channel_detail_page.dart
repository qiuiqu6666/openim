import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../models/channel_preview.dart';
import '../presentation/channel_ui.dart';
import '../publishing/channel_compose_page.dart';
import 'channel_profile_page.dart';
import 'widgets/channel_post_card.dart';

class ChannelDetailPage extends StatefulWidget {
  const ChannelDetailPage({super.key, required this.channel});
  final ChannelPreview channel;
  @override
  State<ChannelDetailPage> createState() => _ChannelDetailPageState();
}

class _ChannelDetailPageState extends State<ChannelDetailPage> {
  final _search = TextEditingController();
  bool _searching = false;
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    final text =
        await channelRoute<String>(context, const ChannelComposePage());
    if (!mounted || text == null) return;
    widget.channel.publish(text);
  }

  Future<void> _profile() async {
    final search = await channelRoute<bool>(
        context, ChannelProfilePage(channel: widget.channel));
    if (!mounted) return;
    if (widget.channel.deleted) {
      Navigator.pop(context);
      return;
    }
    if (search == true) setState(() => _searching = true);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: widget.channel,
      builder: (context, _) {
        final channel = widget.channel;
        final posts = channel.posts
            .where((post) => post.text
                .toLowerCase()
                .contains(_search.text.trim().toLowerCase()))
            .toList()
          ..sort((a, b) => a.pinned == b.pinned
              ? b.createdAt.compareTo(a.createdAt)
              : a.pinned
                  ? -1
                  : 1);
        return ChannelScaffold(
          title: channel.name,
          actions: [
            IconButton(
                tooltip: channelText(context, '搜索消息', 'Search posts'),
                icon: const Icon(Icons.search),
                onPressed: () => setState(() {
                      _searching = !_searching;
                      if (!_searching) _search.clear();
                    })),
            IconButton(
                tooltip: channelText(context, '频道详情', 'Channel details'),
                icon: const Icon(Icons.more_horiz),
                onPressed: _profile),
          ],
          body: Column(children: [
            if (_searching)
              Padding(
                  padding: const EdgeInsets.all(AppTokens.s5),
                  child: TextField(
                      controller: _search,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                          labelText: channelText(
                              context, '搜索频道内容', 'Search channel content'),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                              tooltip:
                                  channelText(context, '清空搜索', 'Clear search'),
                              icon: const Icon(Icons.clear),
                              onPressed: () => setState(_search.clear))))),
            Expanded(
                child: ListView(children: [
              if (!_searching)
                ChannelSection(children: [
                  ListTile(
                      leading: CircleAvatar(child: Icon(channel.icon)),
                      title: Text(channel.name),
                      subtitle: Text(channelText(
                          context,
                          channel.isPublic ? '公开频道 · 订阅人数 —' : '私密频道 · 订阅人数 —',
                          channel.isPublic
                              ? 'Public channel · Subscribers —'
                              : 'Private channel · Subscribers —')),
                      onTap: _profile),
                  if (channel.description.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.all(AppTokens.s5),
                        child: Text(channel.description)),
                ]),
              if (posts.isEmpty)
                ChannelEmpty(
                    title: channelText(
                        context,
                        _search.text.trim().isNotEmpty ? '没有找到消息' : '还没有消息',
                        _search.text.trim().isNotEmpty
                            ? 'No matching posts'
                            : 'No posts yet'),
                    message: channelText(
                        context,
                        _search.text.trim().isNotEmpty
                            ? '换个关键词试试。'
                            : '发布第一条消息，与订阅者分享新鲜事。',
                        _search.text.trim().isNotEmpty
                            ? 'Try another keyword.'
                            : 'Publish the first update for your subscribers.')),
              for (final post in posts)
                ChannelPostCard(channel: channel, post: post),
              const SizedBox(height: AppTokens.s5),
            ])),
          ]),
          bottom: channel.owner
              ? FilledButton.icon(
                  onPressed: _publish,
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(channelText(context, '发布消息', 'Publish post')))
              : FilledButton.icon(
                  onPressed: () => channel.update(() {
                        if (!channel.subscribed) {
                          channel.subscribed = true;
                        } else {
                          channel.notifications = !channel.notifications;
                        }
                      }),
                  icon: Icon(!channel.subscribed
                      ? Icons.add
                      : channel.notifications
                          ? Icons.notifications_off_outlined
                          : Icons.notifications_outlined),
                  label: Text(channelText(
                      context,
                      !channel.subscribed
                          ? '订阅频道（预览）'
                          : channel.notifications
                              ? '关闭通知'
                              : '开启通知',
                      !channel.subscribed
                          ? 'Subscribe (preview)'
                          : channel.notifications
                              ? 'Mute notifications'
                              : 'Enable notifications'))),
        );
      });
}
