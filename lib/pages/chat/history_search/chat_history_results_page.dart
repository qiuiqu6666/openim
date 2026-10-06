import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:openim_common/openim_common.dart';

import '../media/chat_picture_gallery.dart';
import '../stickers/sticker_video_message.dart';
import 'chat_history_category.dart';
import 'chat_history_search_controller.dart';
import 'chat_history_search_source.dart';
import 'chat_history_search_strings.dart';
import 'chat_history_search_tokens.dart';
import 'files/chat_history_file_tile.dart';
import 'filtered_results/chat_history_filtered_results_view.dart';
import 'media/chat_history_media_grid.dart';
import 'navigation/chat_history_message_navigation.dart';
import 'selection/chat_history_date_page.dart';
import 'selection/chat_history_sender_page.dart';
import 'selection/chat_history_sender_source.dart';
import 'widgets/chat_history_keyword_results.dart';
import 'widgets/chat_history_result_tile.dart';
import 'widgets/chat_history_search_bar.dart';

/// One result-page implementation, with immutable category/conversation scope.
class ChatHistoryResultsPage extends StatefulWidget {
  const ChatHistoryResultsPage({
    super.key,
    required this.conversationID,
    this.category,
    this.initialQuery = '',
    this.date,
    this.sender,
    this.source,
    this.isGroup = false,
    this.senderSource,
    this.messageNavigation,
  });

  final String conversationID;
  final ChatHistoryCategory? category;
  final String initialQuery;
  final DateTime? date;
  final ChatHistorySender? sender;
  final ChatHistorySearchSource? source;
  final bool isGroup;
  final ChatHistorySenderSource? senderSource;
  final ChatHistoryMessageNavigation? messageNavigation;

  @override
  State<ChatHistoryResultsPage> createState() => _ChatHistoryResultsPageState();
}

class _ChatHistoryResultsPageState extends State<ChatHistoryResultsPage> {
  late final _input = TextEditingController(text: widget.initialQuery);
  late final _controller = ChatHistorySearchController(
      conversationID: widget.conversationID,
      source: widget.source,
      acceptResult: widget.category == ChatHistoryCategory.video ||
              widget.category == ChatHistoryCategory.media
          ? (message) => !isStickerVideoMessage(message)
          : null);
  late final String _userID;
  late final String? _token;
  bool _openingMedia = false;
  bool _openingCategory = false;
  bool _openingMessage = false;
  late final ChatHistoryMessageNavigation _messageNavigation;
  bool _waiting = false;
  Timer? _debounce;

  bool get _isKeyword => widget.category == null;

  bool get _sameSession =>
      OpenIM.iMManager.userID == _userID && OpenIM.iMManager.token == _token;

  bool get _isMedia =>
      widget.category == ChatHistoryCategory.media ||
      widget.category == ChatHistoryCategory.picture ||
      widget.category == ChatHistoryCategory.video;

  bool get _isFile => widget.category == ChatHistoryCategory.file;
  bool get _usesListSurface =>
      _isFile || widget.category == ChatHistoryCategory.voice;

  @override
  void initState() {
    super.initState();
    // Capture the page's account before a user can switch sessions.
    _userID = OpenIM.iMManager.userID;
    _token = OpenIM.iMManager.token;
    _messageNavigation =
        widget.messageNavigation ?? ChatHistoryMessageNavigation();
    if (!_isKeyword || _input.text.trim().isNotEmpty) _search();
  }

  void _queryChanged(String value) {
    _debounce?.cancel();
    final keyword = value.trim();
    if (keyword == _controller.query.keyword && _controller.hasSearched) {
      setState(() => _waiting = false);
      return;
    }
    _controller.clear();
    setState(() => _waiting = keyword.isNotEmpty);
    if (keyword.isEmpty) return;
    _debounce = Timer(ChatHistorySearchTokens.debounce, () {
      if (mounted && !_openingCategory) _search();
    });
  }

