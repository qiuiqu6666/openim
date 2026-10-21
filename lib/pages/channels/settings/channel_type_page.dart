import 'package:flutter/material.dart';
import '../models/channel_preview.dart';
import '../presentation/channel_ui.dart';
import '../presentation/channel_tokens.dart';

class ChannelTypePage extends StatefulWidget {
  const ChannelTypePage(
      {super.key, required this.channel, this.creating = false});
  final ChannelPreview channel;
  final bool creating;
  @override
  State<ChannelTypePage> createState() => _ChannelTypePageState();
}

class _ChannelTypePageState extends State<ChannelTypePage> {
  late bool _public = widget.channel.isPublic;
  void _save() {
    if (!widget.channel.owner) return;
    widget.channel.update(() {
      widget.channel.isPublic = _public;
    });
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => ChannelScaffold(
      title: channelText(context, '频道类型', 'Channel type'),
      actions: [
        TextButton(
            onPressed: widget.channel.owner ? _save : null,
            child: Text(channelText(context, widget.creating ? '下一步' : '保存',
                widget.creating ? 'Next' : 'Save')))
      ],
      body: ListView(
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 32),
          children: [
            _caption(channelText(context, '链接', 'Link')),
            const SizedBox(height: 10),
            _card(Column(children: [
              for (final public in [true, false]) ...[
                if (!public) const Divider(height: .5, thickness: .5),
                Semantics(
                    selected: _public == public,
                    child: InkWell(
                        onTap: widget.channel.owner
                            ? () => setState(() => _public = public)
                            : null,
                        child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 54),
                            child: Row(children: [
                              Icon(
                                  _public == public
                                      ? Icons.check_circle_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  size: 24,
                                  color: _public == public
                                      ? ChannelTokens.action(context)
                                      : ChannelTokens.hint),
                              const SizedBox(width: 14),
                              Expanded(
                                  child: Text(
                                      channelText(context, public ? '公开' : '私密',
                                          public ? 'Public' : 'Private'),
                                      style: const TextStyle(fontSize: 16))),
                            ])))),
              ],
            ])),
            const SizedBox(height: 10),
            _caption(channelText(
                context,
                _public ? '公共频道可以在搜索中找到，任何人都可以加入' : '私密频道不能通过频道别名加入，可以通过邀请链接加入',
                _public
                    ? 'Anyone can find this channel by its alias and subscribe.'
                    : 'Private channels can be subscribed to through an invitation link.')),
            const SizedBox(height: 28),
            _caption(channelText(context, '邀请链接', 'Invitation link')),
            const SizedBox(height: 10),
            _card(Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(children: [
                  Container(
                      constraints: const BoxConstraints(minHeight: 54),
                      padding: const EdgeInsets.only(left: 14),
                      decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerLow
                              : ChannelTokens.linkFill,
                          borderRadius: BorderRadius.circular(10)),
                      child: Row(children: [
                        Expanded(
                            child: Text(
                                channelText(
                                    context, '链接暂不可用', 'Link unavailable'),
                                style: const TextStyle(fontSize: 16))),
                        IconButton(
                            onPressed: null,
                            tooltip: channelText(context, '复制链接', 'Copy link'),
                            icon: const Icon(Icons.copy_rounded)),
                      ])),
                  const SizedBox(height: 14),
                  SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                          onPressed: null,
                          style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10))),
                          child: Text(
                              channelText(context, '分享链接', 'Share link'),
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600)))),
                ]))),
            const SizedBox(height: 10),
            _caption(channelText(context, '任何人可以通过点击这个链接加入你的频道',
                'Anyone with this link can join your channel.')),
          ]));
  Widget _caption(String text) => Text(text,
      style: TextStyle(fontSize: 14, color: ChannelTokens.muted(context)));
  Widget _card(Widget child) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
          color: ChannelTokens.surface(context),
          borderRadius: BorderRadius.circular(ChannelTokens.cardRadius)),
      child: child);
}
