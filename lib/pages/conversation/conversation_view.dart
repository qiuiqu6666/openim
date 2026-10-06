import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'conversation_logic.dart';
import 'archive/archived_conversation_page.dart';
import 'conversation_organizer.dart';
import 'folders/conversation_folder_bar.dart';
import 'folders/conversation_folder_controller.dart';
import 'folders/conversation_folder_swipe_region.dart';
import '../home/home_quick_actions.dart';
import '../customer_service/customer_service.dart';
import '../group_features/live/widgets/live_list_scope.dart';
import 'widgets/conversation_feed_style.dart';
import 'widgets/conversation_feed_row.dart';
import 'widgets/conversation_header_actions.dart';
import 'widgets/conversation_slide_scope.dart';
import 'editing/conversation_edit_controller.dart';
import 'editing/conversation_edit_action_bar.dart';
import 'editing/conversation_edit_actions.dart';
import 'peek/conversation_peek_entry.dart';
import 'empty/conversation_empty_state.dart';

class ConversationPage extends StatefulWidget {
  const ConversationPage(
      {super.key,
      this.groupChats = false,
      this.archivedOnly = false,
      this.liveUpdatesActive = true,
      this.onEditActionBarChanged});

  final bool groupChats;
  final bool archivedOnly;
  final bool liveUpdatesActive;
  final ValueChanged<Widget?>? onEditActionBarChanged;

  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  static const _orangeAction = Color(0xFFF5A623);
  static const _folderAction = Color(0xFF32ADE6);
  static const _muteAction = Color(0xFF006EFF);
  static const _deleteAction = Color(0xFFFF584C);
  double _plusTurns = 0;
  final _plusActionKey = GlobalKey();
  bool _quickMenuOpen = false;
  bool _switchingEditing = false;
  final _editor = ConversationEditController();
  final _feedScrollController = ScrollController();
  bool _publishedEditBar = false;
  int _editBarPublication = 0;
  final logic = Get.find<ConversationLogic>();
  late final _editActions = ConversationEditActions(
      logic: logic, editor: _editor, isMounted: () => mounted);
  late final _folders = ConversationFolderController(logic: logic);
  final Map<String, SlidableController> _slideControllers = {};

  Future<void> _showQuickActions() async {
    if (_quickMenuOpen) return;
    _quickMenuOpen = true;
    setState(() => _plusTurns += .125);
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    try {
      await showHomeQuickActions(
          context: context,
          anchor: _plusActionKey,
          actions: [
            HomeQuickAction(
                id: 'addFriend',
                title: StrRes.addFriend,
                subtitle:
                    zh ? '通过账号/手机号搜索好友' : 'Find friends by account or phone',
                onTap: logic.addFriend),
            HomeQuickAction(
                id: 'addGroup',
                title: StrRes.addGroup,
                subtitle: zh ? '通过群号搜索群聊' : 'Find a group by its ID',
                onTap: logic.addGroup),
            HomeQuickAction(
                id: 'createGroup',
                title: StrRes.createGroup,
                subtitle: zh ? '发起多人聊天' : 'Start a group conversation',
                onTap: logic.createGroup),
          ]);
    } finally {
      _quickMenuOpen = false;
      if (mounted) setState(() => _plusTurns += .125);
    }
  }

  void _closeOpenItems() {
    for (final controller in _slideControllers.values) {
      if (controller.ratio != 0 && !controller.closing) {
        controller.close();
      }
    }
  }

  Future<void> _showPeek(ConversationInfo info) async {
    if (_editor.editing || _editor.busy || _folders.busy) return;
    _closeOpenItems();
    await showFeedConversationPeek(
      context: context,
      conversation: info,
      logic: logic,
      folders: _folders,
      isActive: () => mounted && !_editor.editing && !_editor.busy,
      onDelete: (item) => _confirmDeleteConversation(context, item),
    );
  }

  void _onFolderSwipe(int direction) {
    final target = conversationFolderAfterSwipe(
      folderIds: _folders.displayFolders.map((folder) => folder.id).toList(),
      selectedFolderId: _folders.selectedFolderID,
      direction: direction,
    );
    if (!target.changed) return;
    _closeOpenItems();
    _folders.selectFolder(target.folderId);
  }

  Future<void> _toggleEditing() async {
    if (_switchingEditing || _folders.busy || !logic.isSessionActive) return;
    _switchingEditing = true;
    try {
      _closeOpenItems();
      if (_folders.reorderEditing) await _folders.finishReordering();
      if (mounted && logic.isSessionActive) _editor.toggleEditing();
    } finally {
      _switchingEditing = false;
    }
  }

