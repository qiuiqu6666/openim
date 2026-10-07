import '../support/sangong_ui.dart';
import '../models/sangong_admin_models.dart';

String sangongBetSubmitSuccessToast(
    AppI18n i18n, SangongBetSubmitResult result) {
  final refund = result.refundedAmount;
  final status = result.collectionReady
      ? i18n.t(
          zhHans: '截止完成，可录入开彩',
          zhHant: '截止完成，可錄入開彩',
          en: 'Closed. Draw entry is ready')
      : i18n.t(
          zhHans: '已截止，正在核对群消息',
          zhHant: '已截止，正在核對群訊息',
          en: 'Closed. Verifying group messages');
  if (refund <= 0) return status;
  return i18n.t(
      zhHans: '$status，已退回 $refund 积分',
      zhHant: '$status，已退回 $refund 積分',
      en: '$status; $refund points refunded');
}
