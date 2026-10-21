import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../widgets/settings_widgets.dart';
import 'chat_background_menu_tokens.dart';

/// The compact entry surface; selection and persistence stay in the editor.
class ChatBackgroundMenu extends StatelessWidget {
  const ChatBackgroundMenu({
    super.key,
    required this.onSelect,
    required this.onPhotos,
    required this.onCamera,
    this.onClose,
    this.busy = false,
    this.embedded = false,
  });

  final VoidCallback onSelect;
  final VoidCallback onPhotos;
  final VoidCallback onCamera;
  final VoidCallback? onClose;
  final bool busy;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final background =
        dark ? AppTokens.backgroundDark : ChatBackgroundMenuTokens.background;

    Widget cell(String zh, String en, VoidCallback onTap) => Semantics(
          button: true,
          enabled: !busy,
          child: SettingsCell(
            title: settingsText(context, zh: zh, en: en),
            enabled: !busy,
            showDivider: false,
            onTap: onTap,
          ),
        );

    return SettingsScaffold(
      title: settingsText(context, zh: '聊天背景', en: 'Chat Background'),
      embedded: embedded,
      onLeadingPressed: onClose,
      backgroundColor: background,
      leadingColor: AppTokens.textPrimary(dark: dark),
      leading: IconButton(
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        icon: const Icon(Icons.arrow_back_ios_new_rounded),
        onPressed: onClose ?? () => Navigator.of(context).maybePop(),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppTokens.s4),
        children: [
          SettingsGroup(
            margin: const EdgeInsets.only(bottom: AppTokens.s4),
            children: [cell('选择背景图', 'Choose Background', onSelect)],
          ),
          SettingsGroup(
            margin: EdgeInsets.zero,
            children: [
              cell('从手机相册选择', 'Choose from Photos', onPhotos),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: AppTokens.s5),
                child: Divider(
                  height: 0,
                  thickness: ChatBackgroundMenuTokens.dividerWidth,
                  color: AppTokens.border(dark: dark),
                ),
              ),
              cell('拍一张', 'Take a Photo', onCamera),
            ],
          ),
          if (busy) const LinearProgressIndicator(),
        ],
      ),
      children: const [],
    );
  }
}
