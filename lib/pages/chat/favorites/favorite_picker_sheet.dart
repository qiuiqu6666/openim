import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/favorite_repository.dart';
import '../../../services/favorite_send_coordinator.dart';
import '../../favorites/favorite_p0.dart';
import '../../favorites/widgets/favorite_capability_gate.dart';
import '../../mine/secondary/favorite_detail_page.dart';
import '../../mine/secondary/favorites_page.dart';
import '../../mine/settings/settings_navigation.dart';
import '../../mine/settings/widgets/settings_widgets.dart';

class FavoritePickerSheet extends StatefulWidget {
  const FavoritePickerSheet(
      {super.key,
      required this.repository,
      required this.target,
      required this.onSend,
      this.onReconcile});

  final FavoriteRepository repository;
  final FavoriteTarget target;
  final Future<FavoriteSendResult> Function(FavoriteItem) onSend;
  final Future<FavoriteSendResult> Function(String)? onReconcile;

  static Future<bool?> show(
    BuildContext context, {
    required FavoriteRepository repository,
    required FavoriteTarget target,
    required Future<FavoriteSendResult> Function(FavoriteItem) onSend,
    Future<FavoriteSendResult> Function(String)? onReconcile,
  }) =>
      showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: AppTokens.surface(dark: settingsIsDark(context)),
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
                top: Radius.circular(FavoritePickerTokens.sheetRadius))),
        clipBehavior: Clip.antiAlias,
        builder: (_) => FavoritePickerSheet(
            repository: repository,
            target: target,
            onSend: onSend,
            onReconcile: onReconcile),
      );

  @override
  State<FavoritePickerSheet> createState() => _FavoritePickerSheetState();
}

class _FavoritePickerSheetState extends State<FavoritePickerSheet> {
  late final Future<FavoriteSendResult> Function(FavoriteItem) _sender;
  late final Future<FavoriteSendResult> Function(String)? _reconcile;
  late final String _scope;
  String? _sendingID;
  String? _error;
  bool _unknown = false;
  bool _invalid = false;
  String? _unknownAttemptID;
  bool _reconciling = false;

  String _text(String zh, String en) => settingsText(context, zh: zh, en: en);
  bool get _locked =>
      _sendingID != null || _unknown || _invalid || _reconciling;

  @override
  void initState() {
    super.initState();
    // The callback captures the destination when the sheet opens.
    _sender = widget.onSend;
    _reconcile = widget.onReconcile;
    _scope = widget.repository.sessionScope;
    widget.repository.addListener(_checkSession);
  }

  void _checkSession() {
    if (mounted && !_invalid && !widget.repository.isSessionCurrent(_scope)) {
      setState(() {
        _invalid = true;
        _error =
            _text('登录状态已改变，请重新打开收藏', 'Your account changed. Reopen favorites.');
      });
    }
  }

