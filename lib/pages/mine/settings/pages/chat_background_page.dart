import 'dart:io';

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

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
  });

  /// Kept for the Settings shell's in-memory preview compatibility. Persistent
  /// chat-background state is owned by [ChatBackgroundLocalService].
  final SettingsDraftStore? store;
  final String conversationId;
  final String conversationName;
  final bool embedded;
  final VoidCallback? onClose;

  @override
  State<ChatBackgroundPage> createState() => _ChatBackgroundPageState();
}

enum _BackgroundScope { currentChat, allChats }

class _ChatBackgroundPageState extends State<ChatBackgroundPage> {
  static const _colors = <Color>[
    Color(0xFFF1F1F1),
    Color(0xFFCFECCB),
    Color(0xFFBEDBFF),
    Color(0xFFF9C9D2),
    Color(0xFFFFF3B6),
    Color(0xFFD9B8E8),
  ];

  static const _recommended = <_RecommendedBackground>[
    _RecommendedBackground(
      titleZh: '人物',
      titleEn: 'Portrait',
      assetPath: 'assets/images/chat_backgrounds/beauty.png',
    ),
    _RecommendedBackground(
      titleZh: '风景',
      titleEn: 'Scenery',
      assetPath: 'assets/images/chat_backgrounds/scenery.png',
    ),
    _RecommendedBackground(
      titleZh: '汽车',
      titleEn: 'Car',
      assetPath: 'assets/images/chat_backgrounds/car.png',
    ),
  ];

  late _BackgroundScope _scope;
  String? _directValue;
  String? _globalValue;
  bool _loading = true;
  bool _saving = false;
  bool _colorsExpanded = true;
  bool _recommendedExpanded = true;

  String get _conversationId => widget.conversationId.trim();

  bool get _isGlobalOnlyEntry =>
      _conversationId.isEmpty ||
      _conversationId == ChatBackgroundLocalService.globalConversationId;

  String get _activeTargetId => _scope == _BackgroundScope.allChats
      ? ChatBackgroundLocalService.globalConversationId
      : _conversationId;

  String? get _previewValue => _scope == _BackgroundScope.allChats
      ? _globalValue
      : (_directValue ?? _globalValue);

  bool get _hasDirectOverride =>
      _scope == _BackgroundScope.currentChat && _directValue != null;

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
      final rgb = color.value.toRadixString(16).padLeft(8, '0').substring(2);
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

  Future<void> _pickBackground() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final result = await AssetPicker.pickAssets(
        context,
        pickerConfig: AssetPickerConfig(
          maxAssets: 1,
          requestType: RequestType.image,
          sortPathsByModifiedDate: true,
          filterOptions: PMFilter.defaultValue(containsPathModified: true),
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
          zh: '无法读取图片，请检查相册权限后重试',
          en: 'Unable to read photos. Check photo permissions and try again.',
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

  String _colorValue(Color color) =>
      '${ChatBackgroundLocalService.colorPrefix}${color.value.toRadixString(16).padLeft(8, '0')}';

  String _assetValue(String assetPath) =>
      '${ChatBackgroundLocalService.assetPrefix}$assetPath';

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final pageTitle = _isGlobalOnlyEntry
        ? settingsText(context, zh: '全局聊天背景', en: 'Global Chat Background')
        : settingsText(context, zh: '聊天背景', en: 'Chat Background');
    final clearTitle = _scope == _BackgroundScope.allChats
        ? settingsText(context, zh: '清除全局默认背景', en: 'Clear Global Default')
        : settingsText(context, zh: '清除本聊天背景', en: 'Clear This Chat Background');

    if (SettingsResponsive.isDesktop(context) &&
        MediaQuery.sizeOf(context).width >= 760) {
      return _desktopLayout(context, dark, pageTitle, clearTitle);
    }

    if (widget.embedded) {
      return Material(
        color: AppTokens.background(dark: dark),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: _content(context, dark, clearTitle, includePreview: true),
        ),
      );
    }

    return SettingsScaffold(
      title: pageTitle,
      onLeadingPressed: widget.onClose,
      children: _content(context, dark, clearTitle, includePreview: true),
    );
  }

