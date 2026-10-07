import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:intl/intl.dart';
import 'package:openim_common/openim_common.dart';

import 'conversation_peek_loader.dart';
import 'conversation_peek_message.dart';

/// Recent history at the bottom, with read-only paging toward older messages.
class ConversationPeekContent extends StatefulWidget {
  const ConversationPeekContent({
    super.key,
    required this.loader,
    required this.conversation,
  });

  final ConversationPeekLoader loader;
  final ConversationInfo conversation;

  @override
  State<ConversationPeekContent> createState() =>
      _ConversationPeekContentState();
}

class _ConversationPeekContentState extends State<ConversationPeekContent> {
  final _scroll = ScrollController();
  static const _olderThreshold = 72.0;
  static const _padding = EdgeInsets.fromLTRB(12, 28, 12, 4);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    // Loading starts after the route's first build, avoiding notifications
    // while its parent ListenableBuilder is mounting.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.loader.loadInitial());
    });
  }

  void _onScroll() {
    final loader = widget.loader;
    if (!_scroll.hasClients ||
        !loader.loaded ||
        loader.loadingOlder ||
        loader.olderError != null ||
        !loader.hasMoreOlder) {
      return;
    }
    if (_scroll.position.extentAfter < _olderThreshold) {
      unawaited(loader.loadOlder());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String _text(BuildContext context, String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  Widget _retry(BuildContext context, VoidCallback onRetry,
          {bool compact = false}) =>
      TextButton.icon(
        key: ValueKey(compact
            ? 'conversation-peek-older-retry'
            : 'conversation-peek-retry'),
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded, size: 17),
        label: Text(_text(context, '重试', 'Retry')),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.loader,
        builder: (context, _) {
          final loader = widget.loader;
          final messages = loader.messages;
          final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
          if (messages.isEmpty) {
            if (loader.loading || loader.loadingOlder) {
              return const Center(
                  child: SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2)));
            }
            if (loader.error != null) {
              return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_text(context, '加载失败，请重试', 'Unable to load messages'),
                      style: TextStyle(fontSize: 14, color: secondary)),
                  const SizedBox(height: 12),
                  _retry(context, () => unawaited(loader.loadInitial())),
                ]),
              );
            }
            return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                  loader.isCurrent
                      ? _text(context, '暂无消息', 'No messages')
                      : _text(
                          context, '会话已失效', 'This session is no longer active'),
                  style: TextStyle(fontSize: 14, color: secondary)),
              if (loader.olderError != null)
                _retry(context, () => unawaited(loader.retryOlder()),
                    compact: true)
              else if (loader.loaded && loader.hasMoreOlder)
                TextButton(
                  key: const ValueKey('conversation-peek-load-older'),
                  onPressed: () => unawaited(loader.loadOlder()),
                  child:
                      Text(_text(context, '加载更早消息', 'Load earlier messages')),
                ),
            ]));
          }
          final items = _items(messages);
          // A short latest page cannot generate a scroll event. Fill only an
          // undersized non-empty window so older history remains reachable.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                _scroll.hasClients &&
                _scroll.position.maxScrollExtent == 0 &&
                loader.loaded &&
                !loader.loadingOlder &&
                loader.hasMoreOlder &&
                loader.olderError == null &&
                loader.isCurrent) {
              unawaited(loader.loadOlder());
            }
          });
          return Stack(children: [
            ListView.builder(
              key: const ValueKey('conversation-peek-history'),
              controller: _scroll,
              reverse: true,
              physics: Theme.of(context).platform == TargetPlatform.iOS
                  ? const BouncingScrollPhysics()
                  : const ClampingScrollPhysics(),
              padding: _padding,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[items.length - index - 1];
                if (item case final Message message) {
                  return ConversationPeekMessage(
                    key: ValueKey(
                        'conversation-peek-message-${message.clientMsgID}'),
                    message: message,
                    isGroupChat: widget.conversation.isGroupChat,
                    peerName: widget.conversation.showName ?? '',
                  );
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(formatChatMessageTime(context, item as int),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: secondary)),
                );
              },
            ),
            if (loader.loadingOlder)
              const Positioned(
                  top: 6,
                  left: 0,
                  right: 0,
                  child: Center(
                      child: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2)))),
            if (loader.olderError != null || loader.error != null)
              Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: Center(
                      child: Material(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          child: _retry(
                              context, () => unawaited(loader.retry()),
                              compact: true)))),
          ]);
        },
      );

  List<Object> _items(List<Message> messages) {
    final items = <Object>[];
    String? previousDay;
    for (final message in messages) {
      final timestamp = message.sendTime;
      if (timestamp != null && timestamp > 0) {
        final day = DateFormat('yyyy/MM/dd')
            .format(DateTime.fromMillisecondsSinceEpoch(timestamp));
        if (previousDay != day) items.add(timestamp);
        previousDay = day;
      }
      items.add(message);
    }
    return items;
  }
}
