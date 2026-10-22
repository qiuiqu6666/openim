import 'chat_background_reference_tokens.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../../chat_background_local_service.dart';
import '../../widgets/settings_widgets.dart';
import 'chat_background_menu_tokens.dart';
import 'chat_background_preview.dart';

class ChatBackgroundEditor extends StatefulWidget {
  const ChatBackgroundEditor(
      {super.key,
      required this.globalOnly,
      required this.allChats,
      required this.name,
      required this.value,
      required this.hasOverride,
      required this.busy,
      required this.onScope,
      required this.onSelect,
      required this.onPhotos,
      required this.onClear,
      this.embedded = false,
      this.onClose});

  final bool globalOnly, allChats, hasOverride, busy, embedded;
  final String name;
  final String? value;
  final ValueChanged<bool> onScope;
  final ValueChanged<String> onSelect;
  final VoidCallback onPhotos, onClear;
  final VoidCallback? onClose;

  @override
  State<ChatBackgroundEditor> createState() => _ChatBackgroundEditorState();
}

enum _BackgroundScope { currentChat, allChats }

class _ChatBackgroundEditorState extends State<ChatBackgroundEditor> {
  bool _colorsExpanded = true;
  bool _recommendedExpanded = true;
  bool get _isGlobalOnlyEntry => widget.globalOnly;
  bool get _saving => widget.busy;
  bool get _loading => false;
  bool get _hasDirectOverride => !widget.allChats && widget.hasOverride;
  bool get _hasEditableValue => widget.hasOverride;
  _BackgroundScope get _scope => widget.allChats
      ? _BackgroundScope.allChats
      : _BackgroundScope.currentChat;
  void _saveValue(String value) => widget.onSelect(value);
  void _pickBackground() => widget.onPhotos();
  void _clearBackground() => widget.onClear();
  static const _colors = ChatBackgroundMenuTokens.colors;
  static final _recommended = [
    for (var i = 0; i < ChatBackgroundMenuTokens.options.length; i++)
      _RecommendedBackground(
          titleZh: ChatBackgroundMenuTokens.titlesZh[i],
          titleEn: ChatBackgroundMenuTokens.titlesEn[i],
          assetPath: ChatBackgroundLocalService.assetOf(
              ChatBackgroundMenuTokens.options[i])!)
  ];

  String _colorValue(Color color) =>
      '${ChatBackgroundLocalService.colorPrefix}${color.toARGB32().toRadixString(16).padLeft(8, '0')}';

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
        : settingsText(context,
            zh: '清除本聊天背景', en: 'Clear This Chat Background');

    if (SettingsResponsive.isDesktop(context) &&
        MediaQuery.sizeOf(context).width >= 760) {
      return _desktopLayout(context, dark, pageTitle, clearTitle);
    }

