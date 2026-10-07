// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'package:openim/pages/group_features/sangong/support/sangong_ui.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_admin_models.dart';

/// 图片报表和管理群 Excel 账单的发送结果。
String sangongReportImageSuccessToast(
  AppI18n i18n,
  SangongReportImageResult result, {
  required String fallbackZhHans,
  required String fallbackZhHant,
  required String fallbackEn,
}) {
  if (result.message.trim().isNotEmpty) {
    return result.message.trim();
  }
  final type = result.type.trim().toLowerCase();
  if (result.queued && !result.sent) {
    if (type == 'bill') {
      return i18n.t(
          zhHans: '管理群 Excel 账单已加入发送队列',
          zhHant: '管理群 Excel 賬單已加入發送佇列',
          en: 'Management group Excel bill queued');
    }
    return i18n.t(
        zhHans: '图片报表已加入发送队列',
        zhHant: '圖片報表已加入發送佇列',
        en: 'Image report queued');
  }
  if (type == 'bets' || type == 'bet_report' || result.mode.isNotEmpty) {
    final modeLabel = result.isPreview
        ? i18n.t(
            zhHans: '预览',
            zhHant: '預覽',
            en: 'preview',
          )
        : i18n.t(
            zhHans: '正式',
            zhHant: '正式',
            en: 'final',
          );
    final period = result.periodNo > 0 ? ' · 第${result.periodNo}期' : '';
    final count = result.betCount > 0 ? ' · ${result.betCount}注' : '';
    return i18n.t(
      zhHans: '统计清单已发送（$modeLabel$period$count）',
      zhHant: '統計清單已發送（$modeLabel$period$count）',
      en: 'Bet report sent ($modeLabel)',
    );
  }
  if (type.contains('bill')) {
    return i18n.t(
      zhHans: '流水/抽水账单已发送到管理统计群',
      zhHant: '流水/抽水賬單已發送到管理統計群',
      en: 'Settle bill sent to admin group',
    );
  }
  if (type.contains('point') ||
      type.contains('balance') ||
      type == 'points_report') {
    return i18n.t(
      zhHans: '用户积分图已发送',
      zhHant: '用戶積分圖已發送',
      en: 'User points image sent',
    );
  }
  if (type.contains('trend') || type == 'trend_report' || result.rowCount > 0) {
    final rows = result.rowCount > 0 ? ' · ${result.rowCount}局' : '';
    final doors = result.doorCount > 0 ? ' · ${result.doorCount}门' : '';
    return i18n.t(
      zhHans: '走势图已发送到游戏群$rows$doors',
      zhHant: '走勢圖已發送到遊戲群$rows$doors',
      en: 'Trend chart sent to game group$rows$doors',
    );
  }
  if (type.contains('settle') || type == 'settle_report') {
    return i18n.t(
      zhHans: '结算明细已发送到游戏群',
      zhHant: '結算明細已發送到遊戲群',
      en: 'Settle detail sent to game group',
    );
  }
  if (result.sent || result.ok) {
    return i18n.t(
      zhHans: fallbackZhHans,
      zhHant: fallbackZhHant,
      en: fallbackEn,
    );
  }
  return i18n.t(
    zhHans: '发送失败',
    zhHant: '發送失敗',
    en: 'Send failed',
  );
}
