import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../settings_draft_store.dart';
import '../settings_navigation.dart';
import '../settings_service.dart';
import '../widgets/settings_widgets.dart';
import '../pages/message_notification_sound_picker_page.dart';
import 'notification_permission_gateway.dart';
import 'widgets/notification_permission_banner.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({
    super.key,
    required this.store,
    this.service = const StubSettingsService(),
    this.permissionGateway = const SystemNotificationPermissionGateway(),
  });

  final SettingsDraftStore store;
  final SettingsService service;
  final NotificationPermissionGateway permissionGateway;

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  bool _savingRemote = false;
  bool _choosingPreview = false;
  String? _saveError;
  int _generation = 0;

  @override
  void didUpdateWidget(NotificationSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.store, oldWidget.store) ||
        !identical(widget.service, oldWidget.service)) {
      _generation++;
      _savingRemote = false;
      _choosingPreview = false;
      _saveError = null;
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }

  bool _accepts(int generation, SettingsDraftStore store) =>
      mounted &&
      generation == _generation &&
      identical(store, widget.store) &&
      store.isCurrentAccount;

  void _updateLocal(VoidCallback change) {
    if (widget.store.isCurrentAccount) change();
  }

  String _previewLabel(String value) {
    switch (value) {
      case 'hidden':
        return settingsText(context, zh: '不显示通知', en: 'Hide notifications');
      case 'none':
        return settingsText(context, zh: '不显示详情', en: 'Hide details');
      case 'sender':
        return settingsText(context, zh: '仅显示发送人', en: 'Sender only');
      default:
        return settingsText(context, zh: '显示发送人和内容', en: 'Sender and message');
    }
  }

  Future<void> _saveRemote(
    Future<void> Function() action,
    VoidCallback apply,
  ) async {
    if (_savingRemote || !widget.store.isCurrentAccount) return;
    if (!widget.service.supportsRemoteNotificationSettings) {
      apply();
      return;
    }
    final generation = _generation;
    final store = widget.store;
    setState(() {
      _savingRemote = true;
      _saveError = null;
    });
    try {
      await action();
      if (!mounted || !_accepts(generation, store)) return;
      apply();
    } catch (error) {
      if (!mounted || !_accepts(generation, store)) return;
      final message = settingsErrorMessage(context, error,
          fallback: settingsText(context,
              zh: '保存失败，请稍后重试。', en: 'Unable to save. Please retry.'));
      setState(() => _saveError = message);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _savingRemote = false);
      }
    }
  }

  Future<void> _choosePreview({required bool opened}) async {
    if (_choosingPreview ||
        !widget.store.isCurrentAccount ||
        (opened ? !widget.store.notifyWhenOpen : _savingRemote)) {
      return;
    }
    final generation = _generation;
    final store = widget.store;
    final current = opened
        ? store.openedNotificationPreview
        : store.closedNotificationPreview;
    _choosingPreview = true;
    try {
      final result = await showSettingsActionSheet<String>(
        context,
        title: settingsText(context, zh: '通知显示内容', en: 'Notification Content'),
        actions: [
          for (final id in ['detail', 'sender', 'none', 'hidden'])
            SettingsAction(_previewLabel(id), id, selected: current == id),
        ],
      );
      if (!_accepts(generation, store) || result == null || result == current) {
        return;
      }
      if (opened) {
        if (store.notifyWhenOpen) {
          store.updateNotifications(openedPreview: result);
        }
      } else {
        await _saveRemote(
          () => widget.service.updateClosedNotificationPreview(result),
          () => store.updateNotifications(closedPreview: result),
        );
      }
    } finally {
      if (mounted && generation == _generation) _choosingPreview = false;
    }
  }

  Future<void> _updateSystemMessages(bool value) async {
    final store = widget.store;
    if (value == store.notifyWhenClosed) return;
    await _saveRemote(
      () => widget.service.updateSystemMessageNotification(value),
      () => store.updateNotifications(closed: value),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final store = widget.store;
          final active = store.isCurrentAccount;
          final remoteEnabled = active && !_savingRemote;
          return SettingsScaffold(
            title: settingsText(context, zh: '通知', en: 'Notifications'),
            children: [
              NotificationPermissionBanner(gateway: widget.permissionGateway),
              if (_saveError != null)
                SettingsGroup(children: [
                  SettingsCell(
                    key: const ValueKey('notification-save-error'),
                    title: _saveError!,
                    titleWidget: Text(_saveError!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTokens.paymentError(
                                dark: settingsIsDark(context)))),
                    showArrow: false,
                    showDivider: false,
                  ),
                ]),
              if (_savingRemote)
                Semantics(
                  liveRegion: true,
                  child: SettingsSectionText(
                    settingsText(context, zh: '保存中…', en: 'Saving…'),
                    key: const ValueKey('notification-saving'),
                  ),
                ),
              SettingsSectionText(
                settingsText(context, zh: '未打开时', en: 'When the app is closed'),
                top: AppTokens.s4,
                bottom: AppTokens.s3,
              ),
              SettingsGroup(children: [
                SettingsSwitchCell(
                  key: const ValueKey('notification-closed-enabled'),
                  title: settingsText(context,
                      zh: '系统消息通知', en: 'System Message Notifications'),
                  value: store.notifyWhenClosed,
                  enabled: remoteEnabled,
                  onChanged: _updateSystemMessages,
                ),
                SettingsSwitchCell(
                  key: const ValueKey('notification-call-quick-answer'),
                  title: settingsText(context,
                      zh: '语音和视频通话用弹窗快捷接听',
                      en: 'Quick Answer Popup for Voice and Video Calls'),
                  value: store.quickAnswer,
                  enabled: active,
                  onChanged: (v) => _updateLocal(
                      () => store.updateNotifications(quickAnswer: v)),
                ),
                SettingsSwitchCell(
                  key: const ValueKey('notification-quick-reply'),
                  title: settingsText(context,
                      zh: '消息横幅快捷回复', en: 'Quick Reply in Message Banners'),
                  value: store.notificationQuickReply,
                  enabled: active,
                  onChanged: (v) => _updateLocal(() =>
                      store.updateNotifications(notificationQuickReply: v)),
                ),
                SettingsCell(
                  key: const ValueKey('notification-closed-preview'),
                  title: settingsText(context,
                      zh: '通知显示内容', en: 'Notification Content'),
                  value: _previewLabel(store.closedNotificationPreview),
                  enabled: remoteEnabled,
                  showDivider: false,
                  onTap: () => _choosePreview(opened: false),
                ),
              ]),
              SettingsSectionText(
                settingsText(context, zh: '打开时', en: 'When the app is open'),
                bottom: AppTokens.s3,
              ),
              SettingsGroup(children: [
                SettingsSwitchCell(
                  key: const ValueKey('notification-open-enabled'),
                  title: settingsText(context,
                      zh: '打开时通知', en: 'Notify When Open'),
                  value: store.notifyWhenOpen,
                  enabled: active,
                  onChanged: (v) =>
                      _updateLocal(() => store.updateNotifications(opened: v)),
                ),
                SettingsCell(
                  key: const ValueKey('notification-open-preview'),
                  title:
                      '- ${settingsText(context, zh: '通知显示内容', en: 'Notification Content')}',
                  value: _previewLabel(store.openedNotificationPreview),
                  enabled: active && store.notifyWhenOpen,
                  indent: AppTokens.s3,
                  onTap: () => _choosePreview(opened: true),
                ),
                SettingsSwitchCell(
                  key: const ValueKey('notification-message-sound-enabled'),
                  title:
                      settingsText(context, zh: '消息提示音', en: 'Message Sound'),
                  value: store.messageSoundEnabled,
                  enabled: active,
                  onChanged: (v) => _updateLocal(
                      () => store.updateNotifications(messageSoundEnabled: v)),
                ),
                SettingsCell(
                  key: const ValueKey('notification-message-sound'),
                  title:
                      '- ${settingsText(context, zh: '默认提示音', en: 'Default Sound')}',
                  value: MessageNotificationSoundPickerPage.label(
                      context, store.messageSound),
                  enabled: active && store.messageSoundEnabled,
                  indent: AppTokens.s3,
                  onTap: () => openSettingsPage(context,
                      MessageNotificationSoundPickerPage(store: store)),
                ),
                SettingsSwitchCell(
                  key: const ValueKey('notification-call-ringtone'),
                  title: settingsText(context,
                      zh: '语音和视频通话来电铃声',
                      en: 'Call Ringtone for Voice and Video Calls'),
                  value: store.callRingtoneEnabled,
                  enabled: active,
                  onChanged: (v) => _updateLocal(
                      () => store.updateNotifications(callRingtoneEnabled: v)),
                ),
                SettingsSwitchCell(
                  key: const ValueKey('notification-vibration'),
                  title: settingsText(context, zh: '振动', en: 'Vibration'),
                  value: store.vibration,
                  enabled: active,
                  onChanged: (v) => _updateLocal(
                      () => store.updateNotifications(vibration: v)),
                  showDivider: false,
                ),
              ]),
            ],
          );
        },
      );
}
