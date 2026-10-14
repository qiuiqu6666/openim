import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:get/get.dart';

import 'network_recovery_progress.dart';

/// Uses the same globally configured HUD as saving a video to the gallery.
/// Never replaces the navigator or dismisses another feature's feedback.
class NetworkRecoveryOverlay extends StatefulWidget {
  const NetworkRecoveryOverlay({super.key, required this.child, this.progress});
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _progress.addListener(_schedule);
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
    final stage = lifecycle == null || lifecycle == AppLifecycleState.resumed
        ? _progress.value
        : null;
    if (stage == null) {
      _dismissOwned();
      return;
    }
    final status = switch (stage) {
      NetworkRecoveryStage.checking => 'networkPreparing'.tr,
      NetworkRecoveryStage.startingShield => 'networkConnectingFallback'.tr,
      NetworkRecoveryStage.retrying => 'networkRecoveryRetrying'.tr,
    };
    if (_ownedHud != null && identical(EasyLoading.instance.w, _ownedHud)) {
      EasyLoading.instance.key?.currentState?.updateStatus(status);
      return;
    }
    _ownedHud = null;
    if (EasyLoading.isShow) return;
    unawaited(EasyLoading.show(status: status, dismissOnTap: false));
    _ownedHud = EasyLoading.instance.w;
  }

  void _dismissOwned() {
    if (_ownedHud != null && identical(EasyLoading.instance.w, _ownedHud)) {
      unawaited(EasyLoading.dismiss(animation: false));
    }
    _ownedHud = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _schedule();

  @override
  void dispose() {
    _progress.removeListener(_schedule);
    WidgetsBinding.instance.removeObserver(this);
    _dismissOwned();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
