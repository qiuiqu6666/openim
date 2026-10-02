import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../settings_service.dart';
import '../widgets/settings_widgets.dart';

class LoginDevicesPage extends StatefulWidget {
  const LoginDevicesPage(
      {super.key, this.service = const StubSettingsService()});
  final SettingsService service;
  @override
  State<LoginDevicesPage> createState() => _LoginDevicesPageState();
}

class _LoginDevicesPageState extends State<LoginDevicesPage>
    with WidgetsBindingObserver {
  bool _mutating = false;
  bool _removingOthers = false;
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;
  bool _failed = false;
  Object? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_loading && !_mutating) _load();
  }

  Future<void> _manage(Future<void> Function() action,
      {bool remove = false, bool others = false}) async {
    if (_mutating || _loading) return;
    setState(() => _mutating = true);
    try {
      if (remove) {
        final confirmed = await showSettingsConfirm(context,
            title: settingsText(context, zh: '移除设备', en: 'Remove devices'),
            message: settingsText(context,
                zh: '移除后，对应设备将退出登录。是否继续？',
                en: 'The selected devices will be signed out. Continue?'),
            confirmText: settingsText(context, zh: '移除', en: 'Remove'),
            destructive: true);
        if (!confirmed || !mounted) return;
      }
      if (others && mounted) setState(() => _removingOthers = true);
      await action();
      if (mounted) await _load();
    } catch (error) {
      if (!mounted) return;
      final code = error is (int, String) ? error.$1 : null;
      showSettingsError(
          context,
          error,
          settingsText(context,
              zh: code == 20043
                  ? '当前登录未绑定设备，请重新登录后再试'
                  : code == 20042
                      ? '设备记录已不存在，请刷新列表'
                      : '操作失败，请稍后重试',
              en: code == 20043
                  ? 'Sign in again to bind this device.'
                  : code == 20042
                      ? 'Device no longer exists. Refresh the list.'
                      : 'Operation failed. Please retry.'));
      if (code == 20042) await _load();
    } finally {
      if (mounted) {
        setState(() {
          _mutating = false;
          _removingOthers = false;
        });
      }
    }
  }

  Widget _badge(String text, Color color, TextStyle style,
          {bool online = false}) =>
      Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.s3, vertical: AppTokens.s2),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppTokens.rPill)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (online) ...[
              Icon(Icons.circle, size: AppTokens.s3, color: color),
              const SizedBox(width: AppTokens.s2),
            ],
            Text(text, style: style.copyWith(color: color)),
          ]));

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final records = await widget.service.getLoginRecords();
      // Legacy login history without a UUID is not a managed device session.
      final devices = records.where((record) {
        final id = record['deviceID'];
        return id is String && id.isNotEmpty;
      }).toList();
      if (mounted) setState(() => _records = devices);
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _error = error;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _time(dynamic value) {
    if (value is! num || value <= 0) return '';
    return DateTime.fromMillisecondsSinceEpoch(value.toInt())
        .toLocal()
        .toString()
        .split('.')
        .first
        .substring(0, 16);
  }

  Widget _metadata(String label, String value, TextStyle style, IconData icon) {
    final painter = TextPainter(
        text: TextSpan(
            text: settingsText(context, zh: '最近登录', en: 'Last login'),
            style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context))
      ..layout();
    final labelWidth = painter.width.ceilToDouble() + AppTokens.s2;
    painter.dispose();
    return Padding(
        padding: const EdgeInsets.only(top: AppTokens.s4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: AppTokens.chevronSize, color: style.color),
          const SizedBox(width: AppTokens.s5),
          Expanded(child: LayoutBuilder(builder: (context, constraints) {
            final labelText = Text(label, style: style, softWrap: false);
            final valueText = Text(value.isEmpty ? '—' : value,
                style: style.copyWith(
                    color:
                        AppTokens.textPrimary(dark: settingsIsDark(context))));
            if (constraints.maxWidth - labelWidth - AppTokens.s3 <
                AppTokens.listItemHeight *
                    2 *
                    MediaQuery.textScalerOf(context).scale(1)) {
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [labelText, valueText]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: labelWidth, child: labelText),
              const SizedBox(width: AppTokens.s3),
              Expanded(child: valueText),
            ]);
          })),
        ]));
  }

  Widget _deviceRow(Map<String, dynamic> record, {required bool divider}) {
    final platform = record['platform']?.toString().trim() ?? '';
    final name = record['deviceName']?.toString().trim() ?? '';
    final version = record['version']?.toString().trim() ?? '';
    final ip = record['ip']?.toString().trim() ?? '';
    final time = _time(record['loginTime']);
    final id = record['deviceID']?.toString() ?? '';
    final isCurrent = id.isNotEmpty && id == DataSp.getDeviceID();
    final dark = settingsIsDark(context);
    final icon = switch (platform.toLowerCase()) {
      'android' => Icons.phone_android_rounded,
      'ios' => Icons.phone_iphone_rounded,
      'web' => Icons.language_rounded,
      'windows' || 'macos' || 'linux' => Icons.laptop_rounded,
      _ => Icons.devices_other_rounded,
    };
    final detail = TextStyle(
        fontSize: AppTokens.captionFontSize,
        height: 1.5,
        color: AppTokens.textSecondary(dark: dark));
    return Container(
      margin: EdgeInsets.only(bottom: divider ? AppTokens.s4 : 0),
      padding: const EdgeInsets.all(AppTokens.s5),
      decoration: BoxDecoration(
          color: AppTokens.surface(dark: dark),
          borderRadius: BorderRadius.circular(AppTokens.s6),
          border: Border.all(
              color: AppTokens.border(dark: dark).withValues(alpha: 0.6))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              width: AppTokens.listItemHeight,
              height: AppTokens.listItemHeight,
              decoration: BoxDecoration(
                  color: AppTokens.accent.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(AppTokens.s5)),
              child: Icon(icon, size: AppTokens.s8, color: AppTokens.accent)),
          const SizedBox(width: AppTokens.s4),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                      child: Text(
                          name.isNotEmpty
                              ? name
                              : platform.isNotEmpty
                                  ? platform
                                  : settingsText(context,
                                      zh: '未知设备', en: 'Unknown device'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: AppTokens.listTitleFontSize,
                              fontWeight: FontWeight.w600,
                              color: AppTokens.textPrimary(dark: dark)))),
                  const SizedBox(width: AppTokens.s3),
                  if (!isCurrent && id.isNotEmpty)
                    TextButton(
                        style: TextButton.styleFrom(
                            foregroundColor:
                                Theme.of(context).colorScheme.error,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(AppTokens.s8 + AppTokens.s4,
                                AppTokens.s8 + AppTokens.s4)),
                        onPressed: _mutating || _loading
                            ? null
                            : () => _manage(
                                () => widget.service.removeDevice(id),
                                remove: true),
                        child: Text(
                            settingsText(context, zh: '移除', en: 'Remove'))),
                ]),
                Wrap(
                    spacing: AppTokens.s2,
                    runSpacing: AppTokens.s2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (isCurrent)
                        _badge(
                            settingsText(context, zh: '本机', en: 'This device'),
                            AppTokens.accent,
                            detail),
                      if (record['online'] == true)
                        _badge(settingsText(context, zh: '在线', en: 'Online'),
                            AppTokens.success, detail,
                            online: true),
                      if (record['trusted'] == true)
                        _badge(settingsText(context, zh: '已信任', en: 'Trusted'),
                            AppTokens.textSecondary(dark: dark), detail),
                    ]),
              ])),
        ]),
        const SizedBox(height: AppTokens.s5),
        Divider(height: 1, thickness: 0.5, color: AppTokens.border(dark: dark)),
        _metadata(settingsText(context, zh: '最近登录', en: 'Last login'), time,
            detail, Icons.access_time_rounded),
        if (version.isNotEmpty)
          _metadata(settingsText(context, zh: '应用版本', en: 'Version'), version,
              detail, Icons.inventory_2_outlined),
        _metadata(settingsText(context, zh: '登录 IP', en: 'Login IP'), ip,
            detail, Icons.location_on_outlined),
        if ((record['ipLocation']?.toString().trim() ?? '').isNotEmpty)
          _metadata(
              settingsText(context, zh: '登录地区', en: 'Location'),
              record['ipLocation'].toString().trim(),
              detail,
              Icons.language_rounded),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => SettingsScaffold(
        title: settingsText(context, zh: '登录设备', en: 'Login Devices'),
        actions: [
          IconButton(
              onPressed: _loading || _mutating ? null : _load,
              tooltip: settingsText(context, zh: '刷新', en: 'Refresh'),
              icon: const Icon(Icons.refresh_rounded))
        ],
        bottom: SafeArea(
            top: false,
            child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.s5, vertical: AppTokens.s4),
                child: SizedBox(
                    width: double.infinity,
                    height: SettingsResponsive.controlHeight(context),
                    child: SettingsDestructiveButton(
                      text: settingsText(context,
                          zh: '移除其他设备', en: 'Remove other devices'),
                      loadingText:
                          settingsText(context, zh: '正在移除…', en: 'Removing…'),
                      loading: _removingOthers,
                      onPressed: _loading ||
                              _mutating ||
                              !_records.any((r) =>
                                  (r['deviceID']?.toString() ?? '')
                                      .isNotEmpty &&
                                  r['deviceID'] != DataSp.getDeviceID())
                          ? null
                          : () => _manage(widget.service.removeOtherDevices,
                              remove: true, others: true),
                    )))),
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_failed) ...[
            Text(
                settingsErrorMessage(context, _error!,
                    fallback: settingsText(context,
                        zh: '登录设备加载失败，请重试',
                        en: 'Could not load devices. Please retry.')),
                style: TextStyle(color: settingsSecondaryTextColor(context))),
            SettingsCell(
                title: settingsText(context,
                    zh: '加载失败，点击重试', en: 'Could not load. Tap to retry'),
                onTap: _load),
          ] else if (_records.isEmpty)
            SettingsEmptyState(
                icon: Icons.devices_other_rounded,
                title:
                    settingsText(context, zh: '暂无登录设备', en: 'No login records'),
                imageWidth: 160)
          else
            Column(children: [
              for (var i = 0; i < _records.length; i++)
                _deviceRow(_records[i], divider: i < _records.length - 1)
            ]),
        ],
      );
}
