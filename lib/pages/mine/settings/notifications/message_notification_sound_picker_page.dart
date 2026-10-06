import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../../core/notifications/message_notification_sound.dart';
import '../../../../core/notifications/notification_sound_activity.dart';
import 'package:openim_live/openim_live.dart' show OpenIMLiveClient;
import '../settings_draft_store.dart';
import '../widgets/settings_widgets.dart';
import 'message_notification_sound_preview.dart';

class MessageNotificationSoundPickerPage extends StatefulWidget {
  const MessageNotificationSoundPickerPage({
    super.key,
    required this.store,
    this.preview,
    this.isCallActive,
  });

  final SettingsDraftStore store;

  /// The route owns and disposes the supplied preview player.
  final MessageNotificationSoundPreview? preview;
  final bool Function()? isCallActive;

  static const List<String> optionIds = MessageNotificationSoundIds.optionIds;

  static String normalizedId(String? value) =>
      MessageNotificationSoundIds.normalizedId(value);

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

  @override
  State<MessageNotificationSoundPickerPage> createState() =>
      _MessageNotificationSoundPickerPageState();
}

class _MessageNotificationSoundPickerPageState
    extends State<MessageNotificationSoundPickerPage>
    with WidgetsBindingObserver {
  late final MessageNotificationSoundPreview _preview;
  StreamSubscription<void>? _audioInterruptions;
  Future<void> _preparing = Future<void>.value();
  int _version = 0;
  String? _previewError;

  @override
  void initState() {
    super.initState();
    _preview = widget.preview ?? AudioMessageNotificationSoundPreview();
    _audioInterruptions = NotificationSoundActivity.interruptions.listen((_) {
      _version++;
      _stopPreview();
    });
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(MessageNotificationSoundPickerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.store, oldWidget.store)) {
      _version++;
      _stopPreview();
    }
  }

  @override
  void dispose() {
    _version++;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_audioInterruptions?.cancel());
    unawaited(_preview.dispose().catchError((Object _) {}));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _version++;
      _stopPreview();
    }
  }

  void _stopPreview() {
    // Stop is allowed to interrupt an in-flight native load immediately.
    unawaited(_preview.stop().catchError((Object _) {}));
  }

  bool _current(int version, SettingsDraftStore store) =>
      mounted &&
      version == _version &&
      identical(widget.store, store) &&
      store.isCurrentAccount;

  void _showPreviewError(int version, SettingsDraftStore store) {
    if (!_current(version, store)) return;
    setState(() => _previewError = settingsText(context,
        zh: '暂时无法试听该提示音', en: 'Unable to preview this sound right now.'));
  }

  bool get _callActive =>
      widget.isCallActive?.call() ??
      (OpenIMLiveClient().isBusy ||
          PackageBridge.rtcBridge?.hasConnection == true);

  bool _allowPreview(int version, SettingsDraftStore store) {
    if (!_current(version, store)) return false;
    if (!_callActive) return true;
    setState(() => _previewError = settingsText(context,
        zh: '提示音已选择，请在通话结束后试听。',
        en: 'Sound selected. Preview it after the call ends.'));
    return false;
  }

  void _selectAndPreview(String id) {
    final store = widget.store;
    if (!store.isCurrentAccount || !store.messageSoundEnabled) return;
    final version = ++_version;
    store.updateNotifications(messageSound: id);
    setState(() => _previewError = null);
    if (!_allowPreview(version, store)) {
      _stopPreview();
      return;
    }
    _preparing = _preparing.then((_) async {
      if (!_allowPreview(version, store)) return;
      try {
        await _preview.stop();
        if (!_allowPreview(version, store)) return;
        await _preview.load(id);
        if (!_allowPreview(version, store)) return;
        // AudioPlayer.play completes when playback stops. Keep preparation free
        // so a newer selection can stop playback immediately after loading.
        unawaited(_preview.play().catchError((Object error) {
          _showPreviewError(version, store);
        }));
      } catch (_) {
        _showPreviewError(version, store);
      }
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final selected = MessageNotificationSoundPickerPage.normalizedId(
              widget.store.messageSound);
          final enabled =
              widget.store.isCurrentAccount && widget.store.messageSoundEnabled;
          return SettingsScaffold(
            title: settingsText(context, zh: '消息提示音', en: 'Message Sound'),
            children: [
              if (_previewError != null)
                SettingsSectionText(_previewError!,
                    key: const ValueKey('notification-sound-preview-error')),
              SettingsGroup(
                margin: EdgeInsets.zero,
                children: [
                  for (final id in MessageNotificationSoundPickerPage.optionIds)
                    Semantics(
                      selected: selected == id,
                      child: SettingsCell(
                        key: ValueKey('notification-sound-$id'),
                        title: MessageNotificationSoundPickerPage.label(
                            context, id),
                        enabled: enabled,
                        showArrow: false,
                        showDivider: id !=
                            MessageNotificationSoundPickerPage.optionIds.last,
                        trailing: selected == id
                            ? const ExcludeSemantics(
                                child: Icon(Icons.check_rounded,
                                    color: AppTokens.accent,
                                    size: AppTokens.chevronSize))
                            : null,
                        onTap: () => _selectAndPreview(id),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      );
}
