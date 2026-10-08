import '../identity/widgets/sangong_identity_view.dart';
// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import 'package:flutter/material.dart';
import 'package:openim/pages/group_features/sangong/support/sangong_ui.dart';
import 'package:openim/pages/group_features/sangong/models/group_game_round_status.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_admin_models.dart';
import 'package:openim/pages/group_features/sangong/utils/sangong_bet_cutoff_labels.dart';
import 'package:openim/pages/group_features/sangong/utils/sangong_bet_submit_cutoff.dart';
import 'package:openim/pages/group_features/sangong/utils/sangong_bet_submit_messages.dart';
import 'package:openim/pages/group_features/sangong/utils/sangong_admin_error_message.dart';
import 'package:openim/pages/group_features/sangong/widgets/group_game_status_banner.dart';
import 'authorization/privilege_route_guard.dart';

/// 长按「统计」：自下而上展示下注预览，可在此确认截止。
class SangongBetPreviewSheet extends StatefulWidget {
  const SangongBetPreviewSheet({
    super.key,
    required this.preview,
    this.cutoff = const SangongBetSubmitCutoff(),
    required this.roundId,
    required this.doorCount,
    this.bankerName = '',
    this.bankerDoor,
    this.selectedMessagePreview,
    this.selectedSenderLabel,
    this.excludeMode = false,
  });

  final SangongBetPreview preview;
  final SangongBetSubmitCutoff cutoff;
  final int roundId;
  final int doorCount;
  final String bankerName;
  final int? bankerDoor;
  final String? selectedMessagePreview;
  final String? selectedSenderLabel;
  final bool excludeMode;

  static Future<SangongBetSubmitResult?> show(
    BuildContext context, {
    required SangongBetPreview preview,
    required SangongBetSubmitCutoff cutoff,
    required int roundId,
    required int doorCount,
    String bankerName = '',
    int? bankerDoor,
    String? selectedMessagePreview,
    String? selectedSenderLabel,
    bool excludeMode = false,
  }) {
    final runtime = SangongScope.read(context);
    final featureContext = runtime.featureContext;
    if (!runtime.canManage) return Future.value(null);
    return showModalBottomSheet<SangongBetSubmitResult>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (context) => SangongPrivilegeRouteGuard(
        featureContext: featureContext,
        refreshOnEntry: false,
        isCurrent: () => runtime.canManage,
        builder: (context) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: SangongScope(
                runtime: runtime,
                child: SangongBetPreviewSheet(
                  preview: preview,
                  cutoff: cutoff,
                  roundId: roundId,
                  doorCount: doorCount,
                  bankerName: bankerName,
                  bankerDoor: bankerDoor,
                  selectedMessagePreview: selectedMessagePreview,
                  selectedSenderLabel: selectedSenderLabel,
                  excludeMode: excludeMode,
                )),
          ),
        ),
      ),
    );
  }

  @override
  State<SangongBetPreviewSheet> createState() => _SangongBetPreviewSheetState();
}

