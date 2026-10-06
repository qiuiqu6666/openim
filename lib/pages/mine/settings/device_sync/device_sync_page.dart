import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/device_sync/device_sync_runtime.dart';
import '../widgets/settings_widgets.dart';

class DeviceSyncPage extends StatefulWidget {
  const DeviceSyncPage({super.key, this.runtime, this.onOpenSystemSettings});

  final DeviceSyncRuntime? runtime;
  final Future<bool> Function()? onOpenSystemSettings;

  @override
  State<DeviceSyncPage> createState() => _DeviceSyncPageState();
}

class _DeviceSyncPageState extends State<DeviceSyncPage> {
  late final DeviceSyncRuntime _runtime;
  late final String _accountID;
  bool _saving = false;
  bool _openingSettings = false;

  @override
  void initState() {
    super.initState();
    _runtime = widget.runtime ?? DeviceSyncRuntime.instance;
    final loadedAccount = _runtime.preferences.value.accountID;
    _accountID =
        loadedAccount.isNotEmpty ? loadedAccount : DataSp.userID?.trim() ?? '';
  }

  bool get _current =>
      _accountID.isNotEmpty &&
      _runtime.preferences.value.accountID == _accountID;

  bool get _waitingForAccount =>
      _accountID.isNotEmpty &&
      _runtime.preferences.value.accountID.isEmpty &&
      DataSp.userID == _accountID;

  String _text(String zh, String en) => settingsText(context, zh: zh, en: en);

