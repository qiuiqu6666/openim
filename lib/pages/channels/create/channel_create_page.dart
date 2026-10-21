import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../models/channel_preview.dart';
import '../presentation/channel_ui.dart';
import '../presentation/channel_avatar.dart';
import '../presentation/channel_tokens.dart';

class ChannelCreatePage extends StatefulWidget {
  const ChannelCreatePage({super.key, this.onSubmit});
  final Future<void> Function(ChannelPreview)? onSubmit;
  @override
  State<ChannelCreatePage> createState() => _ChannelCreatePageState();
}

class _ChannelCreatePageState extends State<ChannelCreatePage> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  Uint8List? _avatar;
  bool _continuing = false;
  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_continuing || _name.text.trim().isEmpty) return;
    setState(() => _continuing = true);
    FocusManager.instance.primaryFocus?.unfocus();
    final draft = ChannelPreview(
        name: _name.text.trim(), description: _description.text.trim())
      ..avatar = _avatar;
    try {
      await widget.onSubmit?.call(draft);
      if (!mounted) {
        draft.dispose();
        return;
      }
      Navigator.pop(context, draft);
    } catch (_) {
      draft.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(channelText(context, '创建未完成，请检查网络后重试',
                'Creation incomplete. Check your connection and retry.'))));
      }
    } finally {
      if (mounted) setState(() => _continuing = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_continuing,
      child: ChannelScaffold(
          backLabel: true,
          onBack: () {
            if (!_continuing) Navigator.of(context).maybePop();
          },
          title: channelText(context, '创建频道', 'Create channel'),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 42, 16, 24),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _card(
                      Row(children: [
                        ChannelAvatar(
                            bytes: _avatar,
                            onChanged: (bytes) =>
                                setState(() => _avatar = bytes)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: TextField(
                          key: const Key('channel-name'),
                          controller: _name,
                          maxLength: 30,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(fontSize: 18),
                          decoration: _input(
                              channelText(context, '频道名称', 'Channel name')),
                        )),
                      ]),
                      94),
                  const SizedBox(height: 16),
                  _card(
                      TextField(
                          key: const Key('channel-introduction'),
                          controller: _description,
                          maxLength: 200,
                          decoration: _input(channelText(context, '频道简介（选填）',
                              'Channel description (optional)'))),
                      50),
                  const SizedBox(height: 14),
                  Text(
                      channelText(context, '为频道设置简介',
                          'Add a description for your channel'),
                      style: TextStyle(
                          fontSize: 13, color: ChannelTokens.muted(context))),
                  const SizedBox(height: 44),
                  FilledButton(
                      key: const Key('channel-next'),
                      onPressed: _continuing ||
                              _name.text.trim().isEmpty
                          ? null
                          : _next,
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: MediaQuery.highContrastOf(context)
                              ? ChannelTokens.button(context)
                              : ChannelTokens.formBlue,
                          disabledBackgroundColor: ChannelTokens.disabled,
                          foregroundColor: AppTokens.onAccent,
                          disabledForegroundColor: AppTokens.onAccent,
                          textStyle: TextStyle(
                              fontFamily: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.fontFamily,
                              fontSize: 17,
                              fontWeight: FontWeight.w600),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9))),
                      child: Text(_continuing
                          ? channelText(context, '创建中…', 'Creating…')
                          : widget.onSubmit == null
                              ? channelText(context, '下一步', 'Next')
                              : channelText(
                                  context, '创建频道', 'Create channel'))),
                ]),
          )));
  InputDecoration _input(String hint) => InputDecoration(
      filled: false,
      hintText: hint,
      hintStyle: const TextStyle(color: ChannelTokens.hint),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      counterText: '');
  Widget _card(Widget child, double height) => Container(
      constraints: BoxConstraints(minHeight: height),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
          color: ChannelTokens.surface(context),
          borderRadius: BorderRadius.circular(ChannelTokens.formRadius)),
      child: child);
}
