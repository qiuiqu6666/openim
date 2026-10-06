// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:openim/pages/group_features/sangong/support/sangong_ui.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_admin_models.dart';
import 'package:openim/pages/group_features/sangong/widgets/sangong_round_settle_dialog.dart';

/// 开彩录入 + 本局结算。冲正重结只从三公设置进入，打 last-settled。
class SangongRoundSettleFlow {
  SangongRoundSettleFlow._();

  static SangongAdminRound? lastSettledRound(BuildContext context) =>
      SangongScope.read(context).realtime.latestState?.lastSettledRound;

  static String lastSettledCaption(BuildContext context, AppI18n i18n) {
    final periodNo = lastSettledRound(context)?.periodNo ?? 0;
    if (periodNo > 0) {
      return i18n.t(
        zhHans: '纠正第 $periodNo 期',
        zhHant: '糾正第 $periodNo 期',
        en: 'Correct period $periodNo',
      );
    }
    return i18n.t(
      zhHans: '最近已结算局',
      zhHant: '最近已結算局',
      en: 'Last settled round',
    );
  }

  static Future<bool> runLastSettledResettle(BuildContext context) async {
    final runtime = SangongScope.read(context);
    final i18n = AppI18n.of(context);
    if (!SangongScope.read(context).http.canCallAdmin) {
      ToastUtils.toast(i18n.t(
        zhHans: SangongScope.read(context).http.hasAuth ? '请先进入游戏群' : '请先登录',
        zhHant: SangongScope.read(context).http.hasAuth ? '請先進入遊戲群' : '請先登入',
        en: SangongScope.read(context).http.hasAuth
            ? 'Open a game group first'
            : 'Please sign in first',
      ));
      return false;
    }

    final hud = AppHud.begin();
    SangongDrawFetchResult fetchResult;
    try {
      fetchResult = await runtime.admin.fetchCurrentDraws();
    } catch (error) {
      ToastUtils.toast(DioErrorMessage.forApp(error));
      return false;
    } finally {
      await hud.end();
    }
    if (!context.mounted) {
      return false;
    }

    final lastSettled = lastSettledRound(context) ??
        (fetchResult.round?.isSettled == true ? fetchResult.round : null);
    if (lastSettled == null) {
      ToastUtils.toast(i18n.t(
        zhHans: '当前无可纠正的已结算局',
        zhHant: '當前無可糾正的已結算局',
        en: 'No settled round to correct',
      ));
      return false;
    }
    return _runResettle(
      context,
      i18n: i18n,
      lastSettled: lastSettled,
      currentDraw: fetchResult.draw,
    );
  }