    if (widget.embedded) {
      return Material(
        color: AppTokens.background(dark: dark),
        child: ListView(
          padding: ChatBackgroundReferenceTokens.pagePadding,
          children: _content(context, dark, clearTitle, includePreview: true),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTokens.background(dark: dark),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        backgroundColor: AppTokens.background(dark: dark),
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle:
            AppSystemBars.styleFor(AppTokens.background(dark: dark)),
        automaticallyImplyLeading: false,
        leading: Navigator.of(context).canPop()
            ? IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                color: AppTokens.accent,
                onPressed:
                    widget.onClose ?? () => Navigator.of(context).maybePop())
            : null,
        title: Text(pageTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: AppTokens.textPrimary(dark: dark),
                fontSize: AppTokens.listTitleFontSize,
                fontWeight: FontWeight.w600,
                height: 1.25)),
      ),
      body: SafeArea(
          top: false,
          child: ListView(
              padding: ChatBackgroundReferenceTokens.pagePadding,
              children:
                  _content(context, dark, clearTitle, includePreview: true))),
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
        const SizedBox(height: AppTokens.s4),
      ],
      SettingsGroup(
        margin: EdgeInsets.zero,
        children: [
          SettingsCell(
            title:
                settingsText(context, zh: '从手机相册选择', en: 'Choose from Photos'),
            value: _saving
                ? settingsText(context, zh: '处理中…', en: 'Working…')
                : null,
            enabled: !_saving,
            onTap: _pickBackground,
          ),
          SettingsCell(
            title: clearTitle,
            showDivider: false,
            enabled: !_saving && _hasEditableValue,
            onTap: _clearBackground,
          ),
        ],
      ),
      const SizedBox(height: AppTokens.s4),
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
          padding: ChatBackgroundReferenceTokens.colorGridPadding,
          child: GridView.count(
            padding: EdgeInsets.zero,
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            children: [for (final color in _colors) _colorTile(color, dark)],
          ),
        ),
      const SizedBox(height: AppTokens.s4),
      _sectionHeader(
        context,
        title: settingsText(context, zh: '推荐背景', en: 'Recommended Backgrounds'),
        expanded: _recommendedExpanded,
        onTap: () =>
            setState(() => _recommendedExpanded = !_recommendedExpanded),
      ),
      if (_recommendedExpanded)
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppTokens.surface(dark: dark),
            borderRadius: BorderRadius.circular(AppTokens.rLg),
          ),
          padding: ChatBackgroundReferenceTokens.imageGridPadding,
          child: GridView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _recommended.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              childAspectRatio: ChatBackgroundReferenceTokens.imageAspectRatio,
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
        child: Semantics(
            button: true,
            selected: selected,
            enabled: !_saving,
            child: GestureDetector(
              onTap: _saving || selected
                  ? null
                  : () => widget.onScope(scope == _BackgroundScope.allChats),
              child: Container(
                constraints: const BoxConstraints(
                    minHeight: ChatBackgroundReferenceTokens.scopeHeight),
                padding: EdgeInsets.symmetric(
                    vertical: MediaQuery.textScalerOf(context).scale(14) > 14
                        ? 8
                        : 0),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? AppTokens.accent
                      : (dark
                          ? ChatBackgroundReferenceTokens.scopeDark
                          : ChatBackgroundReferenceTokens.scopeLight),
                  borderRadius: BorderRadius.circular(
                      ChatBackgroundReferenceTokens.scopeRadius),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? AppTokens.onAccent
                        : AppTokens.textPrimary(dark: dark),
                    fontSize: AppTokens.captionFontSize,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            )),
      );
    }

    return Padding(
      padding: ChatBackgroundReferenceTokens.sectionMargin,
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
    final name = widget.name.trim().isEmpty
        ? settingsText(context, zh: '对方', en: 'Contact')
        : widget.name.trim();
    final title = all
        ? settingsText(context,
            zh: '全部聊天 · 默认背景', en: 'All chats · Default background')
        : settingsText(context,
            zh: '仅当前聊天 · $name', en: 'This chat only · $name');
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
      margin: ChatBackgroundReferenceTokens.sectionMargin,
      padding: ChatBackgroundReferenceTokens.bannerPadding,
      decoration: BoxDecoration(
        color: dark
            ? ChatBackgroundReferenceTokens.bannerDark
            : ChatBackgroundReferenceTokens.bannerLight,
        borderRadius:
            BorderRadius.circular(ChatBackgroundReferenceTokens.tileRadius),
        border: Border.all(
          color: dark
              ? ChatBackgroundReferenceTokens.scopeDark
              : ChatBackgroundReferenceTokens.bannerBorderLight,
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
              const SizedBox(width: AppTokens.s3),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: AppTokens.textPrimary(dark: dark),
                    fontSize: AppTokens.secondaryFontSize,
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
              height: ChatBackgroundReferenceTokens.bannerLineHeight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _preview(BuildContext context, bool dark,
          {double? height = ChatBackgroundReferenceTokens.previewHeight,
          EdgeInsetsGeometry margin =
              ChatBackgroundReferenceTokens.sectionMargin}) =>
      ChatBackgroundPreview(
        value: widget.value,
        allChats: widget.allChats,
        hasOverride: widget.hasOverride,
        height: height,
        margin: margin,
      );

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
        padding: ChatBackgroundReferenceTokens.headerPadding,
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: AppTokens.textSecondary(dark: dark),
                  fontSize: AppTokens.secondaryFontSize,
                ),
              ),
            ),
            Icon(
              expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              color: AppTokens.textSecondary(dark: dark),
            ),
          ],
        ),
      ),
    );
  }

  Widget _colorTile(Color color, bool dark) {
    final index = _colors.indexOf(color);
    final value = _colorValue(color);
    return Semantics(
      label: settingsText(context,
          zh: ChatBackgroundMenuTokens.colorNamesZh[index],
          en: ChatBackgroundMenuTokens.colorNamesEn[index]),
      button: true,
      selected: widget.value == value,
      enabled: !_saving,
      child: InkWell(
        onTap: _saving ? null : () => _saveValue(value),
        borderRadius:
            BorderRadius.circular(ChatBackgroundReferenceTokens.tileRadius),
        child: Container(
            decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(
                    ChatBackgroundReferenceTokens.tileRadius),
                border: Border.all(
                    color: AppTokens.border(dark: dark),
                    width: ChatBackgroundReferenceTokens.hairline))),
      ),
    );
  }

  Widget _recommendedTile(
      BuildContext context, _RecommendedBackground item, bool dark) {
    final value = _assetValue(item.assetPath);
    final label = settingsText(context, zh: item.titleZh, en: item.titleEn);
    return Semantics(
      label: label,
      button: true,
      selected: widget.value == value,
      enabled: !_saving,
      child: InkWell(
        onTap: _saving ? null : () => _saveValue(value),
        child: Column(children: [
          Expanded(
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(
                      ChatBackgroundReferenceTokens.tileRadius),
                  child: Image.asset(item.assetPath,
                      package: 'openim_common',
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      excludeFromSemantics: true,
                      cacheWidth: ChatBackgroundMenuTokens.thumbnailWidth))),
          const SizedBox(height: AppTokens.s3),
          ExcludeSemantics(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppTokens.textSecondary(dark: dark),
                      fontSize: 14))),
        ]),
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
            padding: const EdgeInsets.only(bottom: AppTokens.s7),
            children:
                _content(context, dark, clearTitle, includePreview: false),
          ),
        ),
        VerticalDivider(
          width: 1,
          thickness: ChatBackgroundReferenceTokens.hairline,
          color: AppTokens.border(dark: dark),
        ),
        Expanded(
          flex: 4,
          child: ColoredBox(
            color: AppTokens.background(dark: dark),
            child: Padding(
              padding: ChatBackgroundReferenceTokens.desktopPreviewPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    settingsText(context, zh: '实时预览', en: 'Live Preview'),
                    style: TextStyle(
                      color: AppTokens.textPrimary(dark: dark),
                      fontSize: AppTokens.secondaryFontSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppTokens.s4),
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
      appBar: AppBar(
        toolbarHeight: kToolbarHeight,
        elevation: 0,
        centerTitle: true,
        backgroundColor: AppTokens.surface(dark: dark),
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
            fontSize: AppTokens.listTitleFontSize,
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
