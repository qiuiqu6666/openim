import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

class MessageSelectionPage extends StatefulWidget {
  const MessageSelectionPage(
      {super.key, required this.messages, this.initialID});
  final List<Message> messages;
  final String? initialID;
  @override
  State<MessageSelectionPage> createState() => _MessageSelectionPageState();
}

class _MessageSelectionPageState extends State<MessageSelectionPage> {
  final selected = <String>{};
  @override
  void initState() {
    super.initState();
    if (widget.initialID != null) selected.add(widget.initialID!);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: GlassAppBar(
            title: Text('${'sdkMergeForward'.tr} (${selected.length}/100)'),
            actions: [
              TextButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.pop(
                          context,
                          widget.messages
                              .where((m) => selected.contains(m.clientMsgID))
                              .toList()),
                  child: Text(StrRes.determine)),
            ]),
        body: ListView.builder(
            itemCount: widget.messages.length,
            itemBuilder: (_, i) {
              final m = widget.messages[i];
              return CheckboxListTile(
                  value: selected.contains(m.clientMsgID),
                  title: Text(IMUtils.parseMsg(m),
                      maxLines: 3, overflow: TextOverflow.ellipsis),
                  subtitle: Text(m.senderNickname ?? ''),
                  onChanged: (checked) => setState(() {
                        if (checked == true &&
                            selected.length < 100 &&
                            m.clientMsgID != null) {
                          selected.add(m.clientMsgID!);
                        } else if (checked != true) {
                          selected.remove(m.clientMsgID);
                        }
                      }));
            }),
      );
}
