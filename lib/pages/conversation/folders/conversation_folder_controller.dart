import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import '../../mine/settings/widgets/settings_widgets.dart';
import '../conversation_logic.dart';
import '../conversation_organizer.dart';
import 'folder_name_dialog.dart';

/// Page-owned folder interactions. The Chat service remains the data owner.
class ConversationFolderController extends ChangeNotifier {
  ConversationFolderController({required this.logic});

  final ConversationLogic logic;
  String? _selectedFolderID;
  List<String>? _previewOrder;
  bool _reorderEditing = false;
  bool _interactionOpen = false;
  bool _busy = false;
  bool _disposed = false;
  Future<void>? _savingOrder;

  bool get _active => !_disposed && logic.isSessionActive;
  bool get busy => _busy;
  bool get reorderEditing => _reorderEditing && logic.folders.isNotEmpty;
  String? get selectedFolderID =>
      logic.folders.any((folder) => folder.id == _selectedFolderID)
          ? _selectedFolderID
          : null;

  List<ChatFolder> get displayFolders {
    final folders = List<ChatFolder>.of(logic.folders);
    final order = _previewOrder;
    if (order == null) return folders;
    final byID = {for (final folder in folders) folder.id: folder};
    return [
      for (final id in order)
        if (byID.containsKey(id)) byID.remove(id)!,
      ...byID.values,
    ];
  }

  Future<void> selectFolder(String? id) async {
    if (!_active) return;
    if (_savingOrder != null) {
      await _savingOrder;
    } else if (reorderEditing) {
      await finishReordering();
    } else if (_busy) {
      return;
    }
    if (!_active) return;
    _selectedFolderID = id;
    notifyListeners();
  }

  void previewReorder(int oldIndex, int newIndex) {
    if (!_active || _busy || !reorderEditing) return;
    final ids = displayFolders.map((folder) => folder.id).toList();
    if (oldIndex < 0 ||
        oldIndex >= ids.length ||
        newIndex < 0 ||
        newIndex > ids.length) {
      return;
    }
    if (newIndex > oldIndex) newIndex--;
    ids.insert(newIndex, ids.removeAt(oldIndex));
    _previewOrder = ids;
    notifyListeners();
  }

  Future<void> finishReordering() async {
    if (_savingOrder != null) return _savingOrder;
    if (!_active || !reorderEditing) return;
    final ids = displayFolders.map((folder) => folder.id).toList();
    if (listEquals(ids, logic.folders.map((folder) => folder.id).toList())) {
      _endReordering();
      return;
    }
    _busy = true;
    notifyListeners();
    final saving = _saveOrder(ids);
    _savingOrder = saving;
    try {
      await saving;
    } finally {
      _savingOrder = null;
      _busy = false;
      if (_active) _endReordering();
    }
  }

  Future<void> _saveOrder(List<String> ids) async {
    await logic.reorderFolders(ids);
  }

  void _endReordering() {
    _previewOrder = null;
    _reorderEditing = false;
    notifyListeners();
  }

  Future<void> createFolder(BuildContext context) =>
      _interact(context, () async {
        final folder = await _createFolder(context);
        if (context.mounted && _active && folder != null) {
          _selectedFolderID = folder.id;
          notifyListeners();
        }
      });

  Future<void> manageFolder(BuildContext context, ChatFolder folder) =>
      _interact(context, () async {
        final action = await showSettingsActionSheet<String>(context,
            title: folder.name,
            actions: [
              SettingsAction(_text(context, '重命名', 'Rename'), 'rename'),
              SettingsAction(_text(context, '删除分组', 'Delete folder'), 'delete',
                  destructive: true),
              SettingsAction(_text(context, '重新排序', 'Reorder'), 'reorder'),
            ]);
        if (!context.mounted ||
            !_active ||
            !logic.folders.any((item) => item.id == folder.id)) {
          return;
        }
        switch (action) {
          case 'rename':
            final name = await _promptName(context, folder);
            if (context.mounted &&
                _active &&
                name != null &&
                name != folder.name) {
              await _perform(() => logic.renameFolder(folder, name));
            }
          case 'delete':
            await _deleteFolder(context, folder);
          case 'reorder':
            _previewOrder = logic.folders.map((item) => item.id).toList();
            _reorderEditing = true;
            notifyListeners();
        }
      });

  Future<void> deleteFolder(BuildContext context, ChatFolder folder) =>
      _interact(context, () => _deleteFolder(context, folder));

  Future<void> _deleteFolder(BuildContext context, ChatFolder folder) async {
    final confirmed = await showSettingsConfirm(context,
        title: _text(context, '删除分组', 'Delete folder'),
        message: _text(context, '删除后会话会回到「全部」列表，不会删除聊天记录。',
            'Chats will return to All. Chat history will not be deleted.'),
        confirmText: _text(context, '删除', 'Delete'),
        destructive: true);
    if (!context.mounted || !_active || !confirmed) return;
    final deleted = await _perform(() => logic.deleteFolder(folder));
    if (!context.mounted || !_active || deleted != true) return;
    _previewOrder?.remove(folder.id);
    if (_selectedFolderID == folder.id) _selectedFolderID = null;
    if (logic.folders.isEmpty) {
      _previewOrder = null;
      _reorderEditing = false;
    }
    notifyListeners();
  }

