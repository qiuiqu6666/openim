import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import '../../../../core/controller/im_controller.dart';
import '../../../../routes/swipe_back/app_page_route.dart';
import '../../../mine/settings/openim_profile_service.dart';
import '../../../mine/settings/settings_service.dart';
import '../data/desktop_devices.dart';
import '../desktop_login_devices_page.dart';

class DesktopLoginBanner extends StatefulWidget {
  const DesktopLoginBanner({super.key, this.active = true, this.service});
  final bool active;
  final SettingsService? service;
  @override
  State<DesktopLoginBanner> createState() => _DesktopLoginBannerState();
}

class _DesktopLoginBannerState extends State<DesktopLoginBanner>
    with WidgetsBindingObserver {
  List<DesktopDevice> _devices = [];
  (String?, String?)? _owner;
  bool _loading = false, _foreground = true;
  Timer? _timer;
  SettingsService? get _service =>
      widget.service ??
      (Get.isRegistered<IMController>()
          ? OpenIMProfileService(Get.find<IMController>())
          : null);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void didUpdateWidget(covariant DesktopLoginBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _refresh();
  }

  Future<void> _refresh() async {
    if (!widget.active || !_foreground || _loading) return;
    final owner = (DataSp.userID, DataSp.chatToken);
    if (owner != _owner) {
      setState(() {
        _owner = owner;
        _devices = [];
      });
    }
    final service = _service;
    if (owner.$1?.isNotEmpty != true ||
        owner.$2?.isNotEmpty != true ||
        service == null) {
      return;
    }
    _loading = true;
    try {
      final rows = await service.getLoginRecords();
      if (mounted && owner == (DataSp.userID, DataSp.chatToken)) {
        setState(
            () => _devices = onlineDesktopDevices(rows, DataSp.getDeviceID()));
      }
    } catch (_) {
      /* Keep last known state; a failed request is not sign-out. */
    } finally {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_devices.isEmpty || _owner != (DataSp.userID, DataSp.chatToken)) {
      return const SizedBox.shrink();
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    final platforms = _devices.map((d) => d.platform).toSet();
    final text = '已在${platforms.first}${platforms.length > 1 ? '等' : ''}登录';
    return Semantics(
        button: true,
        label: text,
        child: Material(
          color: dark ? AppTokens.surfaceAltDark : AppTokens.surfaceAltLight,
          child: InkWell(
            onTap: () async {
              final service = _service;
              if (service == null) return;
              await Navigator.of(context).push<void>(AppMaterialPageRoute(
                  builder: (_) => DesktopLoginDevicesPage(service: service)));
              if (mounted) await _refresh();
            },
            child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(children: [
                  Icon(Icons.desktop_windows_outlined,
                      size: 20, color: AppTokens.textSecondary(dark: dark)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppTokens.textPrimary(dark: dark)))),
                  Icon(Icons.chevron_right_rounded,
                      size: 22, color: AppTokens.textSecondary(dark: dark)),
                ])),
          ),
        ));
  }
}
