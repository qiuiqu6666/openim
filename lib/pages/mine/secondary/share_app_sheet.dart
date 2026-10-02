import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../routes/app_navigator.dart';
import '../../contacts/select_contacts/select_contacts_logic.dart';
import '../settings/widgets/settings_widgets.dart';

class ShareAppSheet extends StatefulWidget {
  const ShareAppSheet({
    super.key,
    this.website = '',
  });

  final String website;

  static Future<void> show(
    BuildContext context, {
    String website = '',
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        isDismissible: true,
        enableDrag: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.55),
        builder: (_) => ShareAppSheet(website: website),
      );

  @override
  State<ShareAppSheet> createState() => _ShareAppSheetState();
}

class _ShareAppSheetState extends State<ShareAppSheet> {
  String get _website => widget.website.trim();

  String _shareText(BuildContext context) => settingsText(
        context,
        zh: '我正在使用 99chat，快来一起聊天吧！下载链接：$_website',
        en: 'I am using 99chat. Join me and start chatting: $_website',
      );

  void _toast(String text) => IMViews.showToast(text);

  bool _ensureConfigured(BuildContext context) {
    if (_website.isNotEmpty) return true;
    _toast(settingsText(context, zh: '未配置', en: 'Not configured'));
    return false;
  }

  Future<void> _copyLink(BuildContext context) async {
    if (!_ensureConfigured(context)) return;
    try {
      await Clipboard.setData(ClipboardData(text: _shareText(context)));
      _toast(settingsText(context, zh: '链接已复制', en: 'Link copied'));
    } catch (_) {
      _toast(settingsText(context, zh: '复制失败，请重试', en: 'Copy failed. Try again.'));
    }
  }

  Future<void> _openWebsite(BuildContext context) async {
    if (!_ensureConfigured(context)) return;
    try {
      final ok = await launchUrl(
        Uri.parse(_website),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) {
        _toast(settingsText(context, zh: '无法打开', en: 'Unable to open'));
      }
    } catch (_) {
      if (mounted) {
        _toast(settingsText(context, zh: '无法打开', en: 'Unable to open'));
      }
    }
  }

  Future<void> _shareToFriend(BuildContext context) async {
    if (!_ensureConfigured(context)) return;
    final text = _shareText(context);
    final sharedText = settingsText(context, zh: '已分享', en: 'Shared');
    final failedText = settingsText(context, zh: '分享失败', en: 'Share failed');
    Navigator.of(context).pop();
    final result = await AppNavigator.startSelectContacts(
      action: SelAction.forward,
      ex: text,
    );
    if (result == null) return;

    try {
      final checkedList = result['checkedList'];
      if (checkedList is! Iterable) return;
      var sent = 0;
      for (final info in checkedList) {
        final userID = IMUtils.convertCheckedToUserID(info);
        final groupID = IMUtils.convertCheckedToGroupID(info);
        final message =
            await OpenIM.iMManager.messageManager.createTextMessage(text: text);
        await OpenIM.iMManager.messageManager.sendMessage(
          message: message,
          userID: userID,
          groupID: groupID,
          offlinePushInfo: Config.offlinePushInfo,
        );
        sent++;
      }
      if (sent > 0) _toast(sharedText);
    } catch (_) {
      _toast(failedText);
    }
  }

  Future<void> _systemShare(BuildContext context) async {
    if (!_ensureConfigured(context)) return;
    final text = _shareText(context);
    final unsupportedText = settingsText(
      context,
      zh: '当前设备暂不支持系统分享',
      en: 'System sharing is not supported on this device',
    );
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    Navigator.of(context).pop();
    try {
      await Share.share(
        text,
        sharePositionOrigin: origin,
      );
    } catch (_) {
      _toast(unsupportedText);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final bg = AppTokens.surface(dark: dark);
    final text = AppTokens.textPrimary(dark: dark);
    final subText = AppTokens.textSecondary(dark: dark);
    final line = AppTokens.border(dark: dark);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final shareUrlLabel = _website.isEmpty
        ? settingsText(context, zh: '未配置', en: 'Not configured')
        : _website;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            behavior: HitTestBehavior.translucent,
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              decoration: BoxDecoration(
                color: bg,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 12 + bottomInset),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: line,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        settingsText(context, zh: '分享应用', en: 'Share App'),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: text,
                        ),
                      ),
                      const SizedBox(height: 18),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _copyLink(context),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: dark
                                ? const Color(0xFF23262D)
                                : const Color(0xFFF7F8FA),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: line),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.asset(
                                  'assets/images/share_app_logo_99chat.png',
                                  package: 'openim_common',
                                  width: 52,
                                  height: 52,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Image.asset(
                                    'assets/images/platform_99chat.webp',
                                    package: 'openim_common',
                                    width: 52,
                                    height: 52,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '99chat',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.w700,
                                        color: text,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      settingsText(
                                        context,
                                        zh: '安全、便捷的即时通讯',
                                        en: 'Secure and convenient messaging',
                                      ),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: subText,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: _website.isEmpty
                                          ? null
                                          : () => _openWebsite(context),
                                      child: Text(
                                        shareUrlLabel,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppTokens.accent,
                                          height: 1.3,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 88,
                        child: Row(
                          children: [
                            _ShareActionButton(
                              icon: Icons.person_add_alt_1_rounded,
                              label: settingsText(
                                context,
                                zh: '发送给朋友',
                                en: 'Send to Friend',
                              ),
                              dark: dark,
                              onTap: () => _shareToFriend(context),
                            ),
                            _ShareActionButton(
                              icon: Icons.link_rounded,
                              label: settingsText(
                                context,
                                zh: '复制链接',
                                en: 'Copy Link',
                              ),
                              dark: dark,
                              onTap: () => _copyLink(context),
                            ),
                            _ShareActionButton(
                              icon: Icons.more_horiz_rounded,
                              label: settingsText(
                                context,
                                zh: '更多',
                                en: 'More',
                              ),
                              dark: dark,
                              onTap: () => _systemShare(context),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ShareActionButton extends StatelessWidget {
  const _ShareActionButton({
    required this.icon,
    required this.label,
    required this.dark,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool dark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconBg = dark ? const Color(0xFF2A2D33) : const Color(0xFFF0F2F5);
    final text = AppTokens.textPrimary(dark: dark);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 24, color: AppTokens.accent),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