  Future<void> _openCategory(ChatHistoryCategory category) async {
    if (_openingCategory || !_sameSession) return;
    _openingCategory = true;
    final resumePendingSearch = _waiting;
    _debounce?.cancel();
    setState(() => _waiting = false);
    FocusScope.of(context).unfocus();
    try {
      DateTime? date;
      ChatHistorySender? sender;
      if (category == ChatHistoryCategory.date) {
        date = await Get.to<DateTime>(() => ChatHistoryDatePage(
            conversationID: widget.conversationID,
            source: _controller.source,
            isCurrent: () => mounted && _sameSession));
        if (!mounted || !_sameSession || date == null) return;
      } else if (category == ChatHistoryCategory.sender) {
        sender = await Get.to<ChatHistorySender>(() => ChatHistorySenderPage(
            conversationID: widget.conversationID,
            source: widget.senderSource));
        if (!mounted || !_sameSession || sender == null) return;
      }
      if (!mounted || !_sameSession) return;
      await Get.to<void>(() => ChatHistoryResultsPage(
          conversationID: widget.conversationID,
          category: category,
          date: date,
          sender: sender,
          initialQuery: category.supportsKeyword ? _input.text.trim() : '',
          messageNavigation: _messageNavigation,
          source: widget.source));
    } finally {
      _openingCategory = false;
      if (mounted && _sameSession && resumePendingSearch) {
        _queryChanged(_input.text);
      }
    }
  }

  Future<void> _openContext(Message message) async {
    if (_openingMessage || !mounted || !_sameSession || message.hasExpired) {
      return;
    }
    _openingMessage = true;
    FocusScope.of(context).unfocus();
    try {
      await _messageNavigation.open(context,
          conversationID: widget.conversationID,
          message: message,
          isEntryCurrent: () => mounted && _sameSession);
    } finally {
      _openingMessage = false;
    }
  }

  Future<void> _openMedia(Message message) async {
    if (_openingMedia || !_sameSession || message.hasExpired) return;
    // Private messages retain the original-message read/expiry path. They must
    // never enter a gallery whose neighbours or save action bypass that path.
    if (message.attachedInfoElem?.isPrivateChat == true ||
        isStickerVideoMessage(message)) {
      _openContext(message);
      return;
    }
    _openingMedia = true;
    try {
      final gallery = await ChatPictureGallery.fromMessages(
          _controller.results.where((item) =>
              item.attachedInfoElem?.isPrivateChat != true && !item.hasExpired),
          message);
      if (!mounted ||
          !_sameSession ||
          message.hasExpired ||
          ModalRoute.of(context)?.isCurrent != true ||
          !_controller.results.contains(message)) {
        return;
      }
      if (gallery.sources.isEmpty) {
        IMViews.showToast(chatHistorySearchText(context, 'mediaUnavailable'));
        return;
      }
      await IMUtils.previewMediaFile(
        context: context,
        message: message,
        sources: gallery.sources,
        initialIndex: gallery.initialIndex,
        onAutoPlay: (index) => gallery.sources[index].isVideo,
        onlySave: true,
      );
    } catch (_) {
      if (mounted &&
          _sameSession &&
          ModalRoute.of(context)?.isCurrent == true) {
        IMViews.showToast(chatHistorySearchText(context, 'mediaUnavailable'));
      }
    } finally {
      _openingMedia = false;
    }
  }

