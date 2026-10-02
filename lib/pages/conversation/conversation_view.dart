import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:sprintf/sprintf.dart';

import 'conversation_logic.dart';
import 'conversation_organizer.dart';
import 'folder_name_dialog.dart';

class ConversationPage extends StatefulWidget {
  const ConversationPage(
      {super.key, this.groupChats = false, this.archivedOnly = false});

  final bool groupChats;
  final bool archivedOnly;

  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage>
    with TickerProviderStateMixin {
  static const _orangeAction = Color(0xFFF5A623);
  static const _folderAction = Color(0xFF32ADE6);
  static const _muteAction = Color(0xFF006EFF);
  static const _deleteAction = Color(0xFFFF584C);
  final logic = Get.find<ConversationLogic>();
  final selectedFolderID = RxnString();
  final Map<String, SlidableController> _slideControllers = {};

  SlidableController _controllerFor(String id) =>
      _slideControllers.putIfAbsent(id, () => SlidableController(this));

  void _closeOpenItems() {
    for (final controller in _slideControllers.values) {
      if (controller.ratio != 0 && !controller.closing) {
        controller.close();
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _slideControllers.values) {
      controller.dispose();
    }
    selectedFolderID.close();
    super.dispose();
  }

  Future<void> _editFolder(BuildContext context, [ChatFolder? folder]) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => FolderNameDialog(initialName: folder?.name),
    );
    if (name == null || name.isEmpty) return;
    if (folder == null) {
      await logic.createFolder(name);
    } else {
      await logic.renameFolder(folder, name);
    }
  }

