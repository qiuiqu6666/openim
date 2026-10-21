import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../presentation/channel_ui.dart';

class ChannelComposePage extends StatefulWidget {
  const ChannelComposePage({super.key});
  @override
  State<ChannelComposePage> createState() => _ChannelComposePageState();
}

class _ChannelComposePageState extends State<ChannelComposePage> {
  final _text = TextEditingController();
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChannelScaffold(
        title: channelText(context, '发布消息', 'Publish post'),
        body: Form(
            key: _form,
            child: ListView(
                padding: const EdgeInsets.all(AppTokens.s5),
                children: [
                  TextFormField(
                      controller: _text,
                      minLines: 8,
                      maxLines: 16,
                      maxLength: 4000,
                      decoration: InputDecoration(
                          labelText:
                              channelText(context, '分享频道内容', 'Share an update'),
                          alignLabelWithHint: true,
                          border: const OutlineInputBorder()),
                      validator: (value) => value == null ||
                              value.trim().isEmpty
                          ? channelText(context, '请输入消息内容', 'Enter a message')
                          : null),
                  const SizedBox(height: AppTokens.s5),
                  Text(channelText(context, '消息将以频道身份展示。本次发布仅保留在预览中。',
                      'Posts appear under the channel identity. This post stays in the preview only.')),
                  const SizedBox(height: AppTokens.s3),
                  ListTile(
                      leading: const Icon(Icons.attach_file),
                      title: Text(channelText(
                          context, '图片、视频与文件', 'Photos, videos and files')),
                      subtitle: Text(channelText(context, '正式开放后支持',
                          'Available when channels launch')),
                      onTap: () => channelUnavailable(context)),
                ])),
        bottom: FilledButton(
            onPressed: () {
              if (_form.currentState!.validate()) {
                Navigator.pop(context, _text.text.trim());
              }
            },
            child: Text(channelText(context, '发布到预览', 'Publish to preview'))),
      );
}
