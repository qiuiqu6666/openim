import 'package:openim_common/localization.dart';
import 'widgets/desktop_login_code_input.dart';
import 'data/qr_login_api.dart';
import 'widgets/desktop_login_device_details.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'data/desktop_authorization_service.dart';
import 'widgets/desktop_authorization_layout.dart';

class DesktopLoginConfirmPage extends StatefulWidget {
  const DesktopLoginConfirmPage(
      {super.key, required this.requestId, this.service});
  final String requestId;
  final DesktopAuthorizationService? service;
  @override
  State<DesktopLoginConfirmPage> createState() =>
      _DesktopLoginConfirmPageState();
}

class _DesktopLoginConfirmPageState extends State<DesktopLoginConfirmPage> {
  late final _owner = (DataSp.userID, DataSp.chatToken);
  late final _service = widget.service ?? QrLoginApi();
  final _code = TextEditingController();
  DesktopAuthorization? _value;
  String? _error;
  bool _loading = true, _busy = false;
  Timer? _timer;
  bool get _current =>
      mounted &&
      _owner.$1?.isNotEmpty == true &&
      _owner.$2?.isNotEmpty == true &&
      _owner == (DataSp.userID, DataSp.chatToken);
  bool get _expired =>
      _value != null &&
      _value!.state == DesktopAuthorizationState.scanned &&
      !DateTime.now().isBefore(_value!.expiresAt);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_current) {
        _timer?.cancel();
        if (mounted) {
          setState(() {
            _error = AppCopy.text('登录状态已变化，请重新扫码');
            _value = null;
          });
        }
      } else if (_expired) {
        _timer?.cancel();
        setState(() {});
      }
    });
  }

  Future<void> _load() async {
    if (!_current) {
      setState(() {
        _loading = false;
        _error = AppCopy.text('请先登录 99Chat，再扫描电脑上的二维码');
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await _service.scan(widget.requestId);
      if (_current) setState(() => _value = value);
    } catch (error) {
      if (_current) {
        setState(() => _error = error is QrLoginFailure
            ? error.message
            : error is DesktopAuthorizationUnavailable
                ? AppCopy.text('扫码登录暂不可用，请稍后再试')
                : AppCopy.text('无法获取登录请求，请检查网络后重试'));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirm() async {
    if (!_current ||
        _busy ||
        _expired ||
        _value?.state != DesktopAuthorizationState.scanned) {
      return;
    }
    if (!RegExp(r'^[0-9]{6}$').hasMatch(_code.text)) {
      setState(() => _error = AppCopy.text('请输入电脑上显示的六位数字'));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final value = await _service.confirm(widget.requestId,
          verificationCode: _code.text);
      if (_current) setState(() => _value = value);
    } catch (error) {
      if (_current) {
        setState(() => _error = error is QrLoginFailure
            ? error.message
            : AppCopy.text('确认结果暂未获取，请重试核对'));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close() async {
    if (_busy) return;
    if (_current && _value?.state == DesktopAuthorizationState.scanned) {
      unawaited(_service.cancel(widget.requestId).catchError((Object _) {}));
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _value;
    final state = _expired ? DesktopAuthorizationState.expired : value?.state;
    final title = switch (state) {
      DesktopAuthorizationState.active =>
        AppCopy.format('{#0}已登录', [value!.platform]),
      DesktopAuthorizationState.approved => AppCopy.text('已确认，请在电脑上继续'),
      DesktopAuthorizationState.expired => AppCopy.text('二维码已过期'),
      DesktopAuthorizationState.cancelled => AppCopy.text('已取消登录'),
      _ => value == null
          ? (_error ?? AppCopy.text('正在获取登录请求'))
          : AppCopy.format('登录 {#0} 版 99Chat', [value.platform]),
    };
    final canConfirm = state == DesktopAuthorizationState.scanned && _current;
    return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_close());
        },
        child: DesktopAuthorizationLayout(
          title: title,
          loading: _loading,
          busy: _busy,
          loggedIn: state == DesktopAuthorizationState.active,
          onClose: () => unawaited(_close()),
          action: canConfirm
              ? AppCopy.text('确认登录')
              : value == null
                  ? AppCopy.text('重试')
                  : '完成',
          onAction: canConfirm
              ? () => unawaited(_confirm())
              : value == null
                  ? () => unawaited(_load())
                  : () => unawaited(_close()),
          detail: Column(children: [
            if (value != null &&
                state == DesktopAuthorizationState.scanned) ...[
              DesktopLoginDeviceDetails(
                  deviceName: value.deviceName,
                  platform: value.platform,
                  code: value.code,
                  region: value.region),
              const SizedBox(height: 16),
              DesktopLoginCodeInput(
                controller: _code,
                enabled: !_busy,
              ),
            ],
            if (state == DesktopAuthorizationState.expired)
              Text(AppCopy.text('请在电脑上刷新二维码后重新扫描。')),
            if (_error != null && value != null)
              Text(_error!, textAlign: TextAlign.center),
          ]),
        ));
  }
}
