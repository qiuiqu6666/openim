import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'home/wallet_home_view.dart';
import 'wallet_controller.dart';
import 'wallet_repository.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({
    super.key,
    this.embeddedInMainTab = false,
    this.isTabActive = true,
    this.activeTabIndexListenable,
    this.mainTabIndex = 3,
    this.repository,
  });

  final bool embeddedInMainTab;

  final bool isTabActive;

  /// Main-tab activation is observed without rebuilding the cached wallet
  /// subtree every time the bottom navigation index changes.
  final ValueListenable<int>? activeTabIndexListenable;

  final int mainTabIndex;
  final WalletRepository? repository;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => WalletController(repo: widget.repository),
      child: _WalletTabLifecycle(
        isTabActive: widget.isTabActive,
        activeTabIndexListenable: widget.activeTabIndexListenable,
        mainTabIndex: widget.mainTabIndex,
        child: WalletHomeView(embeddedInMainTab: widget.embeddedInMainTab),
      ),
    );
  }
}

class _WalletTabLifecycle extends StatefulWidget {
  const _WalletTabLifecycle({
    required this.isTabActive,
    required this.activeTabIndexListenable,
    required this.mainTabIndex,
    required this.child,
  });

  final bool isTabActive;
  final ValueListenable<int>? activeTabIndexListenable;
  final int mainTabIndex;
  final Widget child;

  @override
  State<_WalletTabLifecycle> createState() => _WalletTabLifecycleState();
}

class _WalletTabLifecycleState extends State<_WalletTabLifecycle> {
  DateTime? _lastReloadAt;
  bool _routeActive = true;

  @override
  void initState() {
    super.initState();
    widget.activeTabIndexListenable?.addListener(_handleTabIndexChanged);
    _reloadIfActive();
  }

  @override
  void dispose() {
    widget.activeTabIndexListenable?.removeListener(_handleTabIndexChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _WalletTabLifecycle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(
      oldWidget.activeTabIndexListenable,
      widget.activeTabIndexListenable,
    )) {
      oldWidget.activeTabIndexListenable
          ?.removeListener(_handleTabIndexChanged);
      widget.activeTabIndexListenable?.addListener(_handleTabIndexChanged);
    }
    _reloadIfActive();
  }

  void _handleTabIndexChanged() => _reloadIfActive();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeActive = (ModalRoute.of(context)?.isCurrent ?? true) &&
        TickerMode.valuesOf(context).enabled;
    _reloadIfActive();
  }

  bool get _isActive => widget.activeTabIndexListenable == null
      ? widget.isTabActive
      : widget.activeTabIndexListenable!.value == widget.mainTabIndex;

  void _reloadIfActive() {
    final controller = context.read<WalletController>();
    if (!_isActive || !_routeActive) {
      controller.setActive(false);
      return;
    }
    // Reactivation may notify; defer it until the inherited-widget build ends.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isActive || !_routeActive) return;
      if (controller.setActive(true)) _lastReloadAt = DateTime.now();
    });
    if (controller.hasDeferredRefresh) return;
    final now = DateTime.now();
    final last = _lastReloadAt;
    if (last != null && now.difference(last) < const Duration(seconds: 10)) {
      return;
    }
    _lastReloadAt = now;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_isActive || !_routeActive) return;
      await context.read<WalletController>().load();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
