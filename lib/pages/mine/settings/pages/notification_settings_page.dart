import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'package:permission_handler/permission_handler.dart';

import '../settings_draft_store.dart';
import '../settings_navigation.dart';
import '../settings_service.dart';
import '../widgets/settings_widgets.dart';
import 'message_notification_sound_picker_page.dart';

class NotificationSettingsPage extends StatelessWidget {
  const NotificationSettingsPage({
    super.key,
    required this.store,
    this.service = const StubSettingsService(),
  });

  final SettingsDraftStore store;
  final SettingsService service;

  String _previewLabel(BuildContext context, String value) {
    switch (value) {
      case 'none':
        return settingsText(context, zh: '不显示详情', en: 'Hide details');
      case 'sender':
        return settingsText(context, zh: '仅显示发送人', en: 'Sender only');
      default:
        return settingsText(context, zh: '显示发送人和内容', en: 'Sender and message');
    }
  }

  Future<void> _choosePreview(
    BuildContext context, {
    required bool opened,
  }) async {
    final current = opened
        ? store.openedNotificationPreview
        : store.closedNotificationPreview;
    final result = await showSettingsActionSheet<String>(
      context,
      title: settingsText(context, zh: '通知显示内容', en: 'Notification Content'),
      actions: [
        SettingsAction(
          settingsText(context, zh: '显示发送人和内容', en: 'Sender and message'),
          'detail',
          selected: current == 'detail',
        ),
        SettingsAction(
          settingsText(context, zh: '仅显示发送人', en: 'Sender only'),
          'sender',
          selected: current == 'sender',
        ),
        SettingsAction(
          settingsText(context, zh: '不显示详情', en: 'Hide details'),
          'none',
          selected: current == 'none',
        ),
      ],
    );
    if (result == null) return;
    if (opened) {
      store.updateNotifications(openedPreview: result);
      return;
    }
    if (!service.isBackendAvailable) {
      showUnavailableSettingsAction(
        context,
        settingsText(context, zh: '通知显示内容', en: 'Notification content'),
      );
      return;
    }
    await service.updateClosedNotificationPreview(result);
    store.updateNotifications(closedPreview: result);
  }

  Future<void> _updateSystemMessages(BuildContext context, bool value) async {
    if (!service.isBackendAvailable) {
      showUnavailableSettingsAction(
        context,
        settingsText(
          context,
          zh: '系统消息通知',
          en: 'System message notifications',
        ),
      );
      return;
    }
    await service.updateSystemMessageNotification(value);
    store.updateNotifications(closed: value);
  }

  String _messageSoundLabel(BuildContext context) =>
      MessageNotificationSoundPickerPage.label(context, store.messageSound);


  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: store,
        builder: (context, _) => SettingsScaffold(
          title: settingsText(context, zh: '通知', en: 'Notifications'),
          children: [
            const _SystemNotificationPermissionBanner(),
            SettingsSectionText(
              settingsText(context, zh: '未打开时', en: 'When the app is closed'),
              top: 12,
              bottom: 8,
            ),
            SettingsGroup(children: [
              SettingsSwitchCell(
                title: settingsText(context, zh: '系统消息通知', en: 'System Message Notifications'),
                value: store.notifyWhenClosed,
                onChanged: (v) => _updateSystemMessages(context, v),
              ),
              SettingsSwitchCell(
                title: settingsText(
                  context,
                  zh: '语音和视频通话用弹窗快捷接听',
                  en: 'Quick Answer Popup for Voice and Video Calls',
                ),
                value: store.quickAnswer,
                onChanged: (v) => store.updateNotifications(quickAnswer: v),
              ),
              SettingsCell(
                title: settingsText(context, zh: '通知显示内容', en: 'Notification Content'),
                value: _previewLabel(context, store.closedNotificationPreview),
                showDivider: false,
                onTap: () => _choosePreview(context, opened: false),
              ),
            ]),
            SettingsSectionText(
              settingsText(context, zh: '打开时', en: 'When the app is open'),
              bottom: 8,
            ),
            SettingsGroup(children: [
              SettingsSwitchCell(
                title: settingsText(context, zh: '打开时通知', en: 'Notify When Open'),
                value: store.notifyWhenOpen,
                onChanged: (v) => store.updateNotifications(opened: v),
              ),
              SettingsCell(
                title: '- ${settingsText(context, zh: '通知显示内容', en: 'Notification Content')}',
                value: _previewLabel(context, store.openedNotificationPreview),
                enabled: store.notifyWhenOpen,
                indent: 8,
                onTap: () => _choosePreview(context, opened: true),
              ),
              SettingsSwitchCell(
                title: settingsText(context, zh: '消息提示音', en: 'Message Sound'),
                value: store.messageSoundEnabled,
                onChanged: (v) => store.updateNotifications(messageSoundEnabled: v),
              ),
              SettingsCell(
                title: '- ${settingsText(context, zh: '默认提示音', en: 'Default Sound')}',
                value: _messageSoundLabel(context),
                enabled: store.messageSoundEnabled,
                indent: 8,
                onTap: store.messageSoundEnabled
                    ? () => openSettingsPage(
                          context,
                          MessageNotificationSoundPickerPage(store: store),
                        )
                    : null,
              ),
              SettingsSwitchCell(
                title: settingsText(
                  context,
                  zh: '语音和视频通话来电铃声',
                  en: 'Call Ringtone for Voice and Video Calls',
                ),
                value: store.callRingtoneEnabled,
                onChanged: (v) => store.updateNotifications(callRingtoneEnabled: v),
              ),
              SettingsSwitchCell(
                title: settingsText(context, zh: '振动', en: 'Vibration'),
                value: store.vibration,
                onChanged: (v) => store.updateNotifications(vibration: v),
                showDivider: false,
              ),
            ]),
          ],
        ),
      );
}


class _SystemNotificationPermissionBanner extends StatefulWidget {
  const _SystemNotificationPermissionBanner();

  @override
  State<_SystemNotificationPermissionBanner> createState() =>
      _SystemNotificationPermissionBannerState();
}

class _SystemNotificationPermissionBannerState
    extends State<_SystemNotificationPermissionBanner>
    with WidgetsBindingObserver {
  bool _loading = true;
  bool _granted = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final status = await Permission.notification.status;
      if (!mounted) return;
      setState(() {
        _granted = status.isGranted || status.isLimited;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        // Older platforms that do not expose a runtime notification
        // permission should not show a misleading warning banner.
        _granted = true;
        _loading = false;
      });
    }
  }

  Future<void> _request() async {
    try {
      final status = await Permission.notification.request();
      if (!mounted) return;
      if (status.isPermanentlyDenied || status.isRestricted) {
        await openAppSettings();
      }
    } finally {
      if (mounted) await _refresh();
    }
  }

  Future<void> _openSettings() async {
    await openAppSettings();
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _granted) return const SizedBox.shrink();
    final dark = settingsIsDark(context);
    final foreground = dark ? const Color(0xFFFFD591) : const Color(0xFFB45309);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: dark ? const Color(0xFF3A2E14) : const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                settingsText(
                  context,
                  zh: '系统通知权限未开启，离线消息与通话提醒将无法送达。',
                  en: 'System notifications are off. Offline messages and call alerts will not be delivered.',
                ),
                style: TextStyle(color: foreground, fontSize: 13, height: 1.45),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  TextButton(
                    onPressed: _request,
                    child: Text(settingsText(context, zh: '立即开启', en: 'Enable now')),
                  ),
                  TextButton(
                    onPressed: _openSettings,
                    child: Text(settingsText(context, zh: '前往系统设置', en: 'Open system settings')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
