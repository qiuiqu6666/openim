import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../chat/chat_logic.dart';
import '../chat/messages/selection/message_selection_action_bar.dart';
import '../chat/messages/selection/message_selection_toolbar.dart';
import 'history/ai_openim_message_text.dart';
import 'navigation/ai_assistant_header.dart';
import 'presentation/ai_assistant_widgets.dart';
import 'presentation/composer/ai_openim_composer.dart';
import 'presentation/messages/ai_assistant_streaming_list.dart';

/// The official assistant's SDK conversation, presented in the Mine AI style.
/// ChatBinding owns the same ChatLogic used by ordinary OpenIM conversations.
class AiAssistantChatPage extends StatefulWidget {
  const AiAssistantChatPage({super.key, this.logic});

  final ChatLogic? logic;

  @override
  State<AiAssistantChatPage> createState() => _AiAssistantChatPageState();
}

class _AiAssistantChatPageState extends State<AiAssistantChatPage> {
  late final ChatLogic _logic =
      widget.logic ?? Get.find<ChatLogic>(tag: GetTags.chat);
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searching = false;
  int _activeMatch = 0;

  List<Message> get _matches {
    final needle = _search.text.trim().toLowerCase();
    if (!_searching || needle.isEmpty) return const [];
    return _logic.messageList
        .where((message) =>
            !message.isNotificationType &&
            aiOpenimMessageText(message).toLowerCase().contains(needle))
        .toList();
  }

  void _toggleSearch(bool value) {
    _logic.focusNode.unfocus();
    setState(() {
      _searching = value;
      _activeMatch = 0;
      _search.clear();
    });
    if (value) {
      _searchFocus.requestFocus();
    } else {
      _searchFocus.unfocus();
    }
  }

  void _queryChanged() {
    setState(() => _activeMatch = 0);
    _jumpToMatch();
  }

  void _stepMatch(int delta) {
    final matches = _matches;
    if (matches.isEmpty) return;
    setState(() => _activeMatch = (_activeMatch + delta) % matches.length);
    _jumpToMatch();
  }

  void _jumpToMatch() {
    final matches = _matches;
    if (matches.isEmpty) return;
    unawaited(_logic
        .jumpToDateMessage(matches[_activeMatch.clamp(0, matches.length - 1)]));
  }

  String _text(String zh, String en) =>
      AiAssistantI18n.of(context).t(zhHans: zh, en: en);

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final toolbarHeight = math.max(
        kToolbarHeight,
        media.textScaler.scale(AiMetrics.font17) * 1.2 +
            media.textScaler.scale(AiMetrics.font11) * 1.2 +
            AiMetrics.space12);
    return AppSystemBars(
      background: AiPalette.headerBg(dark),
      navigationBackground: AiPalette.canvasBg(dark),
      child: ListenableBuilder(
        listenable: _logic.messageSelection,
        builder: (context, _) => PopScope(
          canPop: !_searching && !_logic.messageSelection.active,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (_logic.messageSelection.active) {
              _logic.messageSelection.cancel();
            } else if (_searching) {
              _toggleSearch(false);
            }
          },
          child: Scaffold(
            resizeToAvoidBottomInset: true,
            backgroundColor: AiPalette.canvasBg(dark),
            appBar: PreferredSize(
              preferredSize: Size.fromHeight(toolbarHeight),
              child: _logic.messageSelection.active
                  ? MessageSelectionToolbar(controller: _logic.messageSelection)
                  : ListenableBuilder(
                      listenable: _logic.assistantStreams,
                      builder: (context, _) => Obx(() {
                        final matches = _matches;
                        return AiAssistantHeader(
                          dark: dark,
                          userID: _logic.userID,
                          ex: _logic.conversationInfo.ex,
                          title: _logic.userID == 'assistant'
                              ? _text('AI助理', 'AI Assistant')
                              : _logic.nickname.value,
                          subtitle: _logic.assistantStreams.snapshots.isNotEmpty
                              ? _text('正在回复…', 'Replying…')
                              : _logic.peerTyping.value
                                  ? _text('正在输入…', 'Typing…')
                                  : _text('官方助理 · 你的专属对话',
                                      'Official assistant · Your personal chat'),
                          toolbarHeight: toolbarHeight,
                          searching: _searching,
                          searchController: _search,
                          searchFocus: _searchFocus,
                          matches: matches.length,
                          activeMatch: matches.isEmpty
                              ? 0
                              : _activeMatch.clamp(0, matches.length - 1),
                          onQuery: _queryChanged,
                          onStep: _stepMatch,
                          onSearch: () => _toggleSearch(true),
                          onBack: () {
                            if (_searching) {
                              _toggleSearch(false);
                            } else {
                              Navigator.of(context).maybePop();
                            }
                          },
                        );
                      }),
                    ),
            ),
            body: SafeArea(
              top: false,
              child: Stack(
                children: [
                  Positioned.fill(
                      child:
                          IgnorePointer(child: AiCanvasBackdrop(dark: dark))),
                  Column(
                    children: [
                      Expanded(
                        child: Stack(
                          children: [
                            AiAssistantStreamingList(
                              logic: _logic,
                              query: _searching ? _search.text : '',
                              emptyView: AiEmptyChatArt(
                                  dark: dark,
                                  assistantName: _text('AI助理', 'AI Assistant'),
                                  i18n: AiAssistantI18n.of(context),
                                  onStart: () =>
                                      _logic.focusNode.requestFocus()),
                            ),
                            Obx(() =>
                                _logic.newMessages.unseenCount.value > 0 ||
                                        _logic.newMessages.awayFromLatest.value
                                    ? Positioned(
                                        right: AiMetrics.space16,
                                        bottom: AiMetrics.space16,
                                        child: NewMessageIndicator(
                                            newMessageCount: _logic
                                                .newMessages.unseenCount.value,
                                            onTap: _logic.scrollBottom))
                                    : const SizedBox.shrink()),
                          ],
                        ),
                      ),
                      Obx(() => _logic.peerTyping.value
                          ? Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AiMetrics.space16,
                                  vertical: AiMetrics.space8),
                              child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Semantics(
                                      liveRegion: true,
                                      child: AiThinkingCard(
                                          dark: dark,
                                          i18n: AiAssistantI18n.of(context)))))
                          : const SizedBox.shrink()),
                      if (_logic.messageSelection.active)
                        MessageSelectionActionBar(
                            controller: _logic.messageSelection),
                      Offstage(
                        offstage: _logic.messageSelection.active,
                        child: AiOpenIMComposer(logic: _logic),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
