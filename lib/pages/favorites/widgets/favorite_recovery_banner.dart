import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/favorite_repository.dart';
import '../../mine/settings/widgets/settings_widgets.dart';

/// Surfaces sync/outbox failures without blocking confirmed cloud favorites.
class FavoriteRecoveryBanner extends StatefulWidget {
  const FavoriteRecoveryBanner({super.key, required this.repository});
  final FavoriteRepository repository;
  @override
  State<FavoriteRecoveryBanner> createState() => _FavoriteRecoveryBannerState();
}

class _FavoriteRecoveryBannerState extends State<FavoriteRecoveryBanner> {
  late final String _scope;
  bool _retrying = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _scope = widget.repository.sessionScope;
  }

  Future<void> _retry() async {
    if (_retrying || !widget.repository.isSessionCurrent(_scope)) return;
    setState(() {
      _retrying = true;
      _error = null;
    });
    try {
      await widget.repository.requireAvailable();
      await widget.repository.syncChanges();
      if (widget.repository.isSessionCurrent(_scope)) {
        await widget.repository.refresh();
      }
    } catch (error) {
      if (mounted && widget.repository.isSessionCurrent(_scope)) {
        _error = error is FavoriteApiException
            ? error.message
            : settingsText(context,
                zh: '同步失败，请重试', en: 'Could not sync. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.repository,
      builder: (context, _) {
        if (!widget.repository.isSessionCurrent(_scope)) {
          return const SizedBox.shrink();
        }
        final messages = <String>{
          if (widget.repository.syncError != null) widget.repository.syncError!,
          if (widget.repository.replayError != null)
            widget.repository.replayError!,
          if (_error != null) _error!
        };
        final pending = widget.repository.pendingRecovery.length;
        if (messages.isEmpty && pending == 0) return const SizedBox.shrink();
        return Padding(
            key: const ValueKey('favorite-recovery-banner'),
            padding: const EdgeInsets.all(AppTokens.s4),
            child: Material(
                color: AppTokens.surfaceAlt(dark: settingsIsDark(context)),
                borderRadius: BorderRadius.circular(AppTokens.rMd),
                child: Padding(
                    padding: const EdgeInsets.all(AppTokens.s4),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                              child: Semantics(
                                  liveRegion: true,
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        for (final message in messages)
                                          Text(message,
                                              style: TextStyle(
                                                  color: settingsTextColor(
                                                      context))),
                                        if (pending > 0)
                                          Text(
                                              settingsText(context,
                                                  zh:
                                                      '$pending 条收藏操作待确认，原内容已保留',
                                                  en:
                                                      '$pending favorite operations need confirmation. Original contents are kept.'),
                                              style: TextStyle(
                                                  color:
                                                      settingsSecondaryTextColor(
                                                          context))),
                                      ]))),
                          const SizedBox(width: AppTokens.s3),
                          TextButton(
                              key: const ValueKey('favorite-recovery-retry'),
                              onPressed: _retrying || widget.repository.syncing
                                  ? null
                                  : _retry,
                              child: Text(settingsText(context,
                                  zh: _retrying ? '同步中' : '刷新',
                                  en: _retrying ? 'Syncing' : 'Refresh'))),
                        ]))));
      });
}
