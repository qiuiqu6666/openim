import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../cloud/chat_keyword_search_api.dart';
import 'search_context_api.dart';
import 'search_context_controller.dart';
import 'search_context_strings.dart';

/// Read-only HTTP preview. Does not instantiate ChatLogic or call SDK read APIs.
class SearchContextPageView extends StatefulWidget {
  const SearchContextPageView({super.key, required this.hit, this.api});
  final CloudKeywordMessage hit;
  final SearchContextApi? api;
  @override
  State<SearchContextPageView> createState() => _SearchContextPageViewState();
}

class _SearchContextPageViewState extends State<SearchContextPageView> {
  late final controller = SearchContextController(widget.hit, api: widget.api);
  final scroll = ItemScrollController();
  final positions = ItemPositionsListener.create();
  Timer? _sessionTimer;
  int _version = 0;
  @override
  void initState() {
    super.initState();
    controller.reload();
    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!controller.api.client.sessionCurrent) {
        _sessionTimer?.cancel();
        controller.invalidateSession();
      }
    });
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    controller.dispose();
    super.dispose();
  }

  Future<void> _more(bool before) async {
    int? seq;
    double alignment = 0;
    final visible = positions.itemPositions.value
        .where((p) =>
            p.index > 0 &&
            p.index <= controller.messages.length &&
            p.itemLeadingEdge >= 0)
        .toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    if (before && visible.isNotEmpty) {
      seq = controller.messages[visible.first.index - 1].seq;
      alignment = visible.first.itemLeadingEdge.clamp(0.0, 1.0);
    }
    await controller.more(before);
    if (!mounted || seq == null || controller.messages.isEmpty) return;
    final index = controller.messages.indexWhere((m) => m.seq == seq);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.isAttached && index >= 0) {
        scroll.jumpTo(index: index + 1, alignment: alignment);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: AppTokens.surface(dark: dark),
      appBar: AppBar(title: Text(contextText(context, 'title'))),
      body: SafeArea(
          child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                final messages = controller.messages;
                return Column(children: [
                  if (controller.loading) const LinearProgressIndicator(),
                  if (controller.errorCode != null)
                    Padding(
                        padding: const EdgeInsets.all(AppTokens.s4),
                        child: Column(children: [
                          Text(searchErrorText(context, controller.errorCode),
                              key: const ValueKey('context-error')),
                          if (![
                            1002,
                            404,
                            409,
                            410,
                            1501,
                            1502,
                            1503,
                            1504,
                            1505,
                            1506,
                            1507
                          ].contains(controller.errorCode))
                            TextButton(
                                onPressed: controller.loading
                                    ? null
                                    : () {
                                        if (controller.initialized) {
                                          _more(_lastBefore);
                                        } else {
                                          setState(() => _version++);
                                          controller.reload();
                                        }
                                      },
                                child: Text(contextText(
                                    context,
                                    controller.initialized
                                        ? 'retry'
                                        : 'reload'))),
                        ])),
                  if (messages.isNotEmpty)
                    Expanded(
                        child: ScrollablePositionedList.builder(
                      key: ValueKey(_version),
                      itemScrollController: scroll,
                      itemPositionsListener: positions,
                      initialScrollIndex:
                          messages.indexWhere((m) => m.seq == widget.hit.seq) +
                              1,
                      initialAlignment: .2,
                      itemCount: messages.length + 2,
                      itemBuilder: (context, index) {
                        if (index == 0 || index == messages.length + 1) {
                          final before = index == 0;
                          final end = before
                              ? controller.beforeEnd
                              : controller.afterEnd;
                          return Padding(
                              padding: const EdgeInsets.all(AppTokens.s3),
                              child: Center(
                                  child: end
                                      ? Text(contextText(context, 'end'))
                                      : TextButton(
                                          key: ValueKey(before
                                              ? 'context-before'
                                              : 'context-after'),
                                          onPressed: controller.loading
                                              ? null
                                              : () {
                                                  _lastBefore = before;
                                                  _more(before);
                                                },
                                          child: Text(contextText(context,
                                              before ? 'before' : 'after')))));
                        }
                        return _message(context, messages[index - 1]);
                      },
                    )),
                ]);
              })),
    );
  }

  bool _lastBefore = true;

  Widget _message(BuildContext context, Message message) {
    final theme = Theme.of(context);
    final anchor = message.seq == widget.hit.seq;
    final sender = message.senderNickname?.isNotEmpty == true
        ? message.senderNickname!
        : message.sendID ?? '';
    return Container(
      key: ValueKey('context-message-${message.seq}'),
      color: anchor ? theme.colorScheme.primaryContainer : null,
      padding: const EdgeInsets.all(AppTokens.s4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (anchor)
          Text(contextText(context, 'anchor'),
              style: theme.textTheme.labelLarge),
        Text(
            [
              sender,
              if (message.sendTime != null)
                formatChatMessageTime(context, message.sendTime!)
            ].join(' · '),
            style: theme.textTheme.labelMedium),
        const SizedBox(height: AppTokens.s2),
        if (message.hasExpired)
          Text(contextText(context, '404'))
        else if (message.contentType == MessageType.picture)
          ChatPictureView(message: message, isISend: false)
        else
          SelectableText(IMUtils.parseMsg(message),
              style: theme.textTheme.bodyLarge),
      ]),
    );
  }
}
