// Layout and actions adapted from 99chat's ArchivedConversationPage,
// lib/src/conversation.dart at d7c3c65 (Apache License 2.0).
// Uses the existing OpenIM conversation state and Chat organizer API.
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../conversation_logic.dart';
import '../folders/conversation_folder_controller.dart';
import '../editing/conversation_edit_action_bar.dart';
import '../editing/conversation_edit_actions.dart';
import '../editing/conversation_edit_controller.dart';
import '../widgets/conversation_feed_row.dart';
import '../widgets/conversation_feed_style.dart';
import '../widgets/conversation_header_actions.dart';
import '../widgets/conversation_slide_scope.dart';
import '../peek/conversation_peek_entry.dart';
import '../../group_features/live/widgets/live_list_scope.dart';

/// A page-owned archived scope over the same live SDK feed as the home page.
class ArchivedConversationPage extends StatefulWidget {
  const ArchivedConversationPage({super.key, this.groupChats = false});

  final bool groupChats;

  @override
  State<ArchivedConversationPage> createState() =>
      _ArchivedConversationPageState();
}

class _ArchivedConversationPageState extends State<ArchivedConversationPage> {
  final _logic = Get.find<ConversationLogic>();
  late final _folders = ConversationFolderController(logic: _logic);
  final _editor = ConversationEditController();
  final _scrollController = ScrollController();
  final _slides = <String, SlidableController>{};
  final _pendingActions = <String>{};
  late final _actions = ConversationEditActions(
      logic: _logic, editor: _editor, isMounted: () => mounted);
  bool _initialLoading = true;

  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    await _logic.refreshOrganizer();
    if (mounted && _initialLoading) {
      setState(() => _initialLoading = false);
    }
  }

  void _closeSlides() {
    for (final slide in _slides.values) {
      if (slide.ratio != 0) unawaited(slide.close());
    }
  }

  void _toggleEditing() {
    _closeSlides();
    _editor.toggleEditing();
  }

  Future<void> _perform(
      ConversationInfo info, Future<void> Function() action) async {
    final id = info.conversationID;
    if (!mounted ||
        !_logic.isSessionActive ||
        _editor.busy ||
        !_pendingActions.add(id)) {
      return;
    }
    setState(() {});
    try {
      await action();
    } finally {
      _pendingActions.remove(id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _unarchive(ConversationInfo info) => _perform(info, () async {
        await _logic.updateOrganizer(info,
            folderID: _logic.folderID(info), archived: false);
      });

  Future<void> _showPeek(ConversationInfo info) async {
    if (_editor.editing || _editor.busy || _pendingActions.isNotEmpty) return;
    _closeSlides();
    await showFeedConversationPeek(
      context: context,
      conversation: info,
      logic: _logic,
      isActive: () => mounted && !_editor.editing && !_editor.busy,
      onDelete: _confirmDelete,
      perform: _perform,
      folders: _folders,
    );
  }

  Future<void> _showMore(ConversationInfo info) async {
    final choice = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, 'pin'),
            child: Text(info.isPinned == true
                ? (_zh ? '取消置顶' : 'Unpin')
                : (_zh ? '置顶' : 'Pin')),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(sheetContext, 'unarchive'),
            child: Text(_zh ? '取消归档' : 'Unarchive'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: Text(_zh ? '取消' : 'Cancel'),
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'pin') {
      await _perform(info, () => _logic.setPinned(info, info.isPinned != true));
    } else if (choice == 'unarchive') {
      await _unarchive(info);
    }
  }

  Future<void> _confirmDelete(ConversationInfo info) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(StrRes.delete),
        content: Text(
            '${StrRes.delete} "${_logic.getShowName(info)}"?\n${StrRes.confirmClearChatHistory}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(StrRes.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(StrRes.delete)),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _perform(info, () => _logic.deleteConversation(info));
    }
  }

  Widget _swipeAction(
          String label, Color color, Future<void> Function() onPressed) =>
      CustomSlidableAction(
        autoClose: false,
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: EdgeInsets.zero,
        onPressed: (actionContext) async {
          await Slidable.of(actionContext)?.close();
          if (mounted) await onPressed();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label,
                maxLines: 1,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ),
      );

  Widget _buildRow(ConversationInfo info) {
    final pending = _pendingActions.contains(info.conversationID);
    return ConversationSlideScope(
      key: ValueKey('archived-slide-scope-${info.conversationID}'),
      onCreated: (controller) => _slides[info.conversationID] = controller,
      onDisposed: (controller) {
        if (identical(_slides[info.conversationID], controller)) {
          _slides.remove(info.conversationID);
        }
      },
      builder: (context, controller) => Slidable(
        key: ValueKey(info.conversationID),
        groupTag: 'archived-conversation-list',
        controller: controller,
        enabled: !_editor.editing && !pending,
        endActionPane: ActionPane(
          extentRatio: .5,
          motion: const DrawerMotion(),
          children: [
            _swipeAction(_zh ? '更多' : 'More', const Color(0xFFF5A623),
                () => _showMore(info)),
            _swipeAction(_zh ? '取消归档' : 'Unarchive', AppTokens.accent,
                () => _unarchive(info)),
            _swipeAction(_zh ? '删除' : 'Delete', const Color(0xFFEF3B36),
                () => _confirmDelete(info)),
          ],
        ),
        child: ConversationFeedRow(
          logic: _logic,
          info: info,
          showDivider: false,
          editing: _editor.editing,
          selected: _editor.selectedIds.contains(info.conversationID),
          archivedLayout: true,
          onTap: () {
            if (pending) return;
            if (_editor.editing) {
              _editor.toggleSelection(info.conversationID);
            } else if (controller.ratio != 0) {
              unawaited(controller.close());
            } else {
              _logic.toChat(conversationInfo: info);
            }
          },
          onLongPress:
              _editor.editing || pending ? null : () => _showPeek(info),
        ),
      ),
    );
  }

  Widget _buildBody(List<ConversationInfo> conversations) {
    final loading = _logic.organizerLoading.value;
    final error = _logic.organizerError.value;
    if (conversations.isEmpty) {
      if (_initialLoading || loading) {
        return const Center(
            child: CircularProgressIndicator(
                key: ValueKey('archived-conversation-loading'),
                color: AppTokens.accent));
      }
      if (error != null) {
        return Center(
            child: TextButton(
                key: const ValueKey('archived-conversation-retry'),
                onPressed: _refresh,
                child: Text(_zh ? '重试' : 'Retry')));
      }
      return Center(
        child: Text(
          widget.groupChats
              ? (_zh ? '暂无归档群聊' : 'No archived groups')
              : (_zh ? '暂无归档会话' : 'No archived chats'),
          style: TextStyle(
              fontSize: 14,
              color: AppTokens.textSecondary(
                  dark: Theme.of(context).brightness == Brightness.dark)),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () {
        GroupLiveListScope.maybeOf(context)?.refreshVisible();
        return _refresh();
      },
      color: AppTokens.accent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _closeSlides,
        child: SlidableAutoCloseBehavior(
          child: ListView.builder(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding:
                EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
            itemCount: conversations.length,
            itemBuilder: (_, index) => _buildRow(conversations[index]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => GroupLiveListScope(
      store: _logic.groupFeatures,
      userID: OpenIM.iMManager.userID,
      sessionCurrent: () => _logic.isSessionActive,
      child: ListenableBuilder(
        listenable:
            Listenable.merge([_editor, FriendDisplayPreferences.changes]),
        builder: (context, _) => Obx(() {
          final conversations = _logic.list
              .where((info) =>
                  (widget.groupChats ? info.isGroupChat : info.isSingleChat) &&
                  _logic.isArchived(info))
              .toList();
          final hasSelection = conversations
              .any((info) => _editor.selectedIds.contains(info.conversationID));
          final background = ConversationFeedStyle.background(context);
          return Scaffold(
            backgroundColor: background,
            appBar: GlassAppBar(
              toolbarHeight: kToolbarHeight,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              shadowColor: Colors.transparent,
              backgroundColor: background,
              foregroundColor: AppTokens.accent,
              systemOverlayStyle: AppSystemBars.styleFor(background),
              titleSpacing: 4,
              centerTitle: false,
              automaticallyImplyLeading: false,
              leading: IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              title: Text(_zh ? '已归档' : 'Archived',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.2,
                      color: AppTokens.textPrimary(
                          dark: Theme.of(context).brightness ==
                              Brightness.dark))),
              actions: [
                ConversationEditButton(
                    editing: _editor.editing,
                    onPressed: _editor.busy ? null : _toggleEditing),
              ],
            ),
            body: _buildBody(conversations),
            bottomNavigationBar: _editor.editing
                ? ConversationEditActionBar(
                    hasSelection: hasSelection,
                    busy: _editor.busy,
                    unarchive: true,
                    onMarkRead: () => _actions.markRead(conversations),
                    onArchive: () => _actions.unarchive(conversations),
                    onDelete: () => _actions.delete(context, conversations),
                  )
                : null,
          );
        }),
      ));

  @override
  void dispose() {
    _folders.dispose();
    _editor.dispose();
    _scrollController.dispose();
    _slides.clear();
    super.dispose();
  }
}
