import '../../../../services/platform_config_service.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../settings_navigation.dart';
import '../widgets/settings_widgets.dart';
import 'legal_document_page.dart';

class AboutUsPage extends StatefulWidget {
  const AboutUsPage({
    super.key,
    this.website = '',
    this.email = '',
    this.embedded = false,
  });

  /// Optional overrides; otherwise contacts come from the public platform API.
  final String website;
  final String email;
  final bool embedded;

  @override
  State<AboutUsPage> createState() => _AboutUsPageState();
}

class _AboutUsPageState extends State<AboutUsPage> {
  String _version = '';
  PlatformConfig? _platform;
  bool _platformLoading = true;
  bool _platformFailed = false;

  Future<void> _loadPlatform() async {
    try {
      final config = await PlatformConfigService.fetch();
      if (mounted) setState(() => _platform = config);
    } catch (_) {
      if (mounted) setState(() => _platformFailed = true);
    } finally {
      if (mounted) setState(() => _platformLoading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPlatform();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadVersion());
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = info.version);
    } catch (_) {
      if (mounted) setState(() => _version = '');
    }
  }

  String _notConfigured(BuildContext context) => settingsText(context,
      zh: _platformLoading
          ? '获取中'
          : _platformFailed
              ? '获取失败'
              : '未配置',
      en: _platformLoading
          ? 'Loading'
          : _platformFailed
              ? 'Load failed'
              : 'Not configured');

  Future<void> _openExternal(String value) async {
    final raw = value.trim();
    if (raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null) {
      if (mounted) {
        showSettingsMessage(
          context,
          settingsText(context, zh: '链接无效', en: 'Invalid link'),
        );
      }
      return;
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        showSettingsMessage(
          context,
          settingsText(context, zh: '无法打开链接', en: 'Unable to open link'),
        );
      }
    } catch (_) {
      if (!mounted) return;
      showSettingsMessage(
        context,
        settingsText(context, zh: '无法打开链接', en: 'Unable to open link'),
      );
    }
  }

  Future<void> _sendEmail(String email) async {
    final address = email.trim();
    if (address.isEmpty) return;
    final uri = Uri(
      scheme: 'mailto',
      path: address,
      queryParameters: {
        'subject':
            settingsText(context, zh: '99chat 反馈', en: '99chat Feedback'),
      },
    );
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        showSettingsMessage(
          context,
          settingsText(context, zh: '无法打开邮件应用', en: 'Unable to open email app'),
        );
      }
    } catch (_) {
      if (!mounted) return;
      showSettingsMessage(
        context,
        settingsText(context, zh: '无法打开邮件应用', en: 'Unable to open email app'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final primary = AppTokens.textPrimary(dark: dark);
    final secondary = AppTokens.textSecondary(dark: dark);
    final surface = AppTokens.surface(dark: dark);
    final website = widget.website.trim().isNotEmpty
        ? widget.website.trim()
        : _platform?.officialURL ?? '';
    final email = widget.email.trim().isNotEmpty
        ? widget.email.trim()
        : _platform?.email ?? '';

    return SettingsScaffold(
      embedded: widget.embedded,
      title: settingsText(context, zh: '关于我们', en: 'About Us'),
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(AppTokens.rLg),
          ),
          padding: const EdgeInsets.fromLTRB(16, 34, 16, 34),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Image.asset(
                  'assets/images/im_new_logo_99chat.jpg',
                  package: 'openim_common',
                  width: 96,
                  height: 96,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '99chat',
                style: TextStyle(
                  color: primary,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _version.isEmpty
                    ? settingsText(context, zh: '专业版', en: 'Pro')
                    : settingsText(
                        context,
                        zh: '专业版 v$_version',
                        en: 'Pro v$_version',
                      ),
                style: TextStyle(color: secondary, fontSize: 15),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SettingsGroup(
          margin: EdgeInsets.zero,
          children: [
            SettingsCell(
              title: settingsText(context, zh: '服务条款', en: 'Terms of Service'),
              onTap: () => openSettingsPage(
                context,
                const LegalDocumentPage(kind: LegalDocumentKind.terms),
              ),
            ),
            SettingsCell(
              title: settingsText(context, zh: '隐私政策', en: 'Privacy Policy'),
              showDivider: false,
              onTap: () => openSettingsPage(
                context,
                const LegalDocumentPage(kind: LegalDocumentKind.privacy),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SettingsGroup(
          margin: EdgeInsets.zero,
          children: [
            SettingsCell(
              title: settingsText(context, zh: '官方网站', en: 'Official Website'),
              value: website.isEmpty ? _notConfigured(context) : website,
              enabled: website.isNotEmpty,
              onTap: website.isEmpty ? null : () => _openExternal(website),
            ),
            SettingsCell(
              title: settingsText(context, zh: '邮件反馈', en: 'Email Feedback'),
              value: email.isEmpty ? _notConfigured(context) : email,
              enabled: email.isNotEmpty,
              showDivider: false,
              onTap: email.isEmpty ? null : () => _sendEmail(email),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 42, 16, 0),
          child: Center(
            child: Text(
              '© 2026 99chat',
              style: TextStyle(color: secondary, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }
}