  Future<void> _search() async {
    _debounce?.cancel();
    if (!mounted || !_sameSession) return;
    if (_waiting) setState(() => _waiting = false);
    if (_isKeyword && _input.text.trim().isEmpty) {
      _controller.clear();
      return;
    }
    await _controller.search(ChatHistorySearchQuery(
      keyword:
          widget.category?.supportsKeyword == false ? '' : _input.text.trim(),
      messageTypes: widget.category?.messageTypes ?? const [],
      startDate: widget.date,
      endDate: widget.date,
      senderIDs: widget.sender == null ? const [] : [widget.sender!.userID],
    ));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    if (widget.category == ChatHistoryCategory.sender ||
        widget.category == ChatHistoryCategory.date) {
      final title = widget.category == ChatHistoryCategory.sender
          ? widget.sender?.name ?? widget.category!.title(context)
          : widget.date == null
              ? widget.category!.title(context)
              : DateFormat.yMMMd(Localizations.localeOf(context).toString())
                  .format(widget.date!);
      return ChatHistoryFilteredResultsView(
        controller: _controller,
        pageKey: ValueKey('chat-history-results-${widget.category!.name}'),
        title: title,
        onMessage: _openContext,
        onRefresh: _search,
      );
    }
    if (_isKeyword) {
      return Scaffold(
        key: const ValueKey('chat-history-results-keyword'),
        backgroundColor: ChatHistorySearchTokens.pageBackground(dark: dark),
        body: SafeArea(
          left: false,
          right: false,
          bottom: false,
          child: Column(children: [
            ChatHistorySearchBar(
              controller: _input,
              autofocus: true,
              onChanged: _queryChanged,
              onSubmitted: (_) => _search(),
              onCancel: () {
                _debounce?.cancel();
                FocusScope.of(context).unfocus();
                Navigator.of(context).maybePop();
              },
            ),
            Expanded(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => ChatHistoryKeywordResults(
                  controller: _controller,
                  isGroup: widget.isGroup,
                  waiting: _waiting,
                  onCategory: _openCategory,
                  onMessage: _openContext,
                  onRefresh: _search,
                ),
              ),
            ),
          ]),
        ),
      );
    }
    final listSurface = AppTokens.surface(dark: dark);
    final listForeground = AppTokens.textPrimary(dark: dark);
    final listMuted = AppTokens.textSecondary(dark: dark);
    final detail = widget.sender?.name ??
        (widget.date == null
            ? null
            : MaterialLocalizations.of(context).formatFullDate(widget.date!));
    return Scaffold(
      key: ValueKey(
          'chat-history-results-${widget.category?.name ?? 'keyword'}'),
      backgroundColor: _usesListSurface
          ? AppTokens.background(dark: dark)
          : theme.colorScheme.surface,
      appBar: GlassAppBar(
        backgroundColor: _usesListSurface ? listSurface : null,
        centerTitle: true,
        title: Text(widget.category?.title(context) ?? 'findChatContent'.tr,
            style: _usesListSurface
                ? Styles.ts_0C1C33_17sp_semibold.copyWith(color: listForeground)
                : Styles.ts_0C1C33_17sp_semibold),
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: _usesListSurface ? AppTokens.accent : Styles.c_0089FF),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
          top: false,
          child: Column(children: [
            if (widget.category?.supportsKeyword != false)
              ColoredBox(
                color: _isFile ? listSurface : Colors.transparent,
                child: Padding(
                  padding: _isFile
                      ? const EdgeInsets.symmetric(
                          horizontal: AppTokens.s5, vertical: AppTokens.s3)
                      : const EdgeInsets.all(AppTokens.s4),
                  child: TextSelectionTheme(
                    data: _isFile
                        ? theme.textSelectionTheme.copyWith(
                            cursorColor: AppTokens.accent,
                            selectionColor: AppTokens.accent.withValues(
                                alpha: ChatComposerTokens.selectionOpacity),
                            selectionHandleColor: AppTokens.accent)
                        : theme.textSelectionTheme,
                    child: SearchBox(
                      controller: _input,
                      enabled: true,
                      height: MediaQuery.textScalerOf(context)
                              .scale(AppTokens.listTitleFontSize) +
                          AppTokens.s8,
                      backgroundColor: _isFile
                          ? AppTokens.surfaceAlt(dark: dark)
                          : theme.colorScheme.surfaceContainerLow,
                      borderRadius:
                          _isFile ? BorderRadius.circular(AppTokens.rSm) : null,
                      searchIconColor: _isFile ? listMuted : null,
                      searchIcon: _isFile
                          ? Icon(Icons.search_rounded,
                              color: listMuted, size: AppTokens.chevronSize)
                          : null,
                      clearIcon: _isFile
                          ? Icon(Icons.cancel_rounded,
                              color: listMuted,
                              size: AppTokens.chevronSize,
                              semanticLabel:
                                  chatHistorySearchText(context, 'clear'))
                          : null,
                      searchIconHeight: _isFile ? AppTokens.chevronSize : null,
                      searchIconWidth: _isFile ? AppTokens.chevronSize : null,
                      textStyle: _isFile
                          ? theme.textTheme.bodyLarge
                              ?.copyWith(color: listForeground)
                          : theme.textTheme.bodyLarge,
                      hintStyle: theme.textTheme.bodyLarge?.copyWith(
                          color: _isFile
                              ? listMuted
                              : theme.colorScheme.onSurfaceVariant),
                      onSubmitted: (_) => _search(),
                      onCleared: _search,
                    ),
                  ),
                ),
              ),
            if (detail != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppTokens.s5, 0, AppTokens.s5, AppTokens.s3),
                child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(detail, style: theme.textTheme.bodyMedium)),
              ),
            Expanded(
                child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Column(children: [
                if (_controller.loading)
                  LinearProgressIndicator(
                    color: _usesListSurface ? AppTokens.accent : null,
                    backgroundColor: _usesListSurface
                        ? ChatComposerTokens.divider(dark: dark)
                        : null,
                  ),
                Expanded(
                    child: RefreshIndicator(
                  color: _usesListSurface ? AppTokens.accent : null,
                  backgroundColor: _usesListSurface ? listSurface : null,
                  onRefresh: _search,
                  child: SizedBox.expand(
                      child: _isMedia
                          ? ChatHistoryMediaGrid(
                              messages: _controller.results,
                              onTap: _openMedia,
                              footer: _footer(),
                            )
                          : ListView.separated(
                              key: const PageStorageKey(
                                  'chat-history-results-list'),
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: _usesListSurface
                                  ? const EdgeInsets.symmetric(
                                      vertical: AppTokens.s3)
                                  : null,
                              itemCount: _controller.results.length + 1,
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              separatorBuilder: (_, index) => index <
                                      _controller.results.length - 1
                                  ? Divider(
                                      height:
                                          ChatHistoryFileTokens.dividerHeight,
                                      indent:
                                          _usesListSurface ? 0 : AppTokens.s5,
                                      endIndent:
                                          _usesListSurface ? 0 : AppTokens.s5,
                                      color: _usesListSurface
                                          ? ChatComposerTokens.divider(
                                              dark: dark)
                                          : theme.dividerColor)
                                  : const SizedBox.shrink(),
                              itemBuilder: (context, index) {
                                if (index == _controller.results.length) {
                                  return _footer();
                                }
                                final message = _controller.results[index];
                                if (_isFile) {
                                  return ColoredBox(
                                    color: listSurface,
                                    child: ChatHistoryFileTile(
                                      key: ValueKey(
                                          'chat-history-result-${message.clientMsgID}'),
                                      message: message,
                                      canOpen: () => _sameSession,
                                      onPrivateTap: () => _openContext(message),
                                    ),
                                  );
                                }
                                final tile = ChatHistoryResultTile(
                                  key: ValueKey(
                                      'chat-history-result-${message.clientMsgID}'),
                                  message: message,
                                  showVoiceDetails: widget.category ==
                                      ChatHistoryCategory.voice,
                                  onTap: () => _openContext(message),
                                );
                                return _usesListSurface
                                    ? ColoredBox(
                                        color: listSurface, child: tile)
                                    : Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: ChatHistorySearchTokens
                                                .horizontalPadding),
                                        child: tile);
                              },
                            )),
                )),
              ]),
            )),
          ])),
    );
  }

  Widget _footer() {
    final theme = Theme.of(context);
    final listActionStyle = _usesListSurface
        ? TextButton.styleFrom(foregroundColor: AppTokens.accent)
        : null;
    if (_controller.loading) return const SizedBox.shrink();
    if (_controller.failed) {
      return TextButton(
          key: const ValueKey('chat-history-retry'),
          style: listActionStyle,
          onPressed: _controller.retry,
          child: Text('chatSearchRetry'.tr));
    }
    if (_controller.hasMore) {
      return TextButton(
          key: const ValueKey('chat-history-more'),
          style: listActionStyle,
          onPressed: _controller.loadMore,
          child: Text('chatSearchMore'.tr));
    }
    if (_controller.hasSearched && _controller.results.isEmpty) {
      return Padding(
          padding: const EdgeInsets.all(AppTokens.s7),
          child: Center(
              child: Text('chatSearchEmpty'.tr,
                  style: _usesListSurface
                      ? theme.textTheme.bodyMedium?.copyWith(
                          color: AppTokens.textSecondary(
                              dark: theme.brightness == Brightness.dark))
                      : null)));
    }
    return const SizedBox(height: AppTokens.s5);
  }
}