  Future<void> _send(FavoriteItem item) async {
    if (_locked || !widget.repository.isSessionCurrent(_scope)) return;
    if (!widget.repository.available) return;
    if (!canSendFavoriteP0(item)) {
      setState(() => _error = favoriteStatusLabel(context, item).isNotEmpty
          ? favoriteStatusLabel(context, item)
          : _text('此内容暂不能快捷发送', 'This content cannot be sent yet'));
      return;
    }
    setState(() {
      _sendingID = item.id;
      _error = null;
    });
    try {
      await widget.repository.requireAvailable();
      if (!mounted || !widget.repository.isSessionCurrent(_scope)) return;
      final result = await _sender(item);
      if (!mounted || !widget.repository.isSessionCurrent(_scope)) return;
      if (result.status == FavoriteSendStatus.success) {
        Navigator.of(context).pop(true);
      } else if (result.errorCode != 'CANCELLED') {
        setState(() {
          _unknown = result.status == FavoriteSendStatus.unknown;
          _unknownAttemptID = _unknown ? result.sendAttemptID : null;
          _error = _unknown
              ? _text('发送状态待确认，请先查看目标对话，避免重复发送',
                  'Sending status is unconfirmed. Check the destination chat before sending again.')
              : result.errorMessage ??
                  _text('发送失败，点击该收藏右侧的发送按钮重试',
                      'Could not send. Tap Send beside the same favorite to retry.');
          if (result.sentCount > 0 && result.totalCount > result.sentCount) {
            _error = _text('已发送 ${result.sentCount}/${result.totalCount} 项。',
                    '${result.sentCount}/${result.totalCount} items sent. ') +
                _error!;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = _text('发送失败，请重试', 'Could not send. Please retry.'));
      }
    } finally {
      if (mounted) setState(() => _sendingID = null);
    }
  }

  Future<void> _reconcileUnknown() async {
    if (!_unknown ||
        _reconciling ||
        _invalid ||
        _unknownAttemptID == null ||
        _reconcile == null ||
        !widget.repository.isSessionCurrent(_scope)) {
      return;
    }
    setState(() => _reconciling = true);
    try {
      final result = await _reconcile(_unknownAttemptID!);
      if (!mounted || !widget.repository.isSessionCurrent(_scope)) return;
      if (result.status == FavoriteSendStatus.success) {
        Navigator.of(context).pop(true);
      } else if (result.errorCode == 'PARTIAL_READY' &&
          result.status == FavoriteSendStatus.failed) {
        setState(() {
          _unknown = false;
          _unknownAttemptID = null;
          _error = _text('已核实已发送部分，点击该收藏右侧的发送按钮继续发送剩余内容',
              'Sent content has been confirmed. Tap Send beside the same favorite to continue the remaining content.');
        });
      } else {
        setState(() => _error = result.errorMessage ??
            _text('发送状态仍待确认，请稍后核实',
                'Sending status is still unconfirmed. Check again later.'));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = _text(
            '暂时无法核实，请稍后重试', 'Could not verify yet. Please try again later.'));
      }
    } finally {
      if (mounted) setState(() => _reconciling = false);
    }
  }

  Future<void> _preview(FavoriteItem item) async {
    if (_locked || !widget.repository.isSessionCurrent(_scope)) return;
    await openSettingsPage<void>(
        context,
        FavoriteDetailPage(
            repository: widget.repository, item: item, readOnly: true));
  }

  Future<void> _openManager() async {
    if (_locked || !widget.repository.isSessionCurrent(_scope)) return;
    final query = widget.repository.query;
    final kind = widget.repository.filterKind;
    await openSettingsPage<void>(
        context, FavoritesPage(repository: widget.repository));
    if (mounted && widget.repository.isSessionCurrent(_scope)) {
      await widget.repository.refresh(query: query, kind: kind);
    }
  }

  @override
  void dispose() {
    widget.repository.removeListener(_checkSession);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final available = MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).bottom;
    final dark = settingsIsDark(context);
    return Theme(
        data: Theme.of(context).copyWith(
            progressIndicatorTheme: Theme.of(context)
                .progressIndicatorTheme
                .copyWith(color: AppTokens.accent)),
        child: Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: SizedBox(
            height: available.clamp(
                0.0,
                MediaQuery.sizeOf(context).height *
                    FavoritePickerTokens.sheetHeightFactor),
            child: SafeArea(
                top: false,
                child: Column(children: [
                  const SizedBox(height: AppTokens.s4),
                  Container(
                    key: const ValueKey('favorite-picker-handle'),
                    width: FavoritePickerTokens.handleWidth,
                    height: FavoritePickerTokens.handleHeight,
                    decoration: BoxDecoration(
                        color: FavoritePickerTokens.handle(dark: dark),
                        borderRadius: BorderRadius.circular(
                            FavoritePickerTokens.handleRadius)),
                  ),
                  Padding(
                      padding: const EdgeInsets.fromLTRB(
                          FavoritePickerTokens.headerLeftPadding,
                          FavoritePickerTokens.cardGap,
                          FavoritePickerTokens.cardGap,
                          AppTokens.s3),
                      child: Row(children: [
                        Expanded(
                            child: Text(_text('收藏', 'Favorites'),
                                style: TextStyle(
                                    fontSize: FavoritePickerTokens.titleSize,
                                    fontWeight: FontWeight.w700,
                                    color: AppTokens.textPrimary(dark: dark)))),
                        IconButton(
                            tooltip: _text('关闭', 'Close'),
                            onPressed: () => Navigator.of(context).pop(false),
                            icon: Icon(Icons.close_rounded,
                                size: FavoritePickerTokens.closeIconSize,
                                color: AppTokens.textSecondary(dark: dark))),
                      ])),
                  if (_sendingID != null || _reconciling)
                    const LinearProgressIndicator(),
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.all(AppTokens.s4),
                        child: Semantics(
                            liveRegion: true,
                            child: Text(_error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)))),
                  if (_unknown &&
                      _unknownAttemptID != null &&
                      _reconcile != null &&
                      !_invalid)
                    TextButton.icon(
                        key: const ValueKey('favorite-reconcile'),
                        onPressed: _reconciling ? null : _reconcileUnknown,
                        icon: const Icon(Icons.fact_check_outlined),
                        label: Text(_text('核实发送结果', 'Verify sending result'))),
                  Expanded(
                      child: _invalid
                          ? const SizedBox.shrink()
                          : FavoriteCapabilityGate(
                              fit: StackFit.expand,
                              repository: widget.repository,
                              child: FavoriteCollectionView(
                                repository: widget.repository,
                                pickerStyle: true,
                                onManage: _openManager,
                                disabled: _locked,
                                onTap: _preview,
                                trailingBuilder: (item) => IconButton(
                                  key: ValueKey('favorite-send-${item.id}'),
                                  tooltip: _text('发送', 'Send'),
                                  style: IconButton.styleFrom(
                                    backgroundColor: _sendingID == item.id
                                        ? null
                                        : FavoritePickerTokens.sendBackground(
                                            dark: dark),
                                    foregroundColor:
                                        AppTokens.textSecondary(dark: dark),
                                    disabledForegroundColor:
                                        AppTokens.textSecondary(dark: dark)
                                            .withValues(alpha: 0.38),
                                    minimumSize: const Size.square(
                                        FavoritePickerTokens.sendVisualSize),
                                    fixedSize: const Size.square(
                                        FavoritePickerTokens.sendVisualSize),
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.standard,
                                    tapTargetSize: MaterialTapTargetSize.padded,
                                    shape: const CircleBorder(),
                                  ),
                                  onPressed: _locked || !canSendFavoriteP0(item)
                                      ? null
                                      : () => _send(item),
                                  icon: _sendingID == item.id
                                      ? const SizedBox.square(
                                          dimension: FavoritePickerTokens
                                              .sendProgressSize,
                                          child: CircularProgressIndicator(
                                              strokeWidth: FavoritePickerTokens
                                                  .sendProgressStroke))
                                      : const Icon(Icons.chevron_right_rounded,
                                          size: FavoritePickerTokens
                                              .sendIconSize),
                                ),
                              ))),
                ])),
          ),
        ));
  }
}
