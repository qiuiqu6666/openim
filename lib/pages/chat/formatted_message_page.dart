import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/chat/chat_formatted_text.dart';

class FormattedMessagePage extends StatefulWidget {
  const FormattedMessagePage({super.key, this.initialText = ''});
  final String initialText;
  @override
  State<FormattedMessagePage> createState() => _FormattedMessagePageState();
}

class _FormattedMessagePageState extends State<FormattedMessagePage> {
  late final TextEditingController input =
      TextEditingController(text: widget.initialText);
  final formats = <String>{};
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: GlassAppBar(title: Text('sdkRichText'.tr), actions: [
        TextButton(
            onPressed: input.text.trim().isEmpty
                ? null
                : () => Navigator.pop(context, (
                      text: input.text,
                      entities: formats
                          .map((type) => RichMessageInfo(
                              type: type, offset: 0, length: input.text.length))
                          .toList()
                    )),
            child: Text(StrRes.send)),
      ]),
      body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, children: [
              for (final pair in [
                ('bold', 'sdkBold'),
                ('italic', 'sdkItalic'),
                ('underline', 'sdkUnderline')
              ])
                FilterChip(
                    label: Text(pair.$2.tr),
                    selected: formats.contains(pair.$1),
                    onSelected: (v) => setState(() {
                          if (v) {
                            formats.add(pair.$1);
                          } else {
                            formats.remove(pair.$1);
                          }
                        }))
            ]),
            TextField(
                controller: input,
                minLines: 4,
                maxLines: 12,
                maxLength: 5000,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(hintText: 'sdkRichHint'.tr)),
            const Divider(),
            ChatFormattedText(
                text: input.text,
                entities: formats
                    .map((type) => MessageEntity(
                        type: type, offset: 0, length: input.text.length))
                    .toList()),
          ])));
}