class _SangongBetPreviewSheetState extends State<SangongBetPreviewSheet> {
  late SangongBetPreview _preview;
  late SangongBetSubmitCutoff _cutoff;
  bool _submitting = false;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _preview = widget.preview;
    _cutoff = widget.cutoff;
  }

  Future<void> _onConfirmSubmit() async {
    if (_submitting || _refreshing) {
      return;
    }
    setState(() => _submitting = true);
    final i18n = AppI18n.of(context);
    final hud = AppHud.begin();
    try {
      try {
        final result = await SangongScope.read(context).admin.submitBets(
              cutoff: _cutoff,
              roundId: widget.roundId,
            );
        if (!mounted) {
          return;
        }
        ToastUtils.toast(sangongBetSubmitSuccessToast(i18n, result));
        Navigator.of(context).pop(result);
      } catch (error) {
        if (!mounted) {
          return;
        }
        ToastUtils.toast(SangongAdminErrorMessage.fromBetting(error));
        setState(() => _submitting = false);
      }
    } finally {
      await hud.end();
    }
  }

  Future<bool> _confirmExcludeEntry(SangongBetPreviewEntry entry) async {
    final messageId = entry.msgSeq;
    if (messageId == null || messageId <= 0 || _submitting || _refreshing) {
      return false;
    }
    final i18n = AppI18n.of(context);
    final detailParts = <String>[
      sangongDisplayName(entry.displayName, entry.imUserId),
      if (entry.text.trim().isNotEmpty)
        entry.text.trim()
      else
        entry.doorsLabel(),
      if (entry.resolvedTotalAmount > 0) '${entry.resolvedTotalAmount}',
    ].where((part) => part.trim().isNotEmpty).toList();
    final detail = detailParts.join('  ');
    final confirmed = await AppDialog.confirm(
      context: context,
      title: i18n.t(
        zhHans: '不计入',
        zhHant: '不計入',
        en: 'Exclude',
      ),
      message: detail.isNotEmpty
          ? i18n.format(
              zhHans: '确定将这条消息的全部注单排除，并在开奖时退款？\n$detail',
              zhHant: '確定將這條訊息的全部注單排除，並在開獎時退款？\n$detail',
              en: 'Exclude all bets in this message and refund at draw entry?\n$detail',
              vars: {'detail': detail},
            )
          : i18n.format(
              zhHans: '确定将 #$messageId 不计入统计？',
              zhHant: '確定將 #$messageId 不計入統計？',
              en: 'Exclude #$messageId from the preview?',
              vars: {'id': '$messageId'},
            ),
      cancelText: i18n.t(
        zhHans: '取消',
        zhHant: '取消',
        en: 'Cancel',
      ),
      confirmText: i18n.t(
        zhHans: '不计入',
        zhHant: '不計入',
        en: 'Exclude',
      ),
      destructive: true,
    );
    if (!confirmed || !mounted) {
      return false;
    }
    await _performExcludeEntry(entry);
    return false;
  }

  Future<void> _performExcludeEntry(SangongBetPreviewEntry entry) async {
    final messageId = entry.msgSeq;
    if (messageId == null || messageId <= 0 || !mounted) {
      return;
    }
    final i18n = AppI18n.of(context);
    setState(() => _refreshing = true);
    final hud = AppHud.begin();
    try {
      try {
        final nextCutoff = _cutoff.withAdditionalExclude(messageId);
        final result = await SangongScope.read(context).admin.previewBets(
              cutoff: nextCutoff,
              roundId: widget.roundId,
            );
        if (!mounted) {
          return;
        }
        setState(() {
          _cutoff = nextCutoff;
          _preview = result.preview;
          _refreshing = false;
        });
        ToastUtils.toast(
          i18n.format(
            zhHans: '已排除 #$messageId',
            zhHant: '已排除 #$messageId',
            en: 'Excluded #$messageId',
            vars: {'id': '$messageId'},
          ),
        );
      } catch (error) {
        if (!mounted) {
          return;
        }
        ToastUtils.toast(SangongAdminErrorMessage.fromBetting(error));
        setState(() => _refreshing = false);
      }
    } finally {
      await hud.end();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = AppColors.text(dark: dark);
    final subColor = AppColors.subText(dark: dark);
    final surface = AppColors.card(dark: dark);
    final primary = Theme.of(context).colorScheme.primary;
    final i18n = AppI18n.of(context);
    final preview = _preview;
    final report = preview.report;
    final count = widget.doorCount.clamp(2, 10);
    final cutoffSummary = sangongBetCutoffSummaryLabel(
      i18n: i18n,
      preview: preview,
      cutoff: _cutoff,
      selectedMessagePreview: widget.selectedMessagePreview,
      selectedSenderLabel: widget.selectedSenderLabel,
    );
    final cutoffAuxTime = sangongBetCutoffAuxTimeLabel(
      i18n: i18n,
      preview: preview,
    );
    final excludeSummary = sangongBetExcludeSummaryLabel(
      i18n: i18n,
      cutoff: _cutoff,
      preview: preview,
      excludedMessagePreview:
          _cutoff.hasExclusions ? widget.selectedMessagePreview : null,
      excludedSenderLabel:
          _cutoff.hasExclusions ? widget.selectedSenderLabel : null,
    );
    final roundStatus = GroupGameRoundStatus(
      bankerName: widget.bankerName,
      bankerDoor: widget.bankerDoor,
      totalBetCount: report.grandTotal,
      doorBetTotals: report.doorValuesForCount(count),
    );
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.78;
    final entries = report.entries;
    final useEntries = entries.isNotEmpty;
    final users = report.users;
    final busy = _submitting || _refreshing;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: subColor.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.excludeMode
                          ? i18n.t(
                              zhHans: '排除预览',
                              zhHant: '排除預覽',
                              en: 'Exclusion preview',
                            )
                          : i18n.t(
                              zhHans: '下注预览',
                              zhHant: '下注預覽',
                              en: 'Bet preview',
                            ),
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: busy ? null : _onConfirmSubmit,
                    style: TextButton.styleFrom(
                      foregroundColor: primary,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(48, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: _submitting
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: primary,
                            ),
                          )
                        : Text(
                            i18n.t(
                              zhHans: '发送',
                              zhHant: '發送',
                              en: 'Send',
                            ),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cutoffSummary,
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (cutoffAuxTime != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        cutoffAuxTime,
                        style: TextStyle(color: subColor, fontSize: 12),
                      ),
                    ],
                    if (excludeSummary != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        excludeSummary,
                        style: TextStyle(
                          color: AppColors.primaryRed,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (preview.excludedAfterCutoff > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        i18n.format(
                          zhHans:
                              '截止点之后 ${preview.excludedAfterCutoff} 条下注消息未纳入，开奖时退回',
                          zhHant:
                              '截止點之後 ${preview.excludedAfterCutoff} 條下注消息未納入，開獎時退回',
                          en: '${preview.excludedAfterCutoff} betting message(s) after cutoff excluded',
                          vars: {
                            'count': '${preview.excludedAfterCutoff}',
                          },
                        ),
                        style: TextStyle(
                          color: AppColors.primaryRed,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: GroupGameStatusBanner(
                  doorCount: count,
                  roundStatus: roundStatus,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        useEntries
                            ? i18n.t(
                                zhHans: '逐条注单',
                                zhHant: '逐條注單',
                                en: 'Bet entries',
                              )
                            : i18n.t(
                                zhHans: '用户下注明细',
                                zhHant: '用戶下注明細',
                                en: 'User bet details',
                              ),
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (useEntries && report.entryCount > 0)
                      Text(
                        i18n.format(
                          zhHans: '共 ${report.entryCount} 条',
                          zhHant: '共 ${report.entryCount} 條',
                          en: '${report.entryCount} entries',
                          vars: {'count': '${report.entryCount}'},
                        ),
                        style: TextStyle(color: subColor, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ),
            Flexible(
              child: Stack(
                children: [
                  if (useEntries)
                    _buildEntriesList(
                      entries: entries,
                      dark: dark,
                      titleColor: titleColor,
                      subColor: subColor,
                      i18n: i18n,
                      busy: busy,
                    )
                  else
                    _buildUsersList(
                      users: users,
                      count: count,
                      dark: dark,
                      titleColor: titleColor,
                      subColor: subColor,
                      i18n: i18n,
                    ),
                  if (_refreshing)
                    Positioned.fill(
                      child: ColoredBox(
                        color: surface.withValues(alpha: 0.55),
                        child: const Center(
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 12 + bottomInset),
              child: Text(
                useEntries
                    ? i18n.t(
                        zhHans: '左滑单条可不计入（需确认）；点右上角发送将截止落注',
                        zhHant: '左滑單條可不計入（需確認）；點右上角發送將截止落注',
                        en: 'Swipe left to exclude (confirm required). Tap Send to place bets.',
                      )
                    : i18n.t(
                        zhHans: '点右上角发送将截止落注',
                        zhHant: '點右上角發送將截止落注',
                        en: 'Tap Send to place bets at cutoff.',
                      ),
                textAlign: TextAlign.center,
                style: TextStyle(color: subColor, fontSize: 12, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntriesList({
    required List<SangongBetPreviewEntry> entries,
    required bool dark,
    required Color titleColor,
    required Color subColor,
    required AppI18n i18n,
    required bool busy,
  }) {
    if (entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Text(
          i18n.t(
            zhHans: '截止点前暂无下注',
            zhHant: '截止點前暫無下注',
            en: 'No bets before cutoff',
          ),
          style: TextStyle(color: subColor, fontSize: 14),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      itemCount: entries.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: AppColors.line(dark: dark).withValues(alpha: 0.65),
      ),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final tile = _BetEntryTile(
          entry: entry,
          titleColor: titleColor,
          subColor: subColor,
          i18n: i18n,
        );
        if (!entry.canExclude) {
          return tile;
        }
        return Dismissible(
          key: ValueKey(
              'bet-entry-${widget.roundId}-${entry.msgSeq ?? entry.messageId ?? entry.index}-${entry.imUserId}'),
          direction: busy ? DismissDirection.none : DismissDirection.endToStart,
          confirmDismiss: (_) => _confirmExcludeEntry(entry),
          background: _ExcludeSwipeBackground(i18n: i18n),
          child: tile,
        );
      },
    );
  }

  Widget _buildUsersList({
    required List<SangongBetPreviewUserStat> users,
    required int count,
    required bool dark,
    required Color titleColor,
    required Color subColor,
    required AppI18n i18n,
  }) {
    if (users.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Text(
          i18n.t(
            zhHans: '截止点前暂无下注',
            zhHant: '截止點前暫無下注',
            en: 'No bets before cutoff',
          ),
          style: TextStyle(color: subColor, fontSize: 14),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      itemCount: users.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: AppColors.line(dark: dark).withValues(alpha: 0.65),
      ),
      itemBuilder: (context, index) {
        return _UserBetDetailTile(
          user: users[index],
          doorCount: count,
          titleColor: titleColor,
          subColor: subColor,
        );
      },
    );
  }
}

class _ExcludeSwipeBackground extends StatelessWidget {
  const _ExcludeSwipeBackground({required this.i18n});

  final AppI18n i18n;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 20),
      color: AppColors.primaryRed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Icon(Icons.block, color: Colors.white, size: 20),
          const SizedBox(width: 6),
          Text(
            i18n.t(
              zhHans: '不计入',
              zhHant: '不計入',
              en: 'Exclude',
            ),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _BetEntryTile extends StatelessWidget {
  const _BetEntryTile({
    required this.entry,
    required this.titleColor,
    required this.subColor,
    required this.i18n,
  });

  final SangongBetPreviewEntry entry;
  final Color titleColor;
  final Color subColor;
  final AppI18n i18n;

  @override
  Widget build(BuildContext context) {
    final text = entry.text.trim();
    final doorsLabel = entry.doorsLabel();
    final metaParts = <String>[];
    if (entry.index > 0) {
      metaParts.add('#${entry.index}');
    }
    if (entry.messageId != null) {
      metaParts.add('id=${entry.messageId}');
    }
    if (entry.msgSeq != null) {
      metaParts.add('seq=${entry.msgSeq}');
    }
    final meta = metaParts.join('  ');
    final statusLabel = _statusLabel(entry.status);
    final detailParts = <String>[];
    if (text.isNotEmpty) {
      detailParts.add(text);
    } else if (doorsLabel.isNotEmpty) {
      if (entry.doorCount > 1 && entry.amount > 0) {
        detailParts.add('$doorsLabel 各${entry.amount}');
      } else {
        detailParts.add(doorsLabel);
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        sangongDisplayName(entry.displayName, entry.imUserId),
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (entry.isAdminSource) ...[
                      const SizedBox(width: 6),
                      _EntryBadge(
                        label: i18n.t(
                          zhHans: '后台',
                          zhHant: '後台',
                          en: 'Admin',
                        ),
                        color: subColor,
                      ),
                    ],
                    if (statusLabel != null) ...[
                      const SizedBox(width: 6),
                      _EntryBadge(
                        label: statusLabel,
                        color:
                            entry.isPlaced ? const Color(0xFF2E7D32) : subColor,
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                '${entry.resolvedTotalAmount}',
                style: TextStyle(
                  color: titleColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (detailParts.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              detailParts.join('  '),
              style: TextStyle(
                color: subColor,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              meta,
              style: TextStyle(
                color: subColor.withValues(alpha: 0.85),
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String? _statusLabel(String status) {
    switch (status.trim().toLowerCase()) {
      case 'placed':
        return i18n.t(
          zhHans: '已落注',
          zhHant: '已落注',
          en: 'Placed',
        );
      case 'pending':
        return i18n.t(
          zhHans: '待提交',
          zhHant: '待提交',
          en: 'Pending',
        );
      default:
        final trimmed = status.trim();
        return trimmed.isEmpty ? null : trimmed;
    }
  }
}

class _EntryBadge extends StatelessWidget {
  const _EntryBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.55)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _UserBetDetailTile extends StatelessWidget {
  const _UserBetDetailTile({
    required this.user,
    required this.doorCount,
    required this.titleColor,
    required this.subColor,
  });

  final SangongBetPreviewUserStat user;
  final int doorCount;
  final Color titleColor;
  final Color subColor;

  @override
  Widget build(BuildContext context) {
    final doorValues = user.doorValuesForCount(doorCount);
    final activeDoors = <int>[];
    for (var i = 0; i < doorValues.length; i++) {
      if (doorValues[i] > 0) {
        activeDoors.add(i + 1);
      }
    }
    final detail = activeDoors.isNotEmpty
        ? activeDoors.map((door) => '$door门${doorValues[door - 1]}').join('  ')
        : user.detailSummary();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SangongUserName(
                  userID: user.imUserId,
                  nickname: user.displayName,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${user.resolvedGrandTotal}',
                style: TextStyle(
                  color: titleColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              detail,
              style: TextStyle(
                color: subColor,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
