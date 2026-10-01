import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

class ChatHistorySearchPage extends StatefulWidget {
  const ChatHistorySearchPage({super.key, required this.conversationID});
  final String conversationID;
  @override
  State<ChatHistorySearchPage> createState() => _ChatHistorySearchPageState();
}

class _ChatHistorySearchPageState extends State<ChatHistorySearchPage> {
  final input = TextEditingController();
  final results = <Message>[];
  bool loading = false, more = false, failed = false;
  int generation = 0, page = 1;
  String query = '';
  Future<void> search({bool next = false}) async {
    if (next && loading) return;
    final current = ++generation;
    if (!next) {
      query = input.text.trim();
      page = 1;
      results.clear();
    }
    setState(() {
      loading = query.isNotEmpty;
      failed = false;
      more = false;
    });
    if (query.isEmpty) return;
    try {
      final response = await OpenIM.iMManager.messageManager
          .searchLocalMessages(
              conversationID: widget.conversationID,
              keywordList: [query],
              messageTypeList: [MessageType.text],
              pageIndex: page,
              count: 30);
      if (!mounted || current != generation) return;
      final messages = response.searchResultItems
              ?.expand((e) => e.messageList ?? <Message>[])
              .toList() ??
          <Message>[];
      setState(() {
        results.addAll(messages);
        more = messages.length >= 30;
        page++;
      });
    } catch (_) {
      if (mounted && current == generation) setState(() => failed = true);
    } finally {
      if (mounted && current == generation) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: GlassAppBar(title: Text('findChatContent'.tr)),
        body: SafeArea(
            child: Column(children: [
          Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: input,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => search(),
                decoration: InputDecoration(
                    hintText: StrRes.search,
                    suffixIcon: IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () => search())),
              )),
          if (loading) const LinearProgressIndicator(),
          if (failed)
            TextButton(
                onPressed: () => search(), child: Text('chatSearchRetry'.tr)),
          if (!loading && !failed && query.isNotEmpty && results.isEmpty)
            Text('chatSearchEmpty'.tr),
          Expanded(
              child: ListView.builder(
                  itemCount: results.length + (more ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == results.length)
                      return TextButton(
                          onPressed: loading ? null : () => search(next: true),
                          child: Text('chatSearchMore'.tr));
                    final message = results[i];
                    return ListTile(
                        title: Text(message.textElem?.content ?? ''),
                        subtitle: Text(
                            '${message.senderNickname ?? ''}  ${DateTime.fromMillisecondsSinceEpoch(message.sendTime ?? 0).toLocal()}'));
                  })),
        ])),
      );
}

