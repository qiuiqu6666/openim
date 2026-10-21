import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../../comments/channel_comments_page.dart';
import '../../models/channel_preview.dart';
import '../../presentation/channel_ui.dart';

class ChannelPostCard extends StatelessWidget {
  const ChannelPostCard({super.key, required this.channel, required this.post});
  final ChannelPreview channel;
  final ChannelPost post;
  @override
  Widget build(BuildContext context) => ChannelSection(children: [
        ListTile(
            leading: CircleAvatar(child: Icon(channel.icon)),
            title: Text(channel.name),
            subtitle: Text(channelText(
                context, '示例消息 · 仅本地可见', 'Preview post · Local only')),
            trailing: channel.owner
                ? IconButton(
                    tooltip: channelText(context, post.pinned ? '取消置顶' : '置顶消息',
                        post.pinned ? 'Unpin post' : 'Pin post'),
                    isSelected: post.pinned,
                    onPressed: () => channel.pin(post),
                    icon: Icon(
                        post.pinned ? Icons.push_pin : Icons.push_pin_outlined))
                : null),
        if (post.pinned)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppTokens.s5),
              child: Text(channelText(context, '置顶消息', 'Pinned post'),
                  style: Theme.of(context).textTheme.labelLarge)),
        Padding(
            padding: const EdgeInsets.all(AppTokens.s5),
            child: channel.restrictSaving
                ? Text(post.text, style: Theme.of(context).textTheme.bodyLarge)
                : SelectableText(post.text,
                    style: Theme.of(context).textTheme.bodyLarge)),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.s5),
            child: Text(
                channelText(
                    context, '浏览量 — · 发布后统计', 'Views — · Counted after launch'),
                style: Theme.of(context).textTheme.bodySmall)),
        Padding(
            padding: const EdgeInsets.all(AppTokens.s3),
            child: Wrap(
                spacing: AppTokens.s3,
                runSpacing: AppTokens.s3,
                children: [
                  TextButton.icon(
                      onPressed:
                          channel.subscribed ? () => channel.react(post) : null,
                      icon: Icon(
                          post.liked ? Icons.favorite : Icons.favorite_border),
                      label: Text(channelText(
                          context,
                          post.liked ? '已回应 1' : '回应',
                          post.liked ? 'Liked 1' : 'Like'))),
                  TextButton.icon(
                      onPressed: () => channelRoute<void>(context,
                          ChannelCommentsPage(channel: channel, post: post)),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: Text(
                          '${channelText(context, '评论', 'Comments')} ${post.comments.length}')),
                  TextButton.icon(
                      onPressed: channel.restrictSaving
                          ? null
                          : () => channelUnavailable(context),
                      icon: const Icon(Icons.forward_outlined),
                      label: Text(channelText(context, '转发', 'Forward'))),
                ])),
      ]);
}
