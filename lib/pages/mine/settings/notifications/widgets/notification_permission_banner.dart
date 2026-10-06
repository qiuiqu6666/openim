import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../widgets/settings_widgets.dart';
import '../notification_permission_gateway.dart';

class NotificationPermissionBanner extends StatefulWidget {
  const NotificationPermissionBanner({
    super.key,
    required this.gateway,
  });

  final NotificationPermissionGateway gateway;

  @override
  State<NotificationPermissionBanner> createState() =>
      _NotificationPermissionBannerState();
}

class _NotificationPermissionBannerState
    extends State<NotificationPermissionBanner> with WidgetsBindingObserver {
  bool _loading = true;
  bool _granted = true;
  bool _busy = false;
  String? _error;
  int _refreshVersion = 0;
  int _actionVersion = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void didUpdateWidget(NotificationPermissionBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.gateway, oldWidget.gateway)) {
      _actionVersion++;
      _busy = false;
      _loading = true;
      _granted = true;
      _error = null;
      _refresh();
    }
  }

  @override
  void dispose() {
    _refreshVersion++;
    _actionVersion++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final version = ++_refreshVersion;
    try {
      final status = await widget.gateway.status();
      if (!mounted || version != _refreshVersion) return;
      setState(() {
        _granted = status == null || status.isGranted || status.isLimited;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted || version != _refreshVersion) return;
      setState(() {
        _loading = false;
        _error = settingsText(context,
            zh: '无法读取系统通知权限，请重试或前往系统设置。',
            en: 'Unable to check notification permission. Retry or open system settings.');
      });
    }
  }

  Future<void> _runAction({required bool request}) async {
    if (_busy) return;
    final version = ++_actionVersion;
    final gateway = widget.gateway;
    _refreshVersion++;
    setState(() => _busy = true);
    try {
      if (request) {
        final status = await gateway.request();
        if (!_currentAction(version)) return;
        if (status.isPermanentlyDenied || status.isRestricted) {
          final opened = await gateway.openSettings();
          if (!_currentAction(version)) return;
          if (!opened) throw StateError('Unable to open system settings');
        }
      } else {
        final opened = await gateway.openSettings();
        if (!_currentAction(version)) return;
        if (!opened) throw StateError('Unable to open system settings');
      }
      if (_currentAction(version)) await _refresh();
    } catch (_) {
      if (!mounted || !_currentAction(version)) return;
      _refreshVersion++;
      setState(() => _error = settingsText(context,
          zh: '无法开启系统通知权限，请稍后重试或手动前往系统设置。',
          en: 'Unable to enable notifications. Retry or open system settings manually.'));
    } finally {
      if (_currentAction(version)) setState(() => _busy = false);
    }
  }

  bool _currentAction(int version) => mounted && version == _actionVersion;

  @override
  Widget build(BuildContext context) {
    if (_loading || (_granted && _error == null)) {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.s4),
      child: Material(
        color: colors.tertiaryContainer,
        borderRadius: BorderRadius.circular(AppTokens.rMd),
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.s5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _error ??
                    settingsText(context,
                        zh: '系统通知权限未开启，消息横幅可能无法显示。',
                        en: 'System notification permission is off. Message banners may not appear.'),
                key: const ValueKey('notification-permission-message'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onTertiaryContainer,
                    ),
              ),
              const SizedBox(height: AppTokens.s3),
              Wrap(
                spacing: AppTokens.s3,
                runSpacing: AppTokens.s2,
                children: [
                  TextButton(
                    key: const ValueKey('notification-permission-enable'),
                    onPressed: _busy ? null : () => _runAction(request: true),
                    child: Text(settingsText(context,
                        zh: _busy ? '处理中' : '立即开启',
                        en: _busy ? 'Working…' : 'Enable now')),
                  ),
                  TextButton(
                    key: const ValueKey('notification-permission-settings'),
                    onPressed: _busy ? null : () => _runAction(request: false),
                    child: Text(settingsText(context,
                        zh: '前往系统设置', en: 'Open system settings')),
                  ),
                  if (_error != null)
                    TextButton(
                      key: const ValueKey('notification-permission-retry'),
                      onPressed: _busy ? null : _refresh,
                      child: Text(settingsText(context, zh: '重试', en: 'Retry')),
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