  List<Widget> _content(
    BuildContext context,
    bool dark,
    String clearTitle, {
    required bool includePreview,
  }) {
    if (_loading) {
      return const [
        SizedBox(height: 120),
        Center(child: CircularProgressIndicator()),
      ];
    }
    return [
      _scopeSwitcher(context, dark),
      _scopeBanner(context, dark),
      if (includePreview) ...[
        _preview(context, dark),
        const SizedBox(height: 12),
      ],
      SettingsGroup(
        margin: EdgeInsets.zero,
        children: [
          SettingsCell(
            title: settingsText(context, zh: '从手机相册选择', en: 'Choose from Photos'),
            value: _saving ? settingsText(context, zh: '处理中…', en: 'Working…') : null,
            enabled: !_saving,
            onTap: _pickBackground,
          ),
          SettingsCell(
            title: clearTitle,
            showDivider: false,
            showArrow: false,
            enabled: !_saving && _hasEditableValue,
            onTap: _clearBackground,
          ),
        ],
      ),
      const SizedBox(height: 12),
      _sectionHeader(
        context,
        title: settingsText(context, zh: '选择一个颜色', en: 'Choose a Color'),
        expanded: _colorsExpanded,
        onTap: () => setState(() => _colorsExpanded = !_colorsExpanded),
      ),
      if (_colorsExpanded)
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppTokens.surface(dark: dark),
            borderRadius: BorderRadius.circular(AppTokens.rLg),
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            children: [for (final color in _colors) _colorTile(color, dark)],
          ),
        ),
      const SizedBox(height: 12),
      _sectionHeader(
        context,
        title: settingsText(context, zh: '推荐背景', en: 'Recommended Backgrounds'),
        expanded: _recommendedExpanded,
        onTap: () => setState(() => _recommendedExpanded = !_recommendedExpanded),
      ),
      if (_recommendedExpanded)
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppTokens.surface(dark: dark),
            borderRadius: BorderRadius.circular(AppTokens.rLg),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _recommended.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: 1.05,
            ),
            itemBuilder: (_, index) =>
                _recommendedTile(context, _recommended[index], dark),
          ),
        ),
    ];
  }

  Widget _scopeSwitcher(BuildContext context, bool dark) {
    if (_isGlobalOnlyEntry) return const SizedBox.shrink();

    Widget chip(_BackgroundScope scope, String label) {
      final selected = _scope == scope;
      return Expanded(
        child: GestureDetector(
          onTap: _saving || selected ? null : () => setState(() => _scope = scope),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? AppTokens.accent
                  : (dark ? const Color(0xFF2A2D33) : const Color(0xFFEDEFF2)),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : AppTokens.textPrimary(dark: dark),
                fontSize: 14,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Row(
        children: [
          chip(
            _BackgroundScope.currentChat,
            settingsText(context, zh: '当前聊天', en: 'This Chat'),
          ),
          const SizedBox(width: 10),
          chip(
            _BackgroundScope.allChats,
            settingsText(context, zh: '全部聊天', en: 'All Chats'),
          ),
        ],
      ),
    );
  }

  Widget _scopeBanner(BuildContext context, bool dark) {
    final all = _scope == _BackgroundScope.allChats;
    final name = widget.conversationName.trim().isEmpty
        ? settingsText(context, zh: '对方', en: 'Contact')
        : widget.conversationName.trim();
    final title = all
        ? settingsText(context, zh: '全部聊天 · 默认背景', en: 'All chats · Default background')
        : settingsText(context, zh: '仅当前聊天 · $name', en: 'This chat only · $name');
    final subtitle = all
        ? settingsText(
            context,
            zh: '未单独设置背景的聊天都会使用这里的样式；单聊仍可覆盖。',
            en: 'Chats without a custom background use this. Individual chats can still override it.',
          )
        : _hasDirectOverride
            ? settingsText(
                context,
                zh: '已为本聊天单独设置，优先于全局默认。',
                en: 'Custom background for this chat overrides the global default.',
              )
            : settingsText(
                context,
                zh: '尚未单独设置，当前预览的是全局默认（或系统默认）。',
                en: 'No custom background yet. Preview shows the global or system default.',
              );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF23262D) : const Color(0xFFF0F4FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: dark ? const Color(0xFF2A2D33) : const Color(0xFFD8E2F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                all ? Icons.public_rounded : Icons.chat_bubble_outline_rounded,
                size: 18,
                color: AppTokens.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: AppTokens.textPrimary(dark: dark),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              color: AppTokens.textSecondary(dark: dark),
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _preview(
    BuildContext context,
    bool dark, {
    double? height = 168,
    EdgeInsetsGeometry margin = const EdgeInsets.fromLTRB(16, 12, 16, 0),
  }) {
    final badge = _scope == _BackgroundScope.allChats
        ? settingsText(context, zh: '全局默认预览', en: 'Global default preview')
        : _hasDirectOverride
            ? settingsText(context, zh: '本聊天专属预览', en: 'This chat preview')
            : settingsText(context, zh: '继承全局默认', en: 'Using global default');

    return Container(
      width: double.infinity,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: AppTokens.surface(dark: dark),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTokens.border(dark: dark), width: 0.6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _backgroundWidget(_previewValue, dark),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.04),
                  Colors.black.withOpacity(0.14),
                ],
              ),
            ),
          ),
          Positioned(
            left: 12,
            top: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.45),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                badge,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          Positioned(
            right: 16,
            top: 44,
            child: _bubble(
              text: settingsText(context, zh: '你好，今晚见面聊', en: 'Hi, let’s talk tonight.'),
              self: true,
              dark: dark,
            ),
          ),
          Positioned(
            left: 16,
            bottom: 16,
            child: _bubble(
              text: settingsText(
                context,
                zh: '这里会显示当前聊天背景效果',
                en: 'Preview of the chat background.',
              ),
              self: false,
              dark: dark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _backgroundWidget(String? value, bool dark) {
    final color = ChatBackgroundLocalService.colorOf(value);
    if (color != null) return ColoredBox(color: color);
    final asset = ChatBackgroundLocalService.assetOf(value);
    if (asset != null) {
      return Image.asset(
        asset,
        package: 'openim_common',
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _defaultBackground(dark),
      );
    }
    final file = ChatBackgroundLocalService.fileOf(value);
    if (file != null) {
      return Image.file(
        File(file),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _defaultBackground(dark),
      );
    }
    return _defaultBackground(dark);
  }

  Widget _defaultBackground(bool dark) =>
      ColoredBox(color: dark ? const Color(0xFF111111) : const Color(0xFFF3F5F8));

  Widget _sectionHeader(
    BuildContext context, {
    required String title,
    required bool expanded,
    required VoidCallback onTap,
  }) {
    final dark = settingsIsDark(context);
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        color: AppTokens.background(dark: dark),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: AppTokens.textSecondary(dark: dark),
                  fontSize: 15,
                ),
              ),
            ),
            Icon(
              expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
              color: AppTokens.textSecondary(dark: dark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble({
    required String text,
    required bool self,
    required bool dark,
  }) =>
      Container(
        constraints: const BoxConstraints(maxWidth: 190),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: self
              ? const Color(0xFF2D8CFF)
              : (dark ? const Color(0xFF23262B) : Colors.white),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: self ? Colors.white : AppTokens.textPrimary(dark: dark),
            fontSize: 14,
          ),
        ),
      );

  Widget _colorTile(Color color, bool dark) {
    final value = _colorValue(color);
    final selected = _scope == _BackgroundScope.allChats
        ? _globalValue == value
        : _directValue == value;
    return GestureDetector(
      onTap: _saving ? null : () => _saveValue(value),
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppTokens.accent : AppTokens.border(dark: dark),
            width: selected ? 2.5 : 0.6,
          ),
        ),
        child: selected
            ? const Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: AppTokens.accent,
                    size: 22,
                  ),
                ),
              )
            : null,
      ),
    );
  }

  Widget _recommendedTile(
    BuildContext context,
    _RecommendedBackground item,
    bool dark,
  ) {
    final value = _assetValue(item.assetPath);
    final selected = _scope == _BackgroundScope.allChats
        ? _globalValue == value
        : _directValue == value;
    return GestureDetector(
      onTap: _saving ? null : () => _saveValue(value),
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? AppTokens.accent : AppTokens.border(dark: dark),
                  width: selected ? 2.5 : 0.6,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    item.assetPath,
                    package: 'openim_common',
                    fit: BoxFit.cover,
                  ),
                  if (selected)
                    const Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(
                          Icons.check_circle_rounded,
                          color: AppTokens.accent,
                          size: 21,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            settingsText(context, zh: item.titleZh, en: item.titleEn),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTokens.textSecondary(dark: dark),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopLayout(
    BuildContext context,
    bool dark,
    String pageTitle,
    String clearTitle,
  ) {
    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 5,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: _content(context, dark, clearTitle, includePreview: false),
          ),
        ),
        VerticalDivider(
          width: 1,
          thickness: 0.6,
          color: AppTokens.border(dark: dark),
        ),
        Expanded(
          flex: 4,
          child: ColoredBox(
            color: AppTokens.background(dark: dark),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    settingsText(context, zh: '实时预览', en: 'Live Preview'),
                    style: TextStyle(
                      color: AppTokens.textPrimary(dark: dark),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _preview(
                      context,
                      dark,
                      height: null,
                      margin: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );

    if (widget.embedded) {
      return Material(color: AppTokens.background(dark: dark), child: body);
    }
    return Scaffold(
      backgroundColor: AppTokens.background(dark: dark),
      appBar: GlassAppBar(
        toolbarHeight: kToolbarHeight,
        elevation: 0,
        centerTitle: true,
        backgroundColor: AppTokens.background(dark: dark),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          color: AppTokens.accent,
          onPressed: widget.onClose ?? () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          pageTitle,
          style: TextStyle(
            color: AppTokens.textPrimary(dark: dark),
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: body,
    );
  }
}

class _RecommendedBackground {
  const _RecommendedBackground({
    required this.titleZh,
    required this.titleEn,
    required this.assetPath,
  });

  final String titleZh;
  final String titleEn;
  final String assetPath;
}
