import 'package:openim_common/localization.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../wallet/host/wallet_navigation.dart';
import '../data/compensation_api.dart';
import '../models/compensation_detail.dart';
import '../presentation/compensation_invitation.dart';
import '../presentation/compensation_page.dart';
import '../presentation/compensation_tokens.dart';
import '../presentation/compensation_poster.dart';

/// Owned by the message-list route. No global subscriptions or cached balances.
class CompensationHomeEntry extends StatefulWidget {
  const CompensationHomeEntry(
      {super.key,
      required this.active,
      this.source,
      this.poster = false,
      this.autoInvite = true});

  final bool autoInvite;

  /// Wallet uses a poster with no automatic dialog.
  final bool poster;
  final bool active;
  final CompensationSource? source;
  @override
  State<CompensationHomeEntry> createState() => _CompensationHomeEntryState();
}

class _CompensationHomeEntryState extends State<CompensationHomeEntry>
    with WidgetsBindingObserver {
  late final CompensationSource _source;
  CompensationDetail? _detail;
  final _shown = <String>{};
  Timer? _timer;
  bool _loading = false, _foreground = true, _opening = false;
  final _clock = Stopwatch();
  bool get _active =>
      mounted && widget.active && _foreground && _source.sessionValid;
  bool get _expired =>
      _detail != null &&
      !_detail!.deadline.isAfter(_detail!.serverTime.add(_clock.elapsed));
  @override
  void initState() {
    super.initState();
    _source = widget.source ?? CompensationApi();
    WidgetsBinding.instance.addObserver(this);
    _sync();
  }

  @override
  void didUpdateWidget(covariant CompensationHomeEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _sync();
  }

  void _sync() {
    _timer?.cancel();
    _timer = null;
    if (_active) {
      unawaited(_load());
      _timer = Timer.periodic(const Duration(seconds: 60), (_) => _load());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _sync();
  }

  Future<void> _load() async {
    if (!_active || _loading || _opening) return;
    _loading = true;
    try {
      final detail = await _source.entry();
      if (!_active) return;
      setState(() {
        _detail = detail;
        _clock
          ..reset()
          ..start();
      });
      if (widget.autoInvite &&
          !widget.poster &&
          detail?.state == CompensationState.unclaimed &&
          !_expired &&
          !_shown.contains(detail!.id)) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _invite(detail));
      }
    } catch (_) {
      if (mounted) setState(() => _detail = null);
    } finally {
      _loading = false;
    }
  }

  Future<void> _invite(CompensationDetail detail) async {
    if (!_active ||
        _opening ||
        _expired ||
        ModalRoute.of(context)?.isCurrent == false ||
        _shown.contains(detail.id)) {
      return;
    }
    _shown.add(detail.id);
    _opening = true;
    try {
      final open = await showDialog<bool>(
          context: context,
          builder: (_) => CompensationInvitation(detail: detail));
      // The root dialog makes HomeView set widget.active=false. Its rebuild
      // after pop can lag behind this Future, so do not gate an explicit tap
      // on the background feed's live-update flag. Keep session/lifetime guards.
      if (open == true && mounted && _foreground && _source.sessionValid) {
        await _openPage(detail);
      }
    } finally {
      _opening = false;
      if (_active) unawaited(_load());
    }
  }

  Future<void> _openPage(CompensationDetail d) async {
    if (!_source.sessionValid) return;
    await openWalletPage<void>(
        context, CompensationPage(activityID: d.id, source: _source),
        activityPage: 'compensation/${d.id}');
  }

  Future<void> _openFromTap(CompensationDetail d) async {
    if (_opening) return;
    _opening = true;
    try {
      await _openPage(d);
    } finally {
      _opening = false;
      if (_active) unawaited(_load());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _clock.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = _detail;
    if (d == null || !_source.sessionValid || _expired) {
      return const SizedBox.shrink();
    }
    if (widget.poster) {
      return CompensationPoster(
          detail: d, onTap: _opening ? null : () => _openFromTap(d));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: CompensationTokens.space,
          vertical: CompensationTokens.small),
      child: Semantics(
        button: true,
        label: AppCopy.format('{#0}，查看活动详情', [d.title]),
        child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('compensation-home-banner'),
              onTap: _opening ? null : () => _openFromTap(d),
              child: SizedBox(
                width: double.infinity,
                height: CompensationTokens.homeBannerHeight,
                child: Image.asset(CompensationTokens.homeBanner,
                    fit: BoxFit.fill, excludeFromSemantics: true),
              ),
            )),
      ),
    );
  }
}
