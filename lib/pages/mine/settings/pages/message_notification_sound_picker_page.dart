import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:openim_common/openim_common.dart';

import '../settings_draft_store.dart';
import '../widgets/settings_widgets.dart';

class MessageNotificationSoundPickerPage extends StatefulWidget {
  const MessageNotificationSoundPickerPage({
    super.key,
    required this.store,
  });

  final SettingsDraftStore store;

  @override
  State<MessageNotificationSoundPickerPage> createState() =>
      _MessageNotificationSoundPickerPageState();

  static const List<String> optionIds = <String>[
    'preview000',
    'crisp',
    'soft',
    'chime',
    'preview',
    'preview1',
    'preview04',
  ];

  static String normalizedId(String? value) {
    final id = value?.trim() ?? '';
    if (id.isEmpty || id == 'default' || id == 'system') return optionIds.first;
    return optionIds.contains(id) ? id : optionIds.first;
  }

  static String label(BuildContext context, String id) {
    switch (normalizedId(id)) {
      case 'crisp':
        return settingsText(context, zh: '清脆', en: 'Crisp');
      case 'soft':
        return settingsText(context, zh: '柔和', en: 'Soft');
      case 'chime':
        return settingsText(context, zh: '叮咚', en: 'Chime');
      case 'preview':
        return settingsText(context, zh: '简约', en: 'Minimal');
      case 'preview1':
        return settingsText(context, zh: '明快', en: 'Bright');
      case 'preview04':
        return settingsText(context, zh: '悦耳', en: 'Pleasant');
      default:
        return settingsText(context, zh: '默认', en: 'Default');
    }
  }
}

class _MessageNotificationSoundPickerPageState
    extends State<MessageNotificationSoundPickerPage> {
  final AudioPlayer _player = AudioPlayer();

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _selectAndPreview(String id) async {
    widget.store.updateNotifications(messageSound: id);
    try {
      await _player.stop();
      await _player.setAsset(
        'assets/audio/99chat/$id.wav',
        package: 'openim_common',
      );
      await _player.seek(Duration.zero);
      await _player.play();
    } catch (_) {
      if (!mounted) return;
      showSettingsMessage(
        context,
        settingsText(
          context,
          zh: '暂时无法试听该提示音',
          en: 'Unable to preview this sound right now.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final selected = MessageNotificationSoundPickerPage.normalizedId(
            widget.store.messageSound,
          );
          return SettingsScaffold(
            title: settingsText(context, zh: '消息提示音', en: 'Message Sound'),
            children: [
              SettingsGroup(
                margin: EdgeInsets.zero,
                children: [
                  for (var i = 0;
                      i < MessageNotificationSoundPickerPage.optionIds.length;
                      i++)
                    _SoundOptionCell(
                      label: MessageNotificationSoundPickerPage.label(
                        context,
                        MessageNotificationSoundPickerPage.optionIds[i],
                      ),
                      selected: MessageNotificationSoundPickerPage.optionIds[i] == selected,
                      showDivider: i <
                          MessageNotificationSoundPickerPage.optionIds.length - 1,
                      onTap: () => _selectAndPreview(
                        MessageNotificationSoundPickerPage.optionIds[i],
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      );
}

class _SoundOptionCell extends StatelessWidget {
  const _SoundOptionCell({
    required this.label,
    required this.selected,
    required this.showDivider,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool showDivider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(
            minHeight: SettingsResponsive.listRowMinHeight(context),
          ),
          padding: SettingsResponsive.listRowPadding(context),
          decoration: BoxDecoration(
            border: showDivider
                ? Border(
                    bottom: BorderSide(
                      color: AppTokens.border(dark: dark),
                      width: 0.7,
                    ),
                  )
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: AppTokens.textPrimary(dark: dark),
                    fontSize: 16,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_rounded,
                  color: AppTokens.accent,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