  Future<void> _change({
    bool? photos,
    bool? videos,
    bool? location,
    bool? wifiOnly,
  }) async {
    if (_saving || !_current) return;
    setState(() => _saving = true);
    try {
      if (videos == true) {
        final accepted = await showSettingsConfirm(
          context,
          title: _text('开启视频上传', 'Enable Video Uploads'),
          message: _text(
            '开启后，系统允许访问的相册视频也会自动上传至当前账号的云存储。'
                '\n\n上传使用本页的网络设置，你可以随时关闭。',
            'Accessible album videos will also upload automatically to this '
                'account’s cloud storage.'
                '\n\nUploads follow the network preference on this page. '
                'You can turn this off at any time.',
          ),
          confirmText: _text('开启视频上传', 'Enable Video Uploads'),
        );
        if (!mounted || !_current || !accepted) return;
      }
      if (!mounted || !_current) return;
      await _runtime.setPreferences(
        photos: photos,
        // The optional video scope belongs to the album switch.
        videos: photos == false ? false : videos,
        location: location,
        wifiOnly: wifiOnly,
      );
    } catch (error) {
      if (mounted && _current) {
        showSettingsError(context, error,
            _text('同步设置保存失败，请重试', 'Could not save sync settings. Try again.'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openSystemSettings() async {
    if (_openingSettings || !_current) return;
    setState(() => _openingSettings = true);
    try {
      final opened = await (widget.onOpenSystemSettings ?? openAppSettings)();
      if (mounted && _current && !opened) {
        showSettingsMessage(
            context,
            _text('请在手机系统设置中调整应用权限',
                'Adjust app permissions in system settings.'));
      }
    } catch (_) {
      if (mounted && _current) {
        showSettingsMessage(
            context,
            _text('请在手机系统设置中调整应用权限',
                'Adjust app permissions in system settings.'));
      }
    } finally {
      if (mounted) setState(() => _openingSettings = false);
    }
  }

  String _statusText(DeviceSyncStatus status) => switch (status) {
        DeviceSyncStatus.inactive => _text('未启用', 'Off'),
        DeviceSyncStatus.waitingPermission =>
          _text('等待权限', 'Permission needed'),
        DeviceSyncStatus.idle => _text('等待同步', 'Ready'),
        DeviceSyncStatus.scanning => _text('检查相册', 'Checking album'),
        DeviceSyncStatus.uploading => _text('正在上传', 'Uploading'),
        DeviceSyncStatus.paused => _text('已暂停', 'Paused'),
        DeviceSyncStatus.retrying => _text('稍后重试', 'Retrying later'),
      };

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<DeviceSyncPreferences>(
        valueListenable: _runtime.preferences,
        builder: (context, preferences, _) =>
            ValueListenableBuilder<DeviceSyncStatus>(
          valueListenable: _runtime.status,
          builder: (context, status, _) {
            final enabled = _current && !_saving;
            return SettingsScaffold(
              title: _text('相册与定位同步', 'Photo and Location Sync'),
              children: [
                SettingsSectionText(_waitingForAccount
                    ? _text('正在读取同步设置…', 'Loading sync settings…')
                    : _current
                        ? _text('上传内容归属当前登录账号，可随时分别关闭。',
                            'Uploaded content belongs to this account. Each option can be turned off at any time.')
                        : _text('登录账号已变化，请重新打开此页面。',
                            'The signed-in account has changed. Reopen this page.')),
                SettingsGroup(children: [
                  SettingsSwitchCell(
                    key: const ValueKey('device-sync-photos'),
                    title: _text('照片自动上传', 'Upload Photos'),
                    subtitle: _text('仅上传本地可访问的照片，跳过仅存于 iCloud 的照片。',
                        'Upload accessible local photos; skip photos stored only in iCloud.'),
                    value: preferences.photos,
                    enabled: enabled,
                    onChanged: (value) => _change(photos: value),
                  ),
                  SettingsSwitchCell(
                    key: const ValueKey('device-sync-videos'),
                    title: _text('包含视频', 'Include Videos'),
                    subtitle: _text('上传系统允许访问的相册视频，可随时关闭。',
                        'Upload accessible album videos; turn this off at any time.'),
                    value: preferences.photos && preferences.videos,
                    enabled: enabled && preferences.photos,
                    onChanged: (value) => _change(videos: value),
                  ),
                  SettingsSwitchCell(
                    key: const ValueKey('device-sync-location'),
                    title: _text('登录时定位', 'Location at Login'),
                    subtitle: _text('每次登录获取一次新定位，10 秒内无结果则本次不上传。',
                        'Request a fresh location once per login; skip this login if there is no result within 10 seconds.'),
                    value: preferences.location,
                    enabled: enabled,
                    showDivider: false,
                    onChanged: (value) => _change(location: value),
                  ),
                ]),
                SettingsGroup(children: [
                  SettingsSwitchCell(
                    key: const ValueKey('device-sync-wifi-only'),
                    title: _text('仅 Wi-Fi 上传相册', 'Album Uploads on Wi-Fi'),
                    subtitle: _text('关闭后也会使用蜂窝网络，可能消耗流量。',
                        'When off, uploads may use cellular data.'),
                    value: preferences.wifiOnly,
                    enabled: enabled,
                    showDivider: false,
                    onChanged: (value) => _change(wifiOnly: value),
                  ),
                ]),
                SettingsGroup(children: [
                  SettingsCell(
                    key: const ValueKey('device-sync-status'),
                    title: _text('同步状态', 'Sync Status'),
                    subtitle:
                        _current ? _statusText(status) : _text('已暂停', 'Paused'),
                    showArrow: false,
                  ),
                  SettingsCell(
                    key: const ValueKey('device-sync-system-settings'),
                    title: _text('相册与定位权限', 'Photo and Location Access'),
                    subtitle: _text('前往系统设置调整允许访问的范围。',
                        'Adjust accessible photos and location access in system settings.'),
                    enabled: _current && !_openingSettings,
                    showDivider: false,
                    onTap: _openSystemSettings,
                  ),
                ]),
                SettingsSectionText(_text(
                  '照片和视频直接上传至云存储。关闭开关会停止相应的后续同步；'
                      '再次开启时会继续检查未完成的上传。',
                  'Photos and videos upload directly to cloud storage. '
                      'Turning an option off stops further sync for that scope. '
                      'When enabled again, incomplete uploads can resume.',
                )),
              ],
            );
          },
        ),
      );
}
