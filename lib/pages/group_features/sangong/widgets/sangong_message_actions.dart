import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import '../sangong_scope.dart';
import '../support/sangong_ui.dart' show DioErrorMessage;
import '../utils/sangong_bet_submit_cutoff.dart';
import 'sangong_bet_preview_sheet.dart';

/// Uses the chat's existing runtime and genuine server message IDs/SDK seq.
class SangongMessageActions {
  static bool canAssign(Message message) =>
      message.contentType == MessageType.text &&
      message.sendID?.trim().isNotEmpty == true &&
      message.textElem?.content?.trim().isNotEmpty == true;

  static List<PopMenuInfo> items(BuildContext context, Message message) {
    final runtime =
        context.dependOnInheritedWidgetOfExactType<SangongScope>()?.notifier;
    if (runtime == null ||
        !runtime.canManage ||
        message.status != MessageStatus.succeeded ||
        message.groupID != runtime.featureContext.groupID) {
      return [];
    }
    Future<void> run(Future<void> Function() action) async {
      // The IM popup closes before opening another overlay.
      await Future<void>.delayed(Duration.zero);
      if (!context.mounted || !runtime.canManage) return;
      try {
        await action();
      } catch (error) {
        if (context.mounted && runtime.isCurrent) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(content: Text(DioErrorMessage.forApp(error))));
        }
      }
    }

    Future<void> preview(bool exclude) async {
      final cutoff = exclude
          ? SangongBetSubmitCutoff.excludingMessage(message)
          : SangongBetSubmitCutoff.fromLongPressedMessage(message);
      if (cutoff == null) return;
      final session = await runtime.admin.fetchSession();
      if (!runtime.canManage) return;
      if (session.round == null || session.round!.id <= 0) {
        throw StateError('当前无有效局');
      }
      final settings = await runtime.settings.fetch();
      if (!runtime.canManage) return;
      final result = await runtime.admin
          .previewBets(cutoff: cutoff, roundId: session.round!.id);
      if (!context.mounted || !runtime.canManage) return;
      await SangongBetPreviewSheet.show(context,
          preview: result.preview,
          cutoff: cutoff,
          roundId: session.round?.id ?? 0,
          doorCount: settings.doorCount,
          selectedMessagePreview:
              SangongBetSubmitCutoff.readMessagePreviewText(message),
          selectedSenderLabel: SangongBetSubmitCutoff.readSenderLabel(message),
          excludeMode: exclude);
    }

    return [
      if (SangongBetSubmitCutoff.fromLongPressedMessage(message) != null)
        PopMenuInfo(
            id: 'sangong_stats',
            text: '统计',
            onTap: () => run(() => preview(false))),
      if (SangongBetSubmitCutoff.canExcludeMessage(message))
        PopMenuInfo(
            id: 'sangong_exclude',
            text: '不计入',
            onTap: () => run(() => preview(true))),
      if (canAssign(message))
        PopMenuInfo(
            id: 'sangong_banker',
            text: '定庄',
            onTap: () => run(() async {
                  final session = await runtime.admin.fetchSession();
                  final roundId = session.round?.id ?? 0;
                  if (!context.mounted || !runtime.canManage) return;
                  if (roundId <= 0) throw StateError('请先开机');
                  final result = await runtime.admin.quickSetupBanker(
                      roundId: roundId,
                      text: message.textElem?.content,
                      imUserId: message.sendID,
                      nickname: message.senderNickname);
                  if (!runtime.canManage) return;
                  if (!result.ok || result.round == null) {
                    throw StateError('定庄结果尚未确认，请刷新后查看');
                  }
                  await runtime.realtime.refreshSnapshot();
                })),
    ];
  }
}