  void _showCustomerService() => showCustomerServiceSheet(context);

  void _scrollToTop() {
    if (_feedScrollController.hasClients) {
      _feedScrollController.animateTo(0,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  void _publishEditBar(Widget? bar) {
    final publish = widget.onEditActionBarChanged;
    if (publish == null || (bar == null && !_publishedEditBar)) return;
    _publishedEditBar = bar != null;
    final revision = ++_editBarPublication;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && revision == _editBarPublication) publish(bar);
    });
  }

  Widget _buildEditActionBar(List<ConversationInfo> conversations) =>
      ConversationEditActionBar(
          hasSelection: conversations
              .any((info) => _editor.selectedIds.contains(info.conversationID)),
          busy: _editor.busy,
          onMarkRead: () => _editActions.markRead(conversations),
          onArchive: () => _editActions.archive(conversations),
          onDelete: () => _editActions.delete(context, conversations));

  @override
  void dispose() {
    final publish = widget.onEditActionBarChanged;
    if (_publishedEditBar && publish != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => publish(null));
    }
    _slideControllers.clear();
    _folders.dispose();
    _editor.dispose();
    _feedScrollController.dispose();
    super.dispose();
  }

  Future<void> _confirmDeleteConversation(
      BuildContext context, ConversationInfo info) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(StrRes.delete),
        content: Text(
            '${StrRes.delete} "${logic.getShowName(info)}"?\n${StrRes.confirmClearChatHistory}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(StrRes.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(StrRes.delete),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted && logic.isSessionActive) {
      await logic.deleteConversation(info);
    }
  }

  Widget _swipeAction({
    required Color color,
    required String label,
    required void Function(BuildContext) onPressed,
  }) =>
      CustomSlidableAction(
        autoClose: false,
        onPressed: (context) async {
          await Slidable.of(context)?.close();
          if (context.mounted) onPressed(context);
        },
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: EdgeInsets.zero,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => widget.archivedOnly
      ? ArchivedConversationPage(groupChats: widget.groupChats)
      : GroupLiveListScope(
          store: logic.groupFeatures,
          userID: OpenIM.iMManager.userID,
          sessionCurrent: () => logic.isSessionActive,
          active: widget.liveUpdatesActive,
          child: ListenableBuilder(
            listenable: Listenable.merge(
                [FriendDisplayPreferences.changes, _editor, _folders]),
            builder: (context, _) => _build(context),
          ));

  Widget _build(BuildContext context) {
    return Obx(() {
      final archivedConversations = logic.list
          .where((info) =>
              (widget.groupChats ? info.isGroupChat : info.isSingleChat) &&
              logic.isArchived(info))
          .toList();
      final conversations = logic.list
          .where((info) =>
              !logic.isArchived(info) &&
              (_folders.selectedFolderID != null
                  ? logic.folderID(info) == _folders.selectedFolderID
                  : (widget.groupChats ? info.isGroupChat : info.isSingleChat)))
          .toList();
      _publishEditBar(
          _editor.editing ? _buildEditActionBar(conversations) : null);
      return Scaffold(
        backgroundColor: ConversationFeedStyle.background(context),
        appBar: GlassAppBar(
          toolbarHeight: kToolbarHeight,
          backgroundColor: ConversationFeedStyle.background(context),
          foregroundColor: AppTokens.textPrimary(
              dark: Theme.of(context).brightness == Brightness.dark),
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          centerTitle: false,
          titleSpacing: 16,
          systemOverlayStyle: AppSystemBars.styleFor(
              Theme.of(context).brightness == Brightness.dark
                  ? AppTokens.backgroundDark
                  : AppTokens.surfaceLight),
          title: GestureDetector(
            onDoubleTap: _scrollToTop,
            child: MainTabTitle(
              title: widget.groupChats
                  ? StrRes.groupChat
                  : (Localizations.localeOf(context).languageCode == 'zh'
                      ? '消息'
                      : 'Messages'),
              busy: logic.imSdkStatus != null && !logic.isFailedSdkStatus,
              failed: logic.isFailedSdkStatus,
            ),
          ),
          actions: [
            ConversationHeaderActions(
                editing: _editor.editing,
                onSupport: _showCustomerService,
                onToggleEditing: _toggleEditing,
                plusKey: _plusActionKey,
                plusTurns: _plusTurns,
                onPlus: _showQuickActions),
          ],
        ),
        body: Column(
          children: [
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppTokens.backgroundDark
                    : AppTokens.surfaceLight,
                border: Border(
                    bottom: BorderSide(
                        color: ConversationFeedStyle.divider(context),
                        width: ConversationFeedStyle.dividerHeight)),
              ),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Material(
                color: Theme.of(context).brightness == Brightness.dark
                    ? AppTokens.surfaceDark
                    : AppTokens.surfaceAltLight,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: logic.globalSearch,
                  child: SizedBox(
                    height: 40,
                    child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(children: [
                          Icon(Icons.search,
                              size: 19,
                              color: AppTokens.textPrimary(
                                      dark: Theme.of(context).brightness ==
                                          Brightness.dark)
                                  .withValues(alpha: .7)),
                          const SizedBox(width: 8),
                          Text(StrRes.search,
                              style: TextStyle(
                                  fontSize: 15,
                                  color: AppTokens.textPrimary(
                                          dark: Theme.of(context).brightness ==
                                              Brightness.dark)
                                      .withValues(alpha: .7))),
                        ])),
                  ),
                ),
              ),
            ),
            ConversationFolderBar(
              folders: _folders.displayFolders,
              selectedFolderID: _folders.selectedFolderID,
              unreadForFolder: _unreadForFolder,
              hasNotifiableUnreadForFolder: _hasNotifiableUnreadForFolder,
              onSelectAll: () => _folders.selectFolder(null),
              onSelectFolder: _folders.selectFolder,
              onCreateFolder: () => _folders.createFolder(context),
              onFolderLongPress: (folder) =>
                  _folders.manageFolder(context, folder),
              reorderEditing: _folders.reorderEditing,
              onExitReorderEditing: _folders.finishReordering,
              onReorderFolders: _folders.busy ? null : _folders.previewReorder,
              onDeleteFolder: _folders.busy
                  ? null
                  : (folder) => _folders.deleteFolder(context, folder),
            ),
            Expanded(
              child: ConversationFolderSwipeRegion(
                enabled: logic.folders.isNotEmpty &&
                    !_editor.editing &&
                    !_folders.reorderEditing &&
                    !_folders.busy,
                onSwipe: _onFolderSwipe,
                child: RefreshIndicator(
                  onRefresh: () async {
                    GroupLiveListScope.maybeOf(context)?.refreshVisible();
                    await Future.wait([
                      logic.onRefresh(),
                      logic.refreshOrganizer(),
                    ]);
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _closeOpenItems,
                    child: SlidableAutoCloseBehavior(
                      child: conversations.isEmpty &&
                              logic.imSdkStatus == null &&
                              logic.canShowEmptyFeed &&
                              (_folders.selectedFolderID != null ||
                                  archivedConversations.isEmpty)
                          ? ConversationEmptyState(
                              groupChats: widget.groupChats,
                              folderSelected: _folders.selectedFolderID != null,
                            )
                          : ListView.builder(
                              controller: _feedScrollController,
                              padding: EdgeInsets.only(
                                  bottom: MediaQuery.paddingOf(context).bottom),
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemBuilder: (_, index) {
                                if (_folders.selectedFolderID == null &&
                                    archivedConversations.isNotEmpty) {
                                  if (index == 0) {
                                    return _buildArchiveEntry(
                                        context, archivedConversations);
                                  }
                                  index--;
                                }
                                return _buildItemView(
                                    context, conversations[index],
                                    showDivider:
                                        index < conversations.length - 1);
                              },
                              itemCount: conversations.length +
                                  (_folders.selectedFolderID == null &&
                                          archivedConversations.isNotEmpty
                                      ? 1
                                      : 0),
                            ),
                    ),
                  ),
                ),
              ),
            ),
            if (_editor.editing && widget.onEditActionBarChanged == null)
              _buildEditActionBar(conversations),
          ],
        ),
      );
    });
  }

  Iterable<ConversationInfo> _folderConversations(ChatFolder folder) =>
      logic.list.where((info) =>
          !logic.isArchived(info) && logic.folderID(info) == folder.id);

  int _unreadForFolder(ChatFolder folder) => _folderConversations(folder)
      .fold(0, (sum, info) => sum + logic.getUnreadCount(info));

  bool _hasNotifiableUnreadForFolder(ChatFolder folder) =>
      _folderConversations(folder).any((info) =>
          logic.getUnreadCount(info) > 0 && !logic.isNotDisturb(info));

  Widget _buildArchiveEntry(
      BuildContext context, List<ConversationInfo> archivedConversations) {
    final unread = archivedConversations.fold<int>(
        0, (sum, info) => sum + logic.getUnreadCount(info));
    return Ink(
      color: ConversationFeedStyle.background(context),
      child: InkWell(
        onTap: () => Navigator.of(context, rootNavigator: true)
            .push(MaterialPageRoute<void>(
          builder: (_) =>
              ArchivedConversationPage(groupChats: widget.groupChats),
        )),
        child: SizedBox(
          height: ConversationFeedStyle.rowHeight(context),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: Row(children: [
              SizedBox(
                width: 54,
                height: 54,
                child: ClipOval(
                  child: Transform.scale(
                    scale: 1.5,
                    child: Image.asset(
                      'assets/images/ic_archive_99chat.png',
                      package: 'openim_common',
                      width: 54,
                      height: 54,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('归档',
                        style: TextStyle(
                            fontSize: 16,
                            height: ConversationFeedStyle.lineHeight,
                            fontWeight: FontWeight.w600,
                            color: AppTokens.textPrimary(
                                dark: Theme.of(context).brightness ==
                                    Brightness.dark))),
                    SizedBox(height: 4.w),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            archivedConversations
                                .map(logic.getShowName)
                                .join('、'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 14,
                                height: ConversationFeedStyle.lineHeight,
                                color: AppTokens.textSecondary(
                                    dark: Theme.of(context).brightness ==
                                        Brightness.dark)),
                          ),
                        ),
                        if (unread > 0) ...[
                          SizedBox(width: 8.w),
                          UnreadCountView(count: unread),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildItemView(BuildContext context, ConversationInfo info,
          {required bool showDivider}) =>
      ConversationSlideScope(
        key: ValueKey('slide-scope-${info.conversationID}'),
        onCreated: (controller) =>
            _slideControllers[info.conversationID] = controller,
        onDisposed: (controller) {
          if (identical(_slideControllers[info.conversationID], controller)) {
            _slideControllers.remove(info.conversationID);
          }
        },
        builder: (context, controller) => Slidable(
          key: ValueKey(info.conversationID),
          enabled: !_editor.editing,
          controller: controller,
          startActionPane: ActionPane(
            motion: const BehindMotion(),
            extentRatio: 0.42,
            openThreshold: 0.12,
            closeThreshold: 0.38,
            children: [
              _swipeAction(
                onPressed: (_) => logic.updateOrganizer(info,
                    folderID: logic.folderID(info),
                    archived: !logic.isArchived(info)),
                color: logic.isArchived(info) ? _muteAction : _orangeAction,
                label: logic.isArchived(info) ? '取消归档' : '归档',
              ),
              _swipeAction(
                onPressed: (_) => _folders.selectedFolderID != null
                    ? _folders.removeFromFolder(info)
                    : _folders.chooseFolder(context, info),
                color: _folders.selectedFolderID != null
                    ? const Color(0xFF8E8E93)
                    : _folderAction,
                label: _folders.selectedFolderID != null ? '移出分组' : '分组',
              ),
            ],
          ),
          endActionPane: ActionPane(
            motion: const BehindMotion(),
            extentRatio: 0.5,
            openThreshold: 0.12,
            closeThreshold: 0.38,
            children: [
              _swipeAction(
                onPressed: (_) =>
                    logic.setNotDisturb(info, !logic.isNotDisturb(info)),
                color: _muteAction,
                label: logic.isNotDisturb(info)
                    ? StrRes.disableConversationMute
                    : StrRes.enableConversationMute,
              ),
              _swipeAction(
                onPressed: (_) => logic.setPinned(info, info.isPinned != true),
                color: _orangeAction,
                label:
                    info.isPinned == true ? StrRes.cancelTop : StrRes.topChat,
              ),
              _swipeAction(
                onPressed: (context) =>
                    _confirmDeleteConversation(context, info),
                color: _deleteAction,
                label: StrRes.delete,
              ),
            ],
          ),
          // Keep the ink surface inside the sliding transform. An Ink decoration
          // on the page's Material can retain its offset after the slide closes.
          child: ConversationFeedRow(
            logic: logic,
            info: info,
            showDivider: showDivider,
            editing: _editor.editing,
            selected: _editor.selectedIds.contains(info.conversationID),
            onTap: () {
              if (_editor.editing) {
                _editor.toggleSelection(info.conversationID);
                return;
              }
              if (controller.ratio != 0) {
                controller.close();
              } else {
                logic.toChat(conversationInfo: info);
              }
            },
            onLongPress: _editor.editing ? null : () => _showPeek(info),
          ),
        ),
      );
}
