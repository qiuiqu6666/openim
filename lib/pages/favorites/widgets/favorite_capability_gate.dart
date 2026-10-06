import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/favorite_repository.dart';
import '../../mine/settings/widgets/settings_widgets.dart';
import '../navigation/favorites_app_bar.dart';

/// Prevents constructing cloud contents before both server capabilities pass.
/// The repository owns capability requests and their account-scoped cache.
class FavoriteCapabilityGate extends StatefulWidget {
  const FavoriteCapabilityGate(
      {super.key,
      required this.repository,
      required this.child,
      this.showScaffold = false,
      this.fit = StackFit.expand,
      this.title});

  final FavoriteRepository repository;
  final Widget child;
  final bool showScaffold;
  final StackFit fit;
  final String? title;

  @override
  State<FavoriteCapabilityGate> createState() => _FavoriteCapabilityGateState();
}

class _FavoriteCapabilityGateState extends State<FavoriteCapabilityGate> {
  late final String _scope;
  bool _requesting = false;
  bool _checked = false;
  bool _opened = false;
  FavoriteApiException? _failure;

  @override
  void initState() {
    super.initState();
    _scope = widget.repository.sessionScope;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_probe());
    });
  }

  Future<void> _probe({bool force = false}) async {
    if (_requesting || !widget.repository.isSessionCurrent(_scope)) return;
    if (!force && widget.repository.capabilityError != null) {
      setState(() => _checked = true);
      return;
    }
    setState(() {
      _requesting = true;
      _checked = true;
      _failure = null;
    });
    try {
      await widget.repository.ensureCapabilities(force: force);
    } catch (error) {
      if (mounted && widget.repository.isSessionCurrent(_scope)) {
        _failure = error is FavoriteApiException
            ? error
            : const FavoriteApiException(
                'CAPABILITY_UNAVAILABLE', '暂时无法确认收藏服务，请重试');
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.repository,
      builder: (context, _) {
        final current = widget.repository.isSessionCurrent(_scope);
        final available = current && widget.repository.available;
        if (available) _opened = true;
        final loading = current &&
            (_requesting ||
                widget.repository.capabilitiesLoading ||
                (!_checked && widget.repository.capabilityError == null));
        final error = widget.repository.capabilityError ?? _failure?.message;
        final message = !current
            ? settingsText(context,
                zh: '登录状态已改变，请重新打开收藏',
                en: 'Your account changed. Reopen favorites.')
            : error ??
                settingsText(context,
                    zh: '收藏服务暂未开放，请稍后重试',
                    en: 'Favorites are unavailable. Please try again later.');
        final panel = Center(
            child: SingleChildScrollView(
                child: Padding(
                    padding: const EdgeInsets.all(AppTokens.s6),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (loading)
                        const CircularProgressIndicator()
                      else
                        Icon(
                            current
                                ? Icons.cloud_off_outlined
                                : Icons.lock_outline,
                            color: settingsSecondaryTextColor(context)),
                      const SizedBox(height: AppTokens.s5),
                      Semantics(
                          liveRegion: true,
                          child: Text(
                              loading
                                  ? settingsText(context,
                                      zh: '正在连接收藏服务',
                                      en: 'Connecting to favorites')
                                  : message,
                              key: const ValueKey('favorite-capability-error'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: settingsTextColor(context)))),
                      if (current && !loading)
                        Padding(
                            padding: const EdgeInsets.only(top: AppTokens.s4),
                            child: OutlinedButton.icon(
                                key:
                                    const ValueKey('favorite-capability-retry'),
                                onPressed: () => _probe(force: true),
                                icon: const Icon(Icons.refresh),
                                label: Text(settingsText(context,
                                    zh: '重试', en: 'Retry')))),
                    ]))));
        final unavailable = widget.showScaffold
            ? Scaffold(
                key: const ValueKey('favorite-capability-gate'),
                backgroundColor:
                    AppTokens.background(dark: settingsIsDark(context)),
                appBar: favoritesAppBar(context,
                    title: widget.title ??
                        settingsText(context, zh: '收藏', en: 'Favorites')),
                body: SafeArea(top: false, child: panel))
            : panel;
        // Retain an opened editor/pending send while capability errors hide it.
        return Stack(fit: widget.fit, children: [
          if (_opened) Offstage(offstage: !available, child: widget.child),
          if (!available) unavailable,
        ]);
      });
}
