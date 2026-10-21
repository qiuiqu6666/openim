import 'package:openim_common/media_localization.dart';

import 'package:flutter/material.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:wechat_camera_picker/wechat_camera_picker.dart';

import '../appearance/chat_background/chat_background_menu.dart';
import '../appearance/chat_background/chat_background_picker.dart';

import '../chat_background_local_service.dart';
import '../settings_draft_store.dart';
import '../widgets/settings_widgets.dart';

class ChatBackgroundPage extends StatefulWidget {
  const ChatBackgroundPage({
    super.key,
    this.store,
    this.conversationId = ChatBackgroundLocalService.globalConversationId,
    this.conversationName = '',
    this.embedded = false,
    this.onClose,
    this.showSelection = false,
  });

  /// Kept for the Settings shell's in-memory preview compatibility. Persistent
  /// chat-background state is owned by [ChatBackgroundLocalService].
  final SettingsDraftStore? store;
  final String conversationId;
  final String conversationName;
  final bool embedded;
  final VoidCallback? onClose;
  final bool showSelection;

  @override
  State<ChatBackgroundPage> createState() => _ChatBackgroundPageState();
}

enum _BackgroundScope { currentChat, allChats }

class _ChatBackgroundPageState extends State<ChatBackgroundPage> {
  late _BackgroundScope _scope;
  String? _directValue;
  String? _globalValue;
  bool _loading = true;
  bool _saving = false;

  String get _conversationId => widget.conversationId.trim();

  bool get _isGlobalOnlyEntry =>
      _conversationId.isEmpty ||
      _conversationId == ChatBackgroundLocalService.globalConversationId;

  String get _activeTargetId => _scope == _BackgroundScope.allChats
      ? ChatBackgroundLocalService.globalConversationId
      : _conversationId;

  bool get _hasEditableValue => _scope == _BackgroundScope.allChats
      ? _globalValue != null
      : _directValue != null;

  @override
  void initState() {
    super.initState();
    _scope = _isGlobalOnlyEntry
        ? _BackgroundScope.allChats
        : _BackgroundScope.currentChat;
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final direct = _isGlobalOnlyEntry
        ? null
        : ChatBackgroundLocalService.direct(_conversationId);
    final global = ChatBackgroundLocalService.global();
    if (!mounted) return;
    setState(() {
      _directValue = direct;
      _globalValue = global;
      _loading = false;
    });
  }

  void _syncStore(String? value) {
    final store = widget.store;
    if (store == null || _scope != _BackgroundScope.allChats) return;
    if (value == null) {
      store.resetChatBackground();
      return;
    }
    final color = ChatBackgroundLocalService.colorOf(value);
    if (color != null) {
      final rgb =
          color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2);
      store.setChatBackground('color:$rgb');
      return;
    }
    final asset = ChatBackgroundLocalService.assetOf(value);
    if (asset != null) {
      final name = asset.split('/').last.split('.').first;
      store.setChatBackground('asset:$name');
      return;
    }
    store.setChatBackground(value);
  }

  Future<void> _pickBackground({bool camera = false}) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final captured = camera
          ? await CameraPicker.pickFromCamera(
              context,
              pickerConfig: CameraPickerConfig(
                textDelegate: AppMediaCopy.camera,
                enableRecording: false,
              ),
            )
          : null;
      if (!mounted) return;
      final result = camera
          ? (captured == null ? null : <AssetEntity>[captured])
          : await AssetPicker.pickAssets(
              context,
              pickerConfig: AssetPickerConfig(
                textDelegate: AppMediaCopy.assets,
                maxAssets: 1,
                requestType: RequestType.image,
                sortPathsByModifiedDate: true,
                filterOptions:
                    PMFilter.defaultValue(containsPathModified: true),
              ),
            );
      if (!mounted || result == null || result.isEmpty) return;
      final bytes = await result.first.thumbnailDataWithSize(
        const ThumbnailSize(1800, 1800),
        quality: 94,
      );
      if (!mounted || bytes == null || bytes.isEmpty) return;
      final value = await ChatBackgroundLocalService.saveGalleryBytes(
        _activeTargetId,
        bytes,
      );
      if (!mounted) return;
      setState(() => _afterSaved(value));
      if (_scope == _BackgroundScope.allChats) {
        widget.store?.setChatBackgroundGallery(bytes);
      }
      _toastSaved();
    } catch (_) {
      if (!mounted) return;
      showSettingsMessage(
        context,
        settingsText(
          context,
          zh: camera ? '无法拍照，请检查相机和相册权限后重试' : '无法读取图片，请检查相册权限后重试',
          en: camera
              ? 'Unable to take a photo. Check camera and photo permissions.'
              : 'Unable to read photos. Check photo permissions and try again.',
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveValue(String value) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ChatBackgroundLocalService.saveValue(_activeTargetId, value);
      if (!mounted) return;
      setState(() => _afterSaved(value));
      _syncStore(value);
      _toastSaved();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clearBackground() async {
    if (_saving || !_hasEditableValue) return;
    setState(() => _saving = true);
    try {
      await ChatBackgroundLocalService.clear(_activeTargetId);
      if (!mounted) return;
      setState(() => _afterSaved(null));
      _syncStore(null);
      showSettingsMessage(
        context,
        _scope == _BackgroundScope.allChats
            ? settingsText(
                context,
                zh: '已清除全局默认背景',
                en: 'Global default background cleared.',
              )
            : settingsText(
                context,
                zh: '已清除本聊天背景，将使用全局默认',
                en: 'This chat will now use the global default.',
              ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _afterSaved(String? value) {
    if (_scope == _BackgroundScope.allChats) {
      _globalValue = value;
    } else {
      _directValue = value;
    }
  }

  void _toastSaved() {
    showSettingsMessage(
      context,
      _scope == _BackgroundScope.allChats
          ? settingsText(
              context,
              zh: '已设为全部聊天的默认背景',
              en: 'Set as the default for all chats.',
            )
          : settingsText(
              context,
              zh: '已仅对本聊天生效',
              en: 'Applied to this chat only.',
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showSelection) {
      return ChatBackgroundMenu(
        embedded: widget.embedded,
        onClose: widget.onClose,
        busy: _loading || _saving,
        onPhotos: _pickBackground,
        onCamera: () => _pickBackground(camera: true),
        onSelect: () async {
          await Navigator.of(context).push<void>(MaterialPageRoute(
            builder: (_) => ChatBackgroundPage(
              store: widget.store,
              conversationId: widget.conversationId,
              conversationName: widget.conversationName,
              showSelection: true,
            ),
          ));
          if (mounted) await _load();
        },
      );
    }
    return ChatBackgroundPicker(
      initialValue: _isGlobalOnlyEntry ? _globalValue : _directValue,
      onSave: (value) async {
        if (value == null) {
          await _clearBackground();
        } else {
          await _saveValue(value);
        }
      },
    );
  }
}
