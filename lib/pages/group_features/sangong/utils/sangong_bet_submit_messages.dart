// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'package:openim/pages/group_features/sangong/support/sangong_ui.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_admin_models.dart';

/// 截止 / 重新截止提交成功文案。
String sangongBetSubmitSuccessToast(
  AppI18n i18n,
  SangongBetSubmitResult result,
) {
  final placed = result.placedCount;
  final failed = result.failedCount;
  final failedSuffix = failed > 0
      ? i18n.t(
          zhHans: '，$failed 笔失败',
          zhHant: '，$failed 筆失敗',
          en: ', $failed failed',
        )
      : '';
  if (!result.isRecutoff) {
    return i18n.t(
      zhHans: '截止成功：$placed 笔已落注$failedSuffix',
      zhHant: '截止成功：$placed 筆已落注$failedSuffix',
      en: 'Closed: $placed bet(s) placed$failedSuffix',
    );
  }

  final recutoff = result.recutoff;
  final detailParts = <String>[];
  if (recutoff != null) {
    if (recutoff.cancelled > 0) {
      detailParts.add(
        i18n.t(
          zhHans: '撤销 ${recutoff.cancelled} 笔',
          zhHant: '撤銷 ${recutoff.cancelled} 筆',
          en: '${recutoff.cancelled} cancelled',
        ),
      );
    }
    if (recutoff.requeued > 0) {
      detailParts.add(
        i18n.t(
          zhHans: '重排 ${recutoff.requeued} 笔',
          zhHant: '重排 ${recutoff.requeued} 筆',
          en: '${recutoff.requeued} requeued',
        ),
      );
    }
  }
  final recall = result.recallSummary;
  if (recall != null && recall.recalled > 0) {
    detailParts.add(
      i18n.t(
        zhHans: '撤回统计 ${recall.recalled} 条',
        zhHant: '撤回統計 ${recall.recalled} 條',
        en: '${recall.recalled} stat message(s) recalled',
      ),
    );
  }
  final detailSuffix = detailParts.isEmpty ? '' : '（${detailParts.join('，')}）';
  return i18n.t(
    zhHans: '重新截止成功：$placed 笔已落注$detailSuffix$failedSuffix',
    zhHant: '重新截止成功：$placed 筆已落注$detailSuffix$failedSuffix',
    en: 'Re-cutoff: $placed bet(s) placed$detailSuffix$failedSuffix',
  );
}