  Future<void> chooseFolder(BuildContext context, ConversationInfo info) =>
      _interact(context, () => _chooseFolder(context, info));

  Future<void> _chooseFolder(
      BuildContext context, ConversationInfo info) async {
    final currentID = logic.folderID(info);
    ChatFolder? current;
    for (final folder in logic.folders) {
      if (folder.id == currentID) current = folder;
    }
    final target = await showSettingsActionSheet<String>(context,
        title: _text(context, '添加到分组', 'Add to folder'),
        actions: [
          for (final folder in logic.folders)
            SettingsAction(folder.name, folder.id,
                subtitle: folder.id == currentID
                    ? _text(context, '已在此分组', 'Already in this folder')
                    : current == null
                        ? null
                        : _text(context, '将从「${current.name}」移入',
                            'Move from "${current.name}"')),
          SettingsAction(_text(context, '新建分组', 'New folder'), '__create__'),
        ]);
    if (!context.mounted || !_active || target == null) return;
    ChatFolder? folder;
    if (target == '__create__') {
      folder = await _createFolder(context);
    } else {
      for (final item in logic.folders) {
        if (item.id == target) folder = item;
      }
    }
    if (!context.mounted || !_active || folder == null) return;
    if (logic.folderID(info) == folder.id && !logic.isArchived(info)) return;
    await _perform(() =>
        logic.updateOrganizer(info, folderID: folder!.id, archived: false));
  }

  Future<void> removeFromFolder(ConversationInfo info) async {
    if (!_active || _busy || _interactionOpen) return;
    await _perform(() => logic.updateOrganizer(info,
        folderID: null, archived: logic.isArchived(info)));
  }

  Future<void> organizeConversation(
          BuildContext context, ConversationInfo info) =>
      _interact(context, () async {
        final archived = logic.isArchived(info);
        final inSelectedFolder = selectedFolderID != null &&
            logic.folderID(info) == selectedFolderID;
        final action = await showSettingsActionSheet<String>(context,
            title: logic.getShowName(info),
            actions: [
              SettingsAction(
                  archived
                      ? _text(context, '取消归档', 'Unarchive')
                      : _text(context, '归档', 'Archive'),
                  'archive'),
              SettingsAction(
                  _text(context, '添加到分组', 'Add to folder'), 'folder'),
              if (inSelectedFolder)
                SettingsAction(
                    _text(context, '移出分组', 'Remove from folder'), 'remove'),
            ]);
        if (!context.mounted || !_active) return;
        switch (action) {
          case 'archive':
            await _perform(() => logic.updateOrganizer(info,
                folderID: logic.folderID(info),
                archived: !logic.isArchived(info)));
          case 'folder':
            await _chooseFolder(context, info);
          case 'remove':
            await _perform(() => logic.updateOrganizer(info,
                folderID: null, archived: logic.isArchived(info)));
        }
      });

  Future<ChatFolder?> _createFolder(BuildContext context) async {
    final name = await _promptName(context);
    if (!context.mounted || !_active || name == null) return null;
    final created = await _perform(() => logic.createFolder(name));
    if (!context.mounted || !_active || created != true) return null;
    for (final folder in logic.folders) {
      if (_normalize(folder.name) == _normalize(name)) return folder;
    }
    return null;
  }

  Future<String?> _promptName(BuildContext context, [ChatFolder? folder]) {
    final duplicateMessage =
        _text(context, '分组名称已存在', 'Folder name already exists');
    return showCupertinoDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (_) => FolderNameDialog(
        initialName: folder?.name,
        validator: (name) => logic.folders.any((item) =>
                item.id != folder?.id &&
                _normalize(item.name) == _normalize(name))
            ? duplicateMessage
            : null,
      ),
    );
  }

  Future<bool?> _perform(Future<bool> Function() operation) async {
    if (!_active || _busy) return null;
    _busy = true;
    notifyListeners();
    try {
      return await operation();
    } finally {
      _busy = false;
      if (_active) notifyListeners();
    }
  }

  Future<void> _interact(
      BuildContext context, Future<void> Function() interaction) async {
    if (!_usable(context) || _busy || _interactionOpen) return;
    _interactionOpen = true;
    try {
      await interaction();
    } finally {
      _interactionOpen = false;
    }
  }

  bool _usable(BuildContext context) => _active && context.mounted;
  static String _normalize(String name) => name.trim().toLowerCase();
  static String _text(BuildContext context, String zh, String en) =>
      settingsText(context, zh: zh, en: en);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