  static Future<bool> run(BuildContext context) async {
    final runtime = SangongScope.read(context);
    final i18n = AppI18n.of(context);
    if (!SangongScope.read(context).http.canCallAdmin) {
      ToastUtils.toast(i18n.t(
        zhHans: SangongScope.read(context).http.hasAuth ? '请先进入游戏群' : '请先登录',
        zhHant: SangongScope.read(context).http.hasAuth ? '請先進入遊戲群' : '請先登入',
        en: SangongScope.read(context).http.hasAuth
            ? 'Open a game group first'
            : 'Please sign in first',
      ));
      return false;
    }

    final hud = AppHud.begin();
    SangongDrawFetchResult fetchResult;
    try {
      fetchResult = await runtime.admin.fetchCurrentDraws();
    } catch (error) {
      ToastUtils.toast(DioErrorMessage.forApp(error));
      return false;
    } finally {
      await hud.end();
    }

    final round = fetchResult.round;
    final drawStatus = fetchResult.draw;
    final roundId =
        drawStatus.roundId > 0 ? drawStatus.roundId : (round?.id ?? 0);

    if (roundId <= 0) {
      ToastUtils.toast(i18n.t(
        zhHans: '当前无有效局',
        zhHant: '當前無有效局',
        en: 'No active round',
      ));
      return false;
    }

    if (round?.isSettled == true) {
      ToastUtils.toast(i18n.t(
        zhHans: '本局已结算，冲正重结请到三公设置',
        zhHant: '本局已結算，沖正重結請到三公設置',
        en: 'Already settled. Use Sangong settings to resettle.',
      ));
      return false;
    }

    if (round != null && !round.hasBetWindowClose) {
      ToastUtils.toast(i18n.t(
        zhHans: '请先截止下注，再录入开彩',
        zhHant: '請先截止下注，再錄入開彩',
        en: 'Close betting before entering draws',
      ));
      return false;
    }

    if (!context.mounted) {
      return false;
    }

    List<SangongDrawInput> inputs;
    if (drawStatus.complete) {
      inputs = const [];
    } else {
      final dialogResult = await SangongRoundSettleDialog.show(
        context,
        drawStatus: drawStatus,
      );
      if (dialogResult == null || !context.mounted || !runtime.isCurrent) {
        return false;
      }
      inputs = dialogResult;
    }

    try {
      var latestDraw = drawStatus;
      unawaited(AppDialog.showLoading(
        text: i18n.t(
          zhHans: '正在结算…',
          zhHant: '正在結算…',
          en: 'Settling…',
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!context.mounted || !runtime.isCurrent) {
        AppDialog.hideLoading();
        return false;
      }
      try {
        if (inputs.isNotEmpty) {
          final mutation = await runtime.admin.submitDraws(inputs);
          latestDraw = mutation.draw;
          if (!mutation.draw.complete) {
            final missing = mutation.draw.missingDoors;
            final missingText = missing.isEmpty
                ? ''
                : i18n.t(
                    zhHans: '：门${missing.join('、门')}',
                    zhHant: '：門${missing.join('、門')}',
                    en: ': doors ${missing.join(', ')}',
                  );
            if (context.mounted) {
              ToastUtils.toast(i18n.t(
                zhHans: '开彩未录满$missingText',
                zhHant: '開彩未錄滿$missingText',
                en: 'Draws incomplete$missingText',
              ));
            }
            return false;
          }
        } else if (!latestDraw.complete) {
          if (context.mounted) {
            ToastUtils.toast(i18n.t(
              zhHans: '开彩未录满，无法结算',
              zhHant: '開彩未錄滿，無法結算',
              en: 'Draws incomplete, cannot settle',
            ));
          }
          return false;
        }

        if (!context.mounted || !runtime.isCurrent) return false;
        await runtime.admin.settleRound(roundId);
      } finally {
        AppDialog.hideLoading();
      }
      if (!context.mounted) {
        return true;
      }
      ToastUtils.toast(i18n.t(
        zhHans: '结算成功',
        zhHant: '結算成功',
        en: 'Round settled',
      ));
      return true;
    } catch (error) {
      if (context.mounted) {
        ToastUtils.toast(DioErrorMessage.forApp(error));
      }
      return false;
    }
  }

  /// 二次确认 → 空开彩表 → `POST .../last-settled/resettle`。
  static Future<bool> _runResettle(
    BuildContext context, {
    required AppI18n i18n,
    required SangongAdminRound lastSettled,
    required SangongDrawStatus currentDraw,
  }) async {
    final runtime = SangongScope.read(context);
    final periodText =
        lastSettled.periodNo > 0 ? '${lastSettled.periodNo}' : '';
    final confirmed = await AppDialog.confirm(
      context: context,
      title: i18n.t(
        zhHans: '冲正重结',
        zhHant: '沖正重結',
        en: 'Void & resettle',
      ),
      message: periodText.isNotEmpty
          ? i18n.t(
              zhHans: '纠正第 $periodText 期：将撤销该期结算并清空开奖号码，下注保留。当前未结算局不受影响。',
              zhHant: '糾正第 $periodText 期：將撤銷該期結算並清空開獎號碼，下注保留。當前未結算局不受影響。',
              en: 'Correct period $periodText: void that settlement and clear draws. Current unsettled round stays.',
            )
          : i18n.t(
              zhHans: '将撤销最近已结算局并清空开奖号码，下注保留。当前未结算局不受影响。',
              zhHant: '將撤銷最近已結算局並清空開獎號碼，下注保留。當前未結算局不受影響。',
              en: 'Void the last settled round and clear draws. Current unsettled round stays.',
            ),
      confirmText: i18n.t(
        zhHans: '重新开奖',
        zhHant: '重新開獎',
        en: 'Re-draw',
      ),
      destructive: true,
    );
    if (!confirmed || !context.mounted) {
      return false;
    }

    final emptyDraw = _emptyDrawForLastSettled(
      context: context,
      lastSettled: lastSettled,
      currentDraw: currentDraw,
    );
    final inputs = await SangongRoundSettleDialog.show(
      context,
      drawStatus: emptyDraw,
      clearExisting: true,
      titleText: i18n.t(
        zhHans: '重新开奖',
        zhHant: '重新開獎',
        en: 'Re-enter draws',
      ),
      subtitleText: i18n.t(
        zhHans: '请重新录入各门号码，勿沿用旧开奖',
        zhHant: '請重新錄入各門號碼，勿沿用舊開獎',
        en: 'Enter new draws; do not reuse old values',
      ),
      confirmLabel: i18n.t(
        zhHans: '冲正重结',
        zhHant: '沖正重結',
        en: 'Resettle',
      ),
    );
    if (inputs == null || !context.mounted) {
      return false;
    }
    if (inputs.isEmpty) {
      ToastUtils.toast(i18n.t(
        zhHans: '冲正重结须重新录入开奖号码',
        zhHant: '沖正重結須重新錄入開獎號碼',
        en: 'Resettle requires new draws',
      ));
      return false;
    }

    try {
      unawaited(AppDialog.showLoading(
        text: i18n.t(
          zhHans: '冲正并重新结算中…',
          zhHant: '沖正並重新結算中…',
          en: 'Voiding and resettling…',
        ),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!context.mounted || !runtime.isCurrent) {
        AppDialog.hideLoading();
        return false;
      }
      try {
        final result = await runtime.admin.resettleLastSettled(draws: inputs);
        if (!result.ok) throw StateError('冲正重结结果尚未确认，请刷新后查看');
      } finally {
        AppDialog.hideLoading();
      }
      if (!context.mounted) {
        return true;
      }
      ToastUtils.toast(i18n.t(
        zhHans: '冲正重结成功',
        zhHant: '沖正重結成功',
        en: 'Resettled successfully',
      ));
      return true;
    } catch (error) {
      if (context.mounted) {
        ToastUtils.toast(DioErrorMessage.forApp(error));
      }
      return false;
    }
  }

  static SangongDrawStatus _emptyDrawForLastSettled({
    required BuildContext context,
    required SangongAdminRound lastSettled,
    required SangongDrawStatus currentDraw,
  }) {
    if (currentDraw.roundId > 0 && currentDraw.roundId == lastSettled.id) {
      return sangongEmptyDrawStatusForResettle(currentDraw);
    }
    final doorCount =
        (SangongScope.read(context).realtime.latestState?.doorCount ??
                currentDraw.doorCount)
            .clamp(2, 10);
    final doors = List<int>.generate(doorCount, (index) => index + 1);
    return SangongDrawStatus(
      doorCount: doorCount,
      bankerDoor: lastSettled.bankerDoor,
      requiredDoors: doors,
      missingDoors: doors,
      complete: false,
      draws: const [],
    );
  }
}
