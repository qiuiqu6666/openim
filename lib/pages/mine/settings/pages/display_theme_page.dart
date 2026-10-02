import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../../theme/app_theme_controller.dart';
import '../settings_draft_store.dart';
import '../settings_navigation.dart';
import '../widgets/settings_widgets.dart';
import 'chat_background_page.dart';
import 'font_size_page.dart';

class DisplayThemePage extends StatelessWidget {
  const DisplayThemePage({super.key, required this.store});

  final SettingsDraftStore store;

  String _themeLabel(BuildContext context, ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return settingsText(context, zh: '深色模式', en: 'Dark');
      case ThemeMode.light:
        return settingsText(context, zh: '日间模式', en: 'Light');
      case ThemeMode.system:
        return settingsText(context, zh: '跟随系统', en: 'System');
    }
  }

  Future<void> _chooseTheme(BuildContext context) async {
    final controller = AppThemeController.instance;
    final selected = await showSettingsActionSheet<ThemeMode>(
      context,
      title: settingsText(context, zh: '选择主题', en: 'Choose Theme'),
      actions: [
        SettingsAction(
          settingsText(context, zh: '跟随系统', en: 'System'),
          ThemeMode.system,
          selected: controller.mode == ThemeMode.system,
        ),
        SettingsAction(
          settingsText(context, zh: '日间模式', en: 'Light'),
          ThemeMode.light,
          selected: controller.mode == ThemeMode.light,
        ),
        SettingsAction(
          settingsText(context, zh: '深色模式', en: 'Dark'),
          ThemeMode.dark,
          selected: controller.mode == ThemeMode.dark,
        ),
      ],
    );
    if (selected != null) await controller.setMode(selected);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([AppThemeController.instance, store]),
        builder: (context, _) => SettingsScaffold(
          title: settingsText(context, zh: '界面与显示', en: 'Appearance'),
          children: [
            SettingsGroup(margin: EdgeInsets.zero, children: [
              SettingsCell(
                title: settingsText(context, zh: '皮肤主题', en: 'Theme'),
                value: _themeLabel(context, AppThemeController.instance.mode),
                onTap: () => _chooseTheme(context),
              ),
              SettingsCell(
                title: settingsText(context, zh: '字体大小', en: 'Text Size'),
                value: FontSizePage.labelFor(context, store.fontSizeIndex),
                onTap: () => openSettingsPage(
                  context,
                  FontSizePage(store: store),
                ),
              ),
              SettingsCell(
                title: settingsText(context, zh: '全局默认聊天背景', en: 'Default Chat Background'),
                onTap: () => openSettingsPage(
                  context,
                  ChatBackgroundPage(store: store),
                ),
              ),
              SettingsCell(
                title: settingsText(context, zh: '多语言选择', en: 'Language'),
                value: _languageLabel(context),
                showDivider: false,
                onTap: () => _chooseLanguage(context),
              ),
            ]),
          ],
        ),
      );

  String _languageLabel(BuildContext context) {
    switch (DataSp.getLanguage() ?? 0) {
      case 1:
        return '简体中文';
      case 2:
        return 'English';
      default:
        return settingsText(context, zh: '跟随系统', en: 'System');
    }
  }

  Future<void> _chooseLanguage(BuildContext context) async {
    final current = DataSp.getLanguage() ?? 0;
    final selected = await showSettingsActionSheet<int>(
      context,
      title: settingsText(context, zh: '选择语言', en: 'Choose Language'),
      actions: [
        SettingsAction(
          settingsText(context, zh: '跟随系统', en: 'System'),
          0,
          selected: current == 0,
        ),
        SettingsAction('简体中文', 1, selected: current == 1),
        SettingsAction('English', 2, selected: current == 2),
      ],
    );
    if (selected == null || selected == current) return;

    await DataSp.putLanguage(selected);
    switch (selected) {
      case 1:
        Get.updateLocale(const Locale('zh', 'CN'));
        break;
      case 2:
        Get.updateLocale(const Locale('en', 'US'));
        break;
      default:
        Get.updateLocale(PlatformDispatcher.instance.locale);
        break;
    }
  }
}
