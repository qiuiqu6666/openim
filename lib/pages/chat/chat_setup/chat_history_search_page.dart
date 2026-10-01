import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'message_context_page.dart';

class ChatHistorySearchPage extends StatefulWidget {
  const ChatHistorySearchPage(
      {super.key,
      required this.conversationID,
      this.initialQuery = '',
      this.filesOnly = false});
  final String conversationID;
  final String initialQuery;
  final bool filesOnly;
  @override
  State<ChatHistorySearchPage> createState() => _ChatHistorySearchPageState();
}

class _ChatHistorySearchPageState extends State<ChatHistorySearchPage> {
  final input = TextEditingController();
  final results = <Message>[];
  bool loading = false, more = false, failed = false;
  int generation = 0, page = 1;
  String query = '';
  final sender = TextEditingController();
  DateTimeRange? dates;
  int? type;
  String content(Message message) => IMUtils.parseMsg(message);

  @override
  void initState() {
    super.initState();
    input.text = widget.initialQuery;
    if (widget.initialQuery.isNotEmpty) search();
  }

  Future<void> search({bool next = false}) async {
    if (next && loading) return;
    final current = ++generation;
    if (!next) {
      query = input.text.trim();
      page = 1;
      results.clear();
    }
    setState(() {
      loading = true;
      failed = false;
      more = false;
    });

    try {
      final response = await OpenIM.iMManager.messageManager
          .searchLocalMessages(
              conversationID: widget.conversationID,
              keywordList: query.isEmpty ? [] : [query],
              senderUserIDList:
                  sender.text.trim().isEmpty ? [] : [sender.text.trim()],
              searchTimePosition: dates == null
                  ? 0
                  : dates!.end
                          .add(const Duration(days: 1))
                          .millisecondsSinceEpoch ~/
                      1000,
              searchTimePeriod: dates == null
                  ? 0
                  : dates!.end
                      .add(const Duration(days: 1))
                      .difference(dates!.start)
                      .inSeconds,
              messageTypeList: widget.filesOnly
                  ? [MessageType.file]
                  : type == null
                      ? []
                      : type == MessageType.text
                          ? [
                              MessageType.text,
                              MessageType.atText,
                              MessageType.advancedText,
                              MessageType.quote
                            ]
                          : [type!],
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
    sender.dispose();
    super.dispose();
  }

  Widget _buildCategories(BuildContext context) {
    final categories = <(String, bool, VoidCallback)>[
      ('日期', dates != null, () async {
        final range = await showDateRangePicker(
          context: context, firstDate: DateTime(2000),
          lastDate: DateTime.now(), initialDateRange: dates,
        );
        if (!mounted || range == null) return;
        setState(() => dates = range);
        search();
      }),
      ('发送人', sender.text.isNotEmpty, () async {
        final editing = TextEditingController(text: sender.text);
        final value = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('按发送人查找'),
            content: TextField(controller: editing,
              decoration: const InputDecoration(hintText: '输入发送人的 IM ID')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
              TextButton(onPressed: () => Navigator.pop(context, editing.text.trim()), child: const Text('搜索')),
            ],
          ),
        );
        // Wait for the dialog's exit transition before disposing its field.
        Future.delayed(const Duration(milliseconds: 400), editing.dispose);
        if (!mounted || value == null) return;
        sender.text = value;
        search();
      }),
      if (!widget.filesOnly)
        for (final pair in [
          (MessageType.picture, '图片'), (MessageType.video, '视频'),
          (MessageType.file, '文件'), (MessageType.voice, '语音'),
        ])
          (pair.$2, type == pair.$1, () {
            setState(() => type = type == pair.$1 ? null : pair.$1);
            search();
          }),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
      child: Column(children: [
        Text('搜索指定内容', style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Styles.c_8E9AB0)),
        const SizedBox(height: 14),
        LayoutBuilder(builder: (context, constraints) => Wrap(
          children: [for (final item in categories)
            SizedBox(width: constraints.maxWidth / 3,
              child: TextButton(
                onPressed: item.$3,
                style: TextButton.styleFrom(
                  foregroundColor: Styles.c_0089FF,
                  backgroundColor: item.$2 ? Styles.c_0089FF.withValues(alpha: .08) : null,
                ),
                child: Text(item.$1),
              ),
            ),
          ],
        )),
        if (dates != null || sender.text.isNotEmpty || type != null)
          TextButton.icon(
            icon: const Icon(Icons.close, size: 16),
            label: const Text('清除筛选'),
            onPressed: () {
              dates = null; type = null; sender.clear(); search();
            },
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Styles.c_FFFFFF,
        appBar: GlassAppBar(
            centerTitle: true,
            leading: IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              icon: Icon(Icons.arrow_back_ios_new, color: Styles.c_0089FF),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(widget.filesOnly
                ? StrRes.globalSearchChatFile
                : 'findChatContent'.tr,
                style: Styles.ts_0C1C33_17sp_semibold)),
        body: SafeArea(
            child: Column(children: [
          Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: input,
                autofocus: false,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => search(),
                decoration: InputDecoration(
                    filled: true,
                    fillColor: Styles.c_F4F5F7,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    prefixIcon: IconButton(icon: const Icon(Icons.search), onPressed: () => search()),
                    hintText: StrRes.search,
                    suffixIcon: input.text.isEmpty ? null : IconButton(
                        tooltip: '清空',
                        icon: const Icon(Icons.cancel, size: 18),
                        onPressed: () { input.clear(); setState(() {}); })),
              )),
          _buildCategories(context),
          if (loading) const LinearProgressIndicator(),
          if (failed)
            TextButton(
                onPressed: () => search(), child: Text('chatSearchRetry'.tr)),
          if (!loading && !failed && generation > 0 && results.isEmpty)
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
                        onTap: () => Get.to(() => MessageContextPage(
                            conversationID: widget.conversationID,
                            target: message)),
                        title: Text(content(message),
                            maxLines: 3, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            '${message.senderNickname ?? ''}  ${DateTime.fromMillisecondsSinceEpoch(message.sendTime ?? 0).toLocal()}'));
                  })),
        ])),
      );
}
