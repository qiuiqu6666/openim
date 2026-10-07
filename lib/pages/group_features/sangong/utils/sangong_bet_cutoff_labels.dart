// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'package:openim/pages/group_features/sangong/support/sangong_ui.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_admin_models.dart';
import 'package:openim/pages/group_features/sangong/utils/sangong_bet_submit_cutoff.dart';

String sangongBetCutoffSummaryLabel({
  required AppI18n i18n,
  required SangongBetPreview preview,
  SangongBetSubmitCutoff? cutoff,
  String? selectedMessagePreview,
  String? selectedSenderLabel,
}) {
  final msgSeq = preview.cutoffMsgSeq ?? cutoff?.untilMsgSeq;
  final sender = selectedSenderLabel?.trim() ?? '';
  final previewText = selectedMessagePreview?.trim() ?? '';

  if (msgSeq != null && msgSeq > 0) {
    return i18n.format(
      zhHans: '截止到消息 #$msgSeq${sender.isEmpty ? '' : '（$sender $previewText）'}',
      zhHant: '截止到 seq $msgSeq',
      en: 'Until seq $msgSeq',
      vars: {'seq': '$msgSeq'},
    );
  }

  return i18n.t(
    zhHans: '截止到本局最新 IM 消息',
    zhHant: '截止到本局最新 IM 訊息',
    en: 'Until latest IM message in this round',
  );
}

String? sangongBetCutoffAuxTimeLabel({
  required AppI18n i18n,
  required SangongBetPreview preview,
}) {
  final raw = preview.previewCloseMsgTime.trim().isNotEmpty
      ? preview.previewCloseMsgTime.trim()
      : preview.previewCloseAt.trim();
  if (raw.isEmpty) {
    return null;
  }
  final parsed = DateTime.tryParse(raw);
  final display = parsed != null ? _formatLocalDateTime(parsed.toLocal()) : raw;
  return i18n.format(
    zhHans: '参考时间 $display',
    zhHant: '參考時間 $display',
    en: 'Reference time: $display',
    vars: {'time': display},
  );
}

String _formatLocalDateTime(DateTime local) {
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  final second = local.second.toString().padLeft(2, '0');
  return '$month-$day $hour:$minute:$second';
}

String? sangongBetExcludeSummaryLabel({
  required AppI18n i18n,
  required SangongBetSubmitCutoff? cutoff,
  required SangongBetPreview preview,
  String? excludedMessagePreview,
  String? excludedSenderLabel,
}) {
  final requestIds = cutoff?.sortedExclusions ?? const [];
  final responseIds = preview.excludedMsgSeqs;
  final ids = <int>{
    ...requestIds,
    ...responseIds,
  }.toList()
    ..sort();
  if (ids.isEmpty) {
    return null;
  }

  final idText = ids.map((id) => '#$id').join('、');
  final sender = excludedSenderLabel?.trim() ?? '';
  final previewText = excludedMessagePreview?.trim() ?? '';
  if (ids.length == 1 && sender.isNotEmpty && previewText.isNotEmpty) {
    return i18n.format(
      zhHans: '排除消息 $idText（$sender $previewText）',
      zhHant: '排除訊息 $idText（$sender $previewText）',
      en: 'Excluded message $idText ($sender $previewText)',
      vars: {
        'ids': idText,
        'sender': sender,
        'text': previewText,
      },
    );
  }
  return i18n.format(
    zhHans: '排除消息 $idText',
    zhHant: '排除訊息 $idText',
    en: 'Excluded message(s) $idText',
    vars: {'ids': idText},
  );
}
