import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../../mine/settings/settings_service.dart';
import 'data/desktop_devices.dart';
import 'widgets/desktop_authorization_layout.dart';

class DesktopLoginDevicesPage extends StatefulWidget {
  const DesktopLoginDevicesPage({super.key, required this.service});
  final SettingsService service;
  @override
  State<DesktopLoginDevicesPage> createState() =>
      _DesktopLoginDevicesPageState();
}

class _DesktopLoginDevicesPageState extends State<DesktopLoginDevicesPage> {
  late final _owner = (DataSp.userID, DataSp.chatToken);
  List<DesktopDevice> _devices = [];
  String? _selected, _error;
  bool _loading = true, _busy = false;
  bool get _current =>
      mounted &&
      _owner.$1?.isNotEmpty == true &&
      _owner.$2?.isNotEmpty == true &&
      _owner == (DataSp.userID, DataSp.chatToken);
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_current) {
      setState(() {
        _loading = false;
        _error = '登录状态已变化，请重新登录';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await widget.service.getLoginRecords();
      if (!_current) return;
      setState(() {
        _devices = onlineDesktopDevices(rows, DataSp.getDeviceID());
        if (!_devices.any((d) => d.id == _selected)) {
          _selected = _devices.firstOrNull?.id;
        }
      });
    } catch (_) {
      if (_current) setState(() => _error = '无法获取设备状态，请检查网络后重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async {
    final id = _selected;
    if (!_current || _busy || id == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Existing API removes this device only, never all devices/user platforms.
      await widget.service.removeDevice(id);
      if (_current) await _load();
    } catch (_) {
      if (_current) setState(() => _error = '退出未完成，请重试核对设备状态');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _devices.where((d) => d.id == _selected).firstOrNull;
    return DesktopAuthorizationLayout(
      title: _error ??
          (selected == null ? '暂无在线的桌面设备' : '${selected.platform}已登录'),
      loggedIn: true,
      loading: _loading,
      busy: _busy,
      onClose: () => Navigator.of(context).pop(),
      action: _error != null
          ? '重试'
          : selected == null
              ? '完成'
              : '退出该设备',
      onAction: _error != null
          ? _load
          : selected == null
              ? () => Navigator.of(context).pop()
              : _signOut,
      detail: _devices.length <= 1
          ? Text(selected?.name ?? '', textAlign: TextAlign.center)
          : Column(children: [
              for (final device in _devices)
                ListTile(
                  title: Text(device.name),
                  subtitle: Text(device.platform),
                  selected: device.id == _selected,
                  trailing: device.id == _selected
                      ? const Icon(Icons.check, color: AppTokens.accent)
                      : null,
                  onTap: _busy
                      ? null
                      : () => setState(() => _selected = device.id),
                )
            ]),
    );
  }
}
