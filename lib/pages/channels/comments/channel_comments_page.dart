import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../models/channel_preview.dart';
import '../presentation/channel_ui.dart';

class ChannelCommentsPage extends StatefulWidget {
  const ChannelCommentsPage(
      {super.key, required this.channel, required this.post});
  final ChannelPreview channel;
  final ChannelPost post;
  @override
  State<ChannelCommentsPage> createState() => _ChannelCommentsPageState();
}

class _ChannelCommentsPageState extends State<ChannelCommentsPage> {
  final _text = TextEditingController();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: widget.channel,
      builder: (context, _) {
        final allowed =
            widget.channel.subscribed && widget.channel.commentsEnabled;
        return ChannelScaffold(
          title: channelText(context, '评论', 'Comments'),
          body: ListView(children: [
            ChannelSection(children: [
              Padding(
                  padding: const EdgeInsets.all(AppTokens.s5),
                  child: Text(widget.post.text))
            ]),
            if (widget.post.comments.isEmpty)
              ChannelEmpty(
                  title: channelText(context, '还没有评论', 'No comments yet'),
                  message: channelText(context, '围绕这条消息，分享你的想法。',
                      'Share your thoughts about this post.')),
            for (final comment in widget.post.comments)
              ChannelSection(children: [
                ListTile(
                    leading:
                        const CircleAvatar(child: Icon(Icons.person_outline)),
                    title: Text(channelText(context, '我 · 预览', 'Me · Preview')),
                    subtitle: Text(comment))
              ]),
          ]),
          bottom: allowed
              ? Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                      child: TextField(
                          controller: _text,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 500,
                          decoration: InputDecoration(
                              labelText: channelText(
                                  context, '写评论', 'Write a comment'),
                              border: const OutlineInputBorder()),
                          onChanged: (_) => setState(() {}))),
                  const SizedBox(width: AppTokens.s3),
                  IconButton(
                      tooltip: channelText(context, '发送评论', 'Send comment'),
                      onPressed: _text.text.trim().isEmpty
                          ? null
                          : () {
                              widget.channel.comment(widget.post, _text.text);
                              _text.clear();
                              setState(() {});
                            },
                      icon: const Icon(Icons.send_outlined)),
                ])
              : Text(
                  channelText(
                      context,
                      widget.channel.commentsEnabled ? '订阅后即可评论' : '该频道已关闭评论',
                      widget.channel.commentsEnabled
                          ? 'Subscribe to comment'
                          : 'Comments are turned off'),
                  textAlign: TextAlign.center),
        );
      });
}
