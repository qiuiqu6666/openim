import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../chat_background_local_service.dart';
import '../../widgets/settings_widgets.dart';
import 'chat_background_menu_tokens.dart';

class ChatBackgroundPicker extends StatefulWidget {
  const ChatBackgroundPicker(
      {super.key, this.initialValue, required this.onSave});

  final String? initialValue;
  final Future<void> Function(String?) onSave;

  @override
  State<ChatBackgroundPicker> createState() => _ChatBackgroundPickerState();
}

class _ChatBackgroundPickerState extends State<ChatBackgroundPicker> {
  late String? _selected = widget.initialValue;
  bool _saving = false;

  Future<void> _save() async {
    if (_saving || _selected == widget.initialValue) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(_selected);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        showSettingsMessage(
            context,
            settingsText(context,
                zh: '保存失败，请重试', en: 'Unable to save. Please try again.'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final background =
        dark ? AppTokens.backgroundDark : ChatBackgroundMenuTokens.background;
    final foreground = AppTokens.textPrimary(dark: dark);
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        backgroundColor: background,
        appBar: AppBar(
          backgroundColor: background,
          foregroundColor: foreground,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: AppSystemBars.styleFor(background),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          automaticallyImplyLeading: false,
          leadingWidth: ChatBackgroundMenuTokens.actionWidth,
          leading: TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).maybePop(),
            style: TextButton.styleFrom(foregroundColor: foreground),
            child: Text(settingsText(context, zh: '取消', en: 'Cancel')),
          ),
          title: Text(
              settingsText(context, zh: '选择背景图', en: 'Choose Background'),
              style: TextStyle(
                  color: foreground,
                  fontSize: AppTokens.listTitleFontSize,
                  fontWeight: FontWeight.w600)),
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppTokens.s3),
              child: FilledButton(
                onPressed:
                    _saving || _selected == widget.initialValue ? null : _save,
                style:
                    FilledButton.styleFrom(backgroundColor: AppTokens.accent),
                child: Text(settingsText(context,
                    zh: _saving ? '保存中' : '完成',
                    en: _saving ? 'Saving' : 'Done')),
              ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: GridView.builder(
            padding: const EdgeInsets.all(AppTokens.s3),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: AppTokens.s2,
              crossAxisSpacing: AppTokens.s2,
            ),
            itemCount: ChatBackgroundMenuTokens.options.length,
            itemBuilder: (context, index) {
              final value = ChatBackgroundMenuTokens.options[index];
              final selected = value == _selected;
              final asset = ChatBackgroundLocalService.assetOf(value);
              final label = settingsText(context,
                  zh: ChatBackgroundMenuTokens.titlesZh[index],
                  en: ChatBackgroundMenuTokens.titlesEn[index]);
              return Semantics(
                label: label,
                button: true,
                selected: selected,
                enabled: !_saving,
                child: Material(
                  color:
                      ChatBackgroundLocalService.colorOf(value) ?? background,
                  borderRadius: BorderRadius.circular(AppTokens.s2),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _saving
                        ? null
                        : () => setState(() => _selected = value),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (asset != null)
                          Ink.image(
                              image: ResizeImage(
                                  AssetImage(asset, package: 'openim_common'),
                                  width:
                                      ChatBackgroundMenuTokens.thumbnailWidth),
                              fit: BoxFit.cover),
                        if (selected)
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              height: AppTokens.s7,
                              width: double.infinity,
                              color: AppTokens.accent,
                              child: Icon(Icons.check_rounded,
                                  color:
                                      Theme.of(context).colorScheme.onPrimary,
                                  size: AppTokens.s6),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
