import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../mine/settings/widgets/settings_widgets.dart';
import 'message_retention/widgets/message_retention_setting.dart';

class MessageRetentionPage extends StatefulWidget {
  const MessageRetentionPage({super.key, required this.conversation});
  final ConversationInfo conversation;

  @override
  State<MessageRetentionPage> createState() => _MessageRetentionPageState();
}

class _MessageRetentionPageState extends State<MessageRetentionPage> {
  late ConversationInfo _info;
  late final String _account;
  late final String? _token;
  late final String? _imToken;
  bool _loading = false;
  bool _busy = false;
  bool _choosing = false;
  String? _loadError;
  String? _saveError;
  ({int? burn, int? retain})? _failedChange;

  bool get _current =>
      mounted &&
      OpenIM.iMManager.userID == _account &&
      DataSp.chatToken == _token &&
      DataSp.imToken == _imToken;
  bool get _enabled => _current && !_loading && !_busy && !_choosing;
  int get _burn => _info.isPrivateChat == true ? (_info.burnDuration ?? 30) : 0;
  int get _retain =>
      _info.isMsgDestruct == true ? (_info.msgDestructTime ?? 86400) : 0;

  String _label(String zh, String en) => settingsText(context, zh: zh, en: en);

  @override
  void initState() {
    super.initState();
    _info = widget.conversation;
    _account = OpenIM.iMManager.userID;
    _token = DataSp.chatToken;
    _imToken = DataSp.imToken;
    unawaited(_load());
  }

  Future<ConversationInfo> _read() async {
    final updated = await OpenIM.iMManager.conversationManager
        .getMultipleConversation(conversationIDList: [_info.conversationID]);
    return updated
        .firstWhere((item) => item.conversationID == _info.conversationID);
  }

  Future<void> _load() async {
    if (!_current || _busy || _loading || _choosing) {
      return;
    }
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final updated = await _read();
      if (_current) {
        setState(() => _info = updated);
      }
    } catch (_) {
      if (_current) {
        setState(() => _loadError = _label(
            '设置暂时无法获取，请重试。', 'Could not load settings. Please try again.'));
      }
    } finally {
      if (_current) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save({int? burn, int? retain}) async {
    if (!_current || _busy || _loading) {
      return;
    }
    setState(() {
      _busy = true;
      _saveError = null;
      _failedChange = null;
    });
    try {
      await OpenIM.iMManager.conversationManager.setConversation(
          _info.conversationID,
          ConversationReq(
              isPrivateChat: burn == null ? null : burn > 0,
              burnDuration: burn == null || burn == 0 ? null : burn,
              isMsgDestruct: retain == null ? null : retain > 0,
              msgDestructTime: retain == null || retain == 0 ? null : retain));
      if (!_current) {
        return;
      }
      final updated = await _read();
      if (_current) {
        setState(() {
          _info = updated;
          _loadError = null;
        });
      }
    } catch (_) {
      if (_current) {
        setState(() {
          _saveError = _label(
              '设置未能更新，请重试。', 'Could not update settings. Please try again.');
          _failedChange = (burn: burn, retain: retain);
        });
      }
    } finally {
      if (_current) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _choose({required bool burn}) async {
    if (!_enabled) {
      return;
    }
    final current = burn ? _burn : _retain;
    final values = burn ? _burnValues : _retainValues;
    if (!values.containsKey(current)) {
      values[current] = '$current ${'sdkSeconds'.tr}';
    }
    setState(() => _choosing = true);
    final value = await showSettingsActionSheet<int>(context,
        title: burn ? 'sdkBurn'.tr : 'sdkAutoDelete'.tr,
        actions: values.entries
            .map((entry) => SettingsAction<int>(entry.value, entry.key,
                subtitle: entry.key == current
                    ? _label('当前设置', 'Current setting')
                    : null,
                selected: entry.key == current))
            .toList());
    if (!_current) {
      return;
    }
    setState(() => _choosing = false);
    if (value == null || value == current) {
      return;
    }
    await _save(burn: burn ? value : null, retain: burn ? null : value);
  }

  Map<int, String> get _burnValues => {
        0: 'sdkOff'.tr,
        30: '30 ${'sdkSeconds'.tr}',
        60: '1 ${'sdkMinutes'.tr}',
        300: '5 ${'sdkMinutes'.tr}',
      };

  Map<int, String> get _retainValues => {
        0: 'sdkOff'.tr,
        86400: '1 ${'sdkDays'.tr}',
        604800: '7 ${'sdkDays'.tr}',
        2592000: '30 ${'sdkDays'.tr}',
      };

  String _value(int seconds, Map<int, String> options) =>
      options[seconds] ?? '$seconds ${'sdkSeconds'.tr}';

  Widget _feedback(String message,
          {Key? retryKey, VoidCallback? retry, bool progress = false}) =>
      Semantics(
        liveRegion: true,
        child: SettingsGroup(children: [
          SettingsCell(
              title: message,
              showArrow: false,
              showDivider: retry != null,
              trailing: progress
                  ? const SizedBox.square(
                      dimension: AppTokens.s6,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : null),
          if (retry != null)
            SettingsCell(
                key: retryKey,
                title: _label('重试', 'Retry'),
                icon: Icons.refresh_rounded,
                showArrow: false,
                showDivider: false,
                enabled: _enabled,
                onTap: retry),
        ]),
      );

  @override
  Widget build(BuildContext context) =>
      SettingsScaffold(title: 'sdkRetention'.tr, children: [
        if (_loading)
          _feedback(_label('正在获取设置…', 'Loading settings…'), progress: true),
        if (_loadError != null)
          _feedback(_loadError!,
              retryKey: const ValueKey('retention-load-retry'), retry: _load),
        if (_busy) _feedback(_label('正在保存…', 'Saving…'), progress: true),
        if (_saveError != null)
          _feedback(_saveError!,
              retryKey: const ValueKey('retention-save-retry'), retry: () {
            final change = _failedChange;
            if (change != null) {
              unawaited(_save(burn: change.burn, retain: change.retain));
            }
          }),
        if (_info.isSingleChat)
          MessageRetentionSetting(
              rowKey: const ValueKey('retention-burn-row'),
              title: 'sdkBurn'.tr,
              value: _value(_burn, _burnValues),
              description: _label('消息已读后开始计时，到期自动删除。',
                  'The timer starts once a message is read. It is deleted when the time is up.'),
              icon: Icons.timer_outlined,
              enabled: _enabled,
              onTap: () => _choose(burn: true)),
        MessageRetentionSetting(
            rowKey: const ValueKey('retention-delete-row'),
            title: 'sdkAutoDelete'.tr,
            value: _value(_retain, _retainValues),
            description: _label('超过保留时长的消息会自动删除。',
                'Messages older than the selected period are deleted automatically.'),
            icon: Icons.auto_delete_outlined,
            enabled: _enabled,
            onTap: () => _choose(burn: false)),
      ]);
}