  Future<void> _manageFolder(BuildContext context, ChatFolder folder) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              title: const Text('重命名分组'),
              onTap: () => Navigator.pop(sheetContext, 'rename')),
          ListTile(
              title: const Text('删除分组'),
              onTap: () => Navigator.pop(sheetContext, 'delete')),
        ]),
      ),
    );
    if (action == 'rename' && context.mounted) {
      await _editFolder(context, folder);
    } else if (action == 'delete') {
      if (await logic.deleteFolder(folder) &&
          selectedFolderID.value == folder.id) {
        selectedFolderID.value = null;
      }
    }
  }

  Future<void> _organizeConversation(
      BuildContext context, ConversationInfo info) async {
    final state = logic.states[info.conversationID];
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: Icon(state?.archived == true
                ? Icons.unarchive_outlined
                : Icons.archive_outlined),
            title: Text(state?.archived == true ? '取消归档' : '归档'),
            onTap: () => Navigator.pop(sheetContext, 'archive'),
          ),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('移入分组'),
            onTap: () => Navigator.pop(sheetContext, 'folder'),
          ),
        ]),
      ),
    );
    if (action == 'archive') {
      await logic.updateOrganizer(info,
          folderID: state?.folderID, archived: !(state?.archived ?? false));
    } else if (action == 'folder' && context.mounted) {
      await _chooseFolder(context, info);
    }
  }

  Future<void> _chooseFolder(
      BuildContext context, ConversationInfo info) async {
    final folderID = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
                title: const Text('未分组'),
                onTap: () => Navigator.pop(sheetContext, '')),
            for (final folder in logic.folders)
              ListTile(
                  title: Text(folder.name),
                  onTap: () => Navigator.pop(sheetContext, folder.id)),
          ],
        ),
      ),
    );
    if (folderID != null) {
      await logic.updateOrganizer(info,
          folderID: folderID.isEmpty ? null : folderID,
          archived: logic.states[info.conversationID]?.archived ?? false);
    }
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
    if (confirmed == true) {
      logic.deleteConversation(info);
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
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: FriendDisplayPreferences.changes,
        builder: (context, _) => _build(context),
      );

  Widget _build(BuildContext context) {
    return Obx(() {
      final archivedConversations = logic.list
          .where((info) =>
              (widget.groupChats ? info.isGroupChat : info.isSingleChat) &&
              logic.isArchived(info))
          .toList();
      final conversations = logic.list
          .where((info) =>
              (widget.groupChats ? info.isGroupChat : info.isSingleChat) &&
              (widget.archivedOnly
                  ? logic.isArchived(info)
                  : selectedFolderID.value != null
                      ? logic.folderID(info) == selectedFolderID.value
                      : !logic.isArchived(info)))
          .toList();
      return Scaffold(
        backgroundColor: Styles.c_F8F9FA,
        appBar: widget.archivedOnly
            ? GlassAppBar(title: const Text('归档'))
            : TitleBar.conversation(
                statusStr: logic.imSdkStatus,
                isFailed: logic.isFailedSdkStatus,
                popCtrl: logic.popCtrl,
                onAddFriend: logic.addFriend,
                onAddGroup: logic.addGroup,
                onCreateGroup: logic.createGroup,
                left: Expanded(
                  flex: 2,
                  child: Row(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Text('消息',
                          style: TextStyle(
                              fontSize: 22.sp,
                              fontWeight: FontWeight.w700,
                              color: Styles.c_0C1C33)),
                      10.horizontalSpace,
                      if (null != logic.imSdkStatus &&
                          (!logic.reInstall || logic.isFailedSdkStatus))
                        Flexible(
                            child: SyncStatusView(
                          isFailed: logic.isFailedSdkStatus,
                          statusStr: logic.imSdkStatus!,
                        )),
                    ],
                  ),
                )),
        body: Column(
          children: [
            if (!widget.archivedOnly)
              Padding(
                padding: EdgeInsets.fromLTRB(12.w, 8.w, 12.w, 10.w),
                child: Material(
                  color: Styles.c_F0F2F6,
                  borderRadius: BorderRadius.circular(10.w),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10.w),
                    onTap: logic.globalSearch,
                    child: SizedBox(
                      height: 36.w,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search,
                              size: 18.w, color: Styles.c_8E9AB0),
                          SizedBox(width: 6.w),
                          Text('搜索',
                              style: TextStyle(
                                  fontSize: 14.sp, color: Styles.c_8E9AB0)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (!widget.archivedOnly && logic.folders.isNotEmpty)
              SizedBox(
                height: 48.w,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 9.w),
                  child: Row(
                    children: [
                      Flexible(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Styles.c_FFFFFF,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Padding(
                              padding: EdgeInsets.all(2.w),
                              child: SizedBox(
                                height: 32.w,
                                child: ListView(
                                  shrinkWrap: true,
                                  scrollDirection: Axis.horizontal,
                                  children: [
                                    _folderTab('全部', null),
                                    for (final folder in logic.folders)
                                      _folderTab(folder.name, folder.id,
                                          onLongPress: () =>
                                              _manageFolder(context, folder)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => _editFolder(context),
                        child: Container(
                          width: 32.w,
                          height: 32.w,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Styles.c_FFFFFF,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.add_rounded,
                              size: 21.w, color: const Color(0xFF8E8E93)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: logic.refreshOrganizer,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _closeOpenItems,
                  child: SlidableAutoCloseBehavior(
                    child: ListView.builder(
                      padding: EdgeInsets.only(
                          bottom: MediaQuery.paddingOf(context).bottom),
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemBuilder: (_, index) {
                        if (!widget.archivedOnly &&
                            selectedFolderID.value == null &&
                            archivedConversations.isNotEmpty) {
                          if (index == 0) {
                            return _buildArchiveEntry(
                                context, archivedConversations);
                          }
                          index--;
                        }
                        return _buildItemView(context, conversations[index]);
                      },
                      itemCount: conversations.length +
                          (!widget.archivedOnly &&
                                  selectedFolderID.value == null &&
                                  archivedConversations.isNotEmpty
                              ? 1
                              : 0),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _folderTab(String title, String? folderID,
      {VoidCallback? onLongPress}) {
    final selected = selectedFolderID.value == folderID;
    final folderConversations = folderID == null
        ? <ConversationInfo>[]
        : logic.list.where((info) => logic.folderID(info) == folderID).toList();
    final unread = folderConversations.fold<int>(
        0, (sum, info) => sum + logic.getUnreadCount(info));
    final hasNotifiableUnread = folderConversations.any(
        (info) => logic.getUnreadCount(info) > 0 && !logic.isNotDisturb(info));
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 1.w),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => selectedFolderID.value = folderID,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.symmetric(horizontal: 13.w, vertical: 5.w),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFECECEC) : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(title,
                style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    height: 1.1,
                    color: const Color(0xFF1C1C1E))),
            if (unread > 0) ...[
              SizedBox(width: 4.w),
              Container(
                constraints: BoxConstraints(minWidth: 16.w, minHeight: 16.w),
                height: 16.w,
                padding: EdgeInsets.symmetric(horizontal: unread > 9 ? 4.w : 0),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: hasNotifiableUnread
                        ? const Color(0xFFFF524B)
                        : const Color(0xFFA8A8AE),
                    borderRadius: BorderRadius.circular(999)),
                child: Text(unread > 99 ? '99+' : '$unread',
                    style: TextStyle(
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        height: 1)),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _buildArchiveEntry(
      BuildContext context, List<ConversationInfo> archivedConversations) {
    final unread = archivedConversations.fold<int>(
        0, (sum, info) => sum + logic.getUnreadCount(info));
    return Ink(
      color: Styles.isDark ? Styles.c_F8F9FA : Styles.c_FFFFFF,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ConversationPage(
              groupChats: widget.groupChats, archivedOnly: true),
        )),
        child: SizedBox(
          height: 72.w,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            child: Row(children: [
              SizedBox(
                width: 54.w,
                height: 54.w,
                child: ClipOval(
                  child: Transform.scale(
                    scale: 1.5,
                    child: Image.asset(
                      'assets/images/ic_archive_99chat.png',
                      package: 'openim_common',
                      width: 54.w,
                      height: 54.w,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('归档',
                        style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w600,
                            color: Styles.c_0C1C33)),
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
                                fontSize: 14.sp, color: Styles.c_8E9AB0),
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

  Widget _buildItemView(BuildContext context, ConversationInfo info) =>
      Slidable(
        key: ValueKey(info.conversationID),
        controller: _controllerFor(info.conversationID),
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
              onPressed: (_) => _chooseFolder(context, info),
              color: _folderAction,
              label: '分组',
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
              label: info.isPinned == true ? StrRes.cancelTop : StrRes.topChat,
            ),
            _swipeAction(
              onPressed: (context) => _confirmDeleteConversation(context, info),
              color: _deleteAction,
              label: StrRes.delete,
            ),
          ],
        ),
        // Keep the ink surface inside the sliding transform. An Ink decoration
        // on the page's Material can retain its offset after the slide closes.
        child: Material(
          color: info.isPinned == true
              ? const Color(0xFFF3F4F6)
              : Styles.isDark
                  ? Styles.c_F8F9FA
                  : Styles.c_FFFFFF,
          child: InkWell(
            onTap: () {
              final controller = _controllerFor(info.conversationID);
              if (controller.ratio != 0) {
                controller.close();
              } else {
                logic.toChat(conversationInfo: info);
              }
            },
            onLongPress: () => _organizeConversation(context, info),
            child: Stack(
              children: [
                SizedBox(
                  height: 72.w,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16.w, 8.w, 16.w, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 54.w,
                          height: 54.w,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              AvatarView(
                                width: 54.w,
                                height: 54.w,
                                isCircle: true,
                                text: logic.getShowName(info),
                                url: info.faceURL,
                                isGroup: logic.isGroupChat(info),
                                textStyle: Styles.ts_FFFFFF_14sp_medium,
                              ),
                              if (logic.getUnreadCount(info) > 0)
                                Positioned(
                                  top: -4.5.w,
                                  right: -4.5.w,
                                  child: logic.isNotDisturb(info)
                                      ? Container(
                                          width: 10.w,
                                          height: 10.w,
                                          decoration: BoxDecoration(
                                            color: Styles.c_FF381F,
                                            shape: BoxShape.circle,
                                          ),
                                        )
                                      : UnreadCountView(
                                          count: logic.getUnreadCount(info),
                                          size: 18.w,
                                          fontSize: 10,
                                        ),
                                ),
                            ],
                          ),
                        ),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            logic.getShowName(info),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 16.sp,
                                              fontWeight: FontWeight.w500,
                                              color: Styles.c_0C1C33,
                                            ),
                                          ),
                                        ),
                                        if (logic.isNotDisturb(info)) ...[
                                          SizedBox(width: 6.w),
                                          Icon(Icons.notifications_off,
                                              size: 16.w,
                                              color: Styles.c_8E9AB0),
                                        ],
                                      ],
                                    ),
                                    SizedBox(height: 6.w),
                                    MatchTextView(
                                      text: logic.getContent(info),
                                      textStyle: TextStyle(
                                        fontSize: 14.sp,
                                        color: Styles.c_8E9AB0,
                                      ),
                                      prefixSpan: TextSpan(
                                        children: [
                                          if (logic.getUnreadCount(info) > 0)
                                            TextSpan(
                                              text:
                                                  '[${sprintf(StrRes.nPieces, [
                                                    logic.getUnreadCount(info)
                                                  ])}] ',
                                              style: TextStyle(
                                                  fontSize: 14.sp,
                                                  color: Styles.c_8E9AB0),
                                            ),
                                          TextSpan(
                                            text: logic.getPrefixTag(info),
                                            style:
                                                Styles.ts_0089FF_14sp.copyWith(
                                              color:
                                                  info.draftText?.isNotEmpty ==
                                                          true
                                                      ? Styles.c_FF381F
                                                      : Styles.c_0089FF,
                                            ),
                                          ),
                                        ],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(width: 8.w),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (info.isSingleChat &&
                                          info.latestMsg?.sendID ==
                                              OpenIM.iMManager.userID &&
                                          info.latestMsg?.status ==
                                              MessageStatus.succeeded) ...[
                                        ChatReadReceiptIcon(
                                          semanticLabel:
                                              FriendDisplayPreferences
                                                      .showReadReceipts
                                                  ? null
                                                  : StrRes.sentSuccessfully,
                                          isRead: FriendDisplayPreferences
                                                  .showReadReceipts &&
                                              info.latestMsg?.isRead == true,
                                          color: FriendDisplayPreferences
                                                      .showReadReceipts &&
                                                  info.latestMsg?.isRead == true
                                              ? Styles.c_0089FF
                                              : Styles.c_8E9AB0,
                                        ),
                                        SizedBox(width: 4.w),
                                      ],
                                      Text(
                                        logic.getTime(info),
                                        style: TextStyle(
                                            fontSize: 12.sp,
                                            color: Styles.c_8E9AB0),
                                      ),
                                    ],
                                  ),
                                  if (info.isPinned == true) ...[
                                    SizedBox(height: 4.w),
                                    Transform.rotate(
                                      angle: 0.785398,
                                      child: Icon(Icons.push_pin,
                                          size: 16.w, color: Styles.c_8E9AB0),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 82.w,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    height: 0.5,
                    color: const Color(0xFFE5E6E9),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
