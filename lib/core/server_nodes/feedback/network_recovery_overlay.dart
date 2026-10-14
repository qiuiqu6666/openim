import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart';

import 'network_recovery_progress.dart';

/// Only delayed cold-start feedback uses the common HUD. Runtime reconnects
/// keep the current page interactive and report through its connection status.
class NetworkRecoveryOverlay extends StatefulWidget {
  const NetworkRecoveryOverlay({super.key, required this.child, this.progress});
  static const revealDelay = Duration(milliseconds: 1200);
  final Widget child;
  final NetworkRecoveryProgress? progress;

  @override
  State<NetworkRecoveryOverlay> createState() => _NetworkRecoveryOverlayState();
}

class _NetworkRecoveryOverlayState extends State<NetworkRecoveryOverlay>
    with WidgetsBindingObserver {
  late final _progress = widget.progress ?? NetworkRecoveryProgress.instance;
  Widget? _ownedHud;
  bool _scheduled = false;
  Timer? _revealTimer;
  bool _delayPassed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _progress.addListener(_schedule);
    EasyLoading.addStatusCallback(_onHudStatus);
    _schedule();
  }

  void _schedule() {
    if (_scheduled || !mounted) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _refresh();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _refresh() {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    final foreground =
        lifecycle == null || lifecycle == AppLifecycleState.resumed;
    final startup = _progress.value?.context == NetworkRecoveryContext.startup;
    if (!foreground || !startup) {
      _cancelReveal();
      _dismissOwned();
      return;
    }
    if (!_delayPassed) {
      _revealTimer ??= Timer(NetworkRecoveryOverlay.revealDelay, () {
        _revealTimer = null;
        _delayPassed = true;
        _schedule();
      });
      return;
    }
    // Internal route/retry stages do not change copy, geometry or animation.
    if (_ownedHud != null && identical(EasyLoading.instance.w, _ownedHud)) {
      return;
    }
    _ownedHud = null;
    if (EasyLoading.isShow) return;
    unawaited(EasyLoading.show(
        status: 'networkPreparing'.tr,
        maskType: EasyLoadingMaskType.none,
        dismissOnTap: false));
    _ownedHud = EasyLoading.instance.w;
  }

  void _cancelReveal() {
    _revealTimer?.cancel();
    _revealTimer = null;
    _delayPassed = false;
  }

  void _onHudStatus(EasyLoadingStatus status) {
    if (status == EasyLoadingStatus.dismiss) _schedule();
  }

  void _dismissOwned() {
    if (_ownedHud != null && identical(EasyLoading.instance.w, _ownedHud)) {
      unawaited(EasyLoading.dismiss(animation: false));
    }
    _ownedHud = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _cancelReveal();
      _dismissOwned();
    } else {
      // Foregrounding must not immediately replay a stale startup HUD.
      _schedule();
    }
  }

  @override
  void dispose() {
    _progress.removeListener(_schedule);
    EasyLoading.removeCallback(_onHudStatus);
    WidgetsBinding.instance.removeObserver(this);
    _cancelReveal();
    _dismissOwned();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
