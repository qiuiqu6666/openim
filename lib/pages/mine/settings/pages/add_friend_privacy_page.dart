import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../settings_draft_store.dart';
import '../settings_service.dart';
import '../widgets/settings_widgets.dart';

class AddFriendPrivacyPage extends StatefulWidget {
  const AddFriendPrivacyPage({
    super.key,
    required this.store,
    this.service = const StubSettingsService(),
  });

  final SettingsDraftStore store;
  final SettingsService service;

  @override
  State<AddFriendPrivacyPage> createState() => _AddFriendPrivacyPageState();
}

class _AddFriendPrivacyPageState extends State<AddFriendPrivacyPage> {
  SettingsDraftStore get store => widget.store;
  SettingsService get service => widget.service;
  bool _saving = false;

  Future<void> _updateDiscovery({
    bool? qrCode,
    bool? businessCard,
    bool? group,
    bool? phone,
    bool? uid,
    bool? account,
    bool? email,
  }) async {
    if (_saving) return;
    if (!service.supportsFriendPermissions || !store.friendPermissionsLoaded) {
      showUnavailableSettingsAction(
        context,
        settingsText(context, zh: '添加我的方式', en: 'Ways to find me'),
      );
      return;
    }
    setState(() {
      _saving = true;
    });
    try {
      await service.updateFriendDiscovery(
        qrCode: qrCode,
        businessCard: businessCard,
        group: group,
        phone: phone,
        uid: uid,
        account: account,
        email: email,
      );
      if (!mounted) return;
      store.setFriendDiscovery(
        qrCode: qrCode,
        businessCard: businessCard,
        group: group,
        phone: phone,
        uid: uid,
        account: account,
        email: email,
      );
      showSettingsMessage(
          context, settingsText(context, zh: '已保存', en: 'Saved'));
    } catch (error) {
      if (mounted) {
        showSettingsError(
            context,
            error,
            settingsText(context,
                zh: '保存失败，请重试', en: 'Could not save. Retry.'));
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          final helperColor = settingsSecondaryTextColor(context);
          return SettingsScaffold(
            title: settingsText(context, zh: '添加我的方式', en: 'How to Add Me'),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Text(
                  settingsText(
                    context,
                    zh: '管理别人可以通过哪些方式找到你并添加你为好友。关闭后，对应入口将不再对你生效。',
                    en: 'Choose how others can find you and send friend requests. When disabled, that entry point will no longer work for you.',
                  ),
                  style: TextStyle(
                    color: helperColor,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ),
              SettingsGroup(
                margin: EdgeInsets.zero,
                children: [
                  _PrivacySwitchCell(
                    title: settingsText(context, zh: '二维码', en: 'QR Code'),
                    subtitle: settingsText(
                      context,
                      zh: '允许通过我的二维码添加',
                      en: 'Allow adding me via my QR code',
                    ),
                    value: store.allowQrCode,
                    onChanged:
                        _saving ? null : (v) => _updateDiscovery(qrCode: v),
                  ),
                  _PrivacySwitchCell(
                    title: settingsText(context, zh: '名片', en: 'Contact Card'),
                    subtitle: settingsText(
                      context,
                      zh: '允许通过名片转发添加',
                      en: 'Allow adding me via shared contact cards',
                    ),
                    value: store.allowBusinessCard,
                    onChanged: _saving
                        ? null
                        : (v) => _updateDiscovery(businessCard: v),
                  ),
                  _PrivacySwitchCell(
                    title: settingsText(context, zh: '群聊', en: 'Group Chat'),
                    subtitle: settingsText(
                      context,
                      zh: '允许群成员从群聊中添加',
                      en: 'Allow group members to add me from group chats',
                    ),
                    value: store.allowGroup,
                    onChanged:
                        _saving ? null : (v) => _updateDiscovery(group: v),
                  ),
                  _PrivacySwitchCell(
                    title: settingsText(context, zh: '手机号', en: 'Phone Number'),
                    subtitle: settingsText(
                      context,
                      zh: '允许通过手机号搜索添加',
                      en: 'Allow adding me by phone number search',
                    ),
                    value: store.allowPhone,
                    onChanged:
                        _saving ? null : (v) => _updateDiscovery(phone: v),
                  ),
                  _PrivacySwitchCell(
                    title:
                        settingsText(context, zh: '公开账号', en: 'Public Account'),
                    subtitle: settingsText(context,
                        zh: '允许通过公开账号添加',
                        en: 'Allow adding me by public account'),
                    value: store.allowAccount,
                    onChanged:
                        _saving ? null : (v) => _updateDiscovery(account: v),
                  ),
                  _PrivacySwitchCell(
                    title: settingsText(context, zh: '邮箱', en: 'Email'),
                    subtitle: settingsText(context,
                        zh: '允许通过邮箱搜索添加', en: 'Allow adding me by email'),
                    value: store.allowEmail,
                    onChanged:
                        _saving ? null : (v) => _updateDiscovery(email: v),
                  ),
                  _PrivacySwitchCell(
                    title: settingsText(context, zh: 'UID', en: 'UID'),
                    subtitle: settingsText(
                      context,
                      zh: '允许通过 UID 搜索添加',
                      en: 'Allow adding me by UID search',
                    ),
                    value: store.allowUid,
                    onChanged: _saving ? null : (v) => _updateDiscovery(uid: v),
                    showDivider: false,
                  ),
                ],
              ),
            ],
          );
        },
      );
}

class _PrivacySwitchCell extends StatelessWidget {
  const _PrivacySwitchCell({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.showDivider = true,
  });

  final String title;
  final String subtitle;
  final bool value;
  final bool showDivider;
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
                Text(
                  subtitle,
                  style: TextStyle(
                    color: AppTokens.textSecondary(dark: dark),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
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
