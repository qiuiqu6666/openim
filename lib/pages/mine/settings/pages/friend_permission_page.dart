import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import '../../../../routes/app_navigator.dart';
import '../../../../core/controller/im_controller.dart';
import '../../account_setup/presence_visibility_store.dart';
import '../settings_draft_store.dart';
import '../settings_navigation.dart';
import '../settings_service.dart';
import '../widgets/settings_widgets.dart';
import 'add_friend_privacy_page.dart';

class FriendPermissionPage extends StatefulWidget {
  const FriendPermissionPage(
      {super.key,
      required this.store,
      this.service = const StubSettingsService()});
  final SettingsDraftStore store;
  final SettingsService service;
  @override
  State<FriendPermissionPage> createState() => _FriendPermissionPageState();
}

class _FriendPermissionPageState extends State<FriendPermissionPage> {
  bool _loading = false, _saving = false;
  String? _error;
  PresenceVisibilityStore? _visibility;
  StreamSubscription? _notifications;
  String text(String zh, String en) => settingsText(context, zh: zh, en: en);
  @override
  void initState() {
    super.initState();
    if (widget.service.supportsFriendPermissions) _load();
    if (widget.service.supportsPresenceVisibility) {
      _visibility = PresenceVisibilityStore();
      if (Get.isRegistered<IMController>()) {
        _notifications = Get.find<IMController>()
            .customBusinessMessageSubject
            .listen(_visibility!.onNotification);
      }
      _visibility!.refresh();
    }
  }

  Future<void> _load() async {
    if (_loading || _saving) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.service.getFriendPermissions();
      if (mounted) widget.store.syncFriendPermissions(data);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = text('权限加载失败，请重试', 'Could not load permissions. Retry.');
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _setAllowed(bool value) async {
    if (_saving || _loading || !widget.store.friendPermissionsLoaded) return;
    setState(() {
      _saving = true;
    });
    try {
      await widget.service.updateAllowAddFriend(value);
      if (!mounted) return;
      widget.store.setAllowAddFriend(value);
      showSettingsMessage(context, text('已保存', 'Saved'));
    } catch (error) {
      if (mounted) {
        showSettingsError(
            context, error, text('保存失败，请重试', 'Could not save. Retry.'));
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _setVisibility(bool value) async {
    final visibility = _visibility!;
    await visibility.setVisible(value);
    if (mounted && visibility.showLastSeen.value == value) {
      showSettingsMessage(context, text('已保存', 'Saved'));
    }
  }

  @override
  void dispose() {
    _notifications?.cancel();
    _visibility?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final store = widget.store;
        final ready = widget.service.supportsFriendPermissions &&
            store.friendPermissionsLoaded &&
            !_loading &&
            _error == null &&
            !_saving;
        return Stack(children: [
          SettingsScaffold(
              title: text('朋友权限', 'Friend Permissions'),
              children: [
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.all(AppTokens.s5),
                      child: Column(children: [
                        Text(_error!),
                        TextButton(
                            onPressed: _load, child: Text(text('重试', 'Retry')))
                      ])),
                SettingsGroup(children: [
                  _ToggleCell(
                      title: text('允许别人添加我', 'Allow Friend Requests'),
                      subtitle: text('关闭后，其他人将无法向你发送好友申请。',
                          'When off, others cannot send you friend requests.'),
                      value: store.allowAddFriend,
                      onChanged: ready ? _setAllowed : null),
                  SettingsCell(
                      title: text('添加我的方式', 'Ways to Find Me'),
                      showDivider: false,
                      onTap: ready
                          ? () => openSettingsPage(
                              context,
                              AddFriendPrivacyPage(
                                  store: store, service: widget.service))
                          : null),
                ]),
                if (!widget.service.supportsFriendPermissions)
                  Padding(
                      padding: const EdgeInsets.all(AppTokens.s5),
                      child: Text(text('当前服务暂不支持修改好友添加权限',
                          'Friend permission updates are unavailable.'))),
                SettingsGroup(children: [
                  SettingsCell(
                      title: text('黑名单', 'Blacklist'),
                      showDivider: false,
                      onTap: AppNavigator.startBlacklist)
                ]),
                SettingsGroup(children: [
                  if (_visibility != null)
                    Obx(() => _ToggleCell(
                          title: text('显示上线时间', 'Show Last Seen'),
                          minSubtitleLines: 2,
                          showDivider: false,
                          subtitle: !_visibility!.ready.value
                              ? text('正在获取设置…', 'Loading setting…')
                              : _visibility!.showLastSeen.value
                                  ? text('已开启，其他人可以看到你的具体上线时间。',
                                      'Enabled. Others can see your exact last seen time.')
                                  : text('已关闭，其他人无法看到你的具体上线时间。',
                                      'Disabled. Others cannot see your exact last seen time.'),
                          value: _visibility!.showLastSeen.value,
                          onChanged: _visibility!.ready.value &&
                                  !_visibility!.busy.value
                              ? _setVisibility
                              : null,
                        ))
                  else
                    _ToggleCell(
                        title: text('显示上线时间', 'Show Last Seen'),
                        minSubtitleLines: 2,
                        showDivider: false,
                        subtitle: text('当前服务未支持此权限设置；仅好友可见暂不支持。',
                            'This service does not support this setting. Friends-only visibility is unavailable.'),
                        value: true,
                        onChanged: null),
                  if (_visibility != null)
                    Obx(() => _visibility!.failed.value
                        ? TextButton(
                            onPressed: _visibility!.refresh,
                            child: Text(text('上线时间权限加载失败，点击重试',
                                'Could not load last-seen privacy. Retry.')))
                        : const SizedBox.shrink()),
                ]),
              ]),
          if (_loading || _saving)
            Positioned.fill(
                child: IgnorePointer(
                    child: Center(child: LoadingView.indicator()))),
        ]);
      });
}

class _ToggleCell extends StatelessWidget {
  const _ToggleCell({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.showDivider = true,
    this.minSubtitleLines = 1,
  });

  final String title;
  final String subtitle;
  final bool value;
  final bool showDivider;
  final int minSubtitleLines;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppTokens.textPrimary(dark: dark),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                ConstrainedBox(
                    constraints: BoxConstraints(
                        minHeight: MediaQuery.textScalerOf(context).scale(13) *
                            1.4 *
                            minSubtitleLines),
                    child: Text(
                      subtitle,
                      style: TextStyle(
                        color: AppTokens.textSecondary(dark: dark),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    )),
              ],
            ),
          ),
          const SizedBox(width: 12),
          AppSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
