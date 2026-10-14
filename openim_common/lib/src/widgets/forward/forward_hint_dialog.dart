import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'forward_dialog_tokens.dart';
import 'forward_message_preview.dart';

class ForwardHintDialog extends StatelessWidget {
  const ForwardHintDialog(
      {super.key,
      required this.title,
      this.checkedList = const [],
      this.nameBuilder,
      this.nameMinHeight = 0,
      this.preview});

  final String title;
  final List<dynamic> checkedList;
  final Widget Function(BuildContext, dynamic recipient, TextStyle)?
      nameBuilder;
  final double nameMinHeight;
  final ForwardPreviewData? preview;

  @override
  Widget build(BuildContext context) {
    final recipients = IMUtils.convertCheckedListToForwardObj(checkedList);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final border = AppTokens.border(dark: dark);
    final style = TextStyle(
        color: AppTokens.textPrimary(dark: dark),
        fontSize: AppTokens.listTitleFontSize);
    Widget name(int index, {bool compact = false}) {
      final textStyle =
          compact ? style.copyWith(fontSize: AppTokens.captionFontSize) : style;
      return ConstrainedBox(
          constraints: BoxConstraints(minHeight: nameMinHeight),
          child: nameBuilder?.call(context, checkedList[index], textStyle) ??
              Text(recipients[index]['nickname'] ?? '',
                  style: textStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis));
    }

    Widget avatar(int index) => AvatarView(
        url: recipients[index]['faceURL'],
        text: recipients[index]['nickname'],
        isGroup: IMUtils.convertCheckedToGroupID(checkedList[index]) != null,
        width: ForwardDialogTokens.avatar,
        height: ForwardDialogTokens.avatar,
        isCircle: false,
        borderRadius: BorderRadius.circular(AppTokens.rSm));
    final label = Text(
        recipients.length <= 1 ? StrRes.sentTo : StrRes.sentSeparatelyTo,
        style: style.copyWith(fontWeight: FontWeight.w600));
    return Dialog(
      backgroundColor: AppTokens.surface(dark: dark),
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(AppTokens.s7),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.rMd)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
          constraints:
              const BoxConstraints(maxWidth: ForwardDialogTokens.maxWidth),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
                child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppTokens.s6),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (recipients.length == 1)
                            Row(children: [
                              Flexible(child: label),
                              const SizedBox(width: AppTokens.s3),
                              avatar(0),
                              const SizedBox(width: AppTokens.s4),
                              Expanded(child: name(0)),
                            ])
                          else ...[
                            label,
                            const SizedBox(height: AppTokens.s4),
                            ConstrainedBox(
                                constraints: const BoxConstraints(
                                    maxHeight:
                                        ForwardDialogTokens.recipientHeight),
                                child: SingleChildScrollView(child:
                                    LayoutBuilder(
                                        builder: (context, constraints) {
                                  final scale = MediaQuery.textScalerOf(context)
                                          .scale(AppTokens.captionFontSize) /
                                      AppTokens.captionFontSize;
                                  final columns = (constraints.maxWidth /
                                          (ForwardDialogTokens
                                                  .recipientCellWidth *
                                              math.max(1, scale)))
                                      .floor()
                                      .clamp(1, 4);
                                  final width = (constraints.maxWidth -
                                          AppTokens.s3 * (columns - 1)) /
                                      columns;
                                  return Wrap(
                                      spacing: AppTokens.s3,
                                      runSpacing: AppTokens.s4,
                                      children: List.generate(
                                          recipients.length,
                                          (index) => SizedBox(
                                              width: width,
                                              child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    avatar(index),
                                                    const SizedBox(
                                                        height: AppTokens.s2),
                                                    name(index, compact: true),
                                                  ]))));
                                }))),
                          ],
                          const SizedBox(height: AppTokens.s5),
                          Divider(height: 1, color: border),
                          const SizedBox(height: AppTokens.s5),
                          ForwardMessagePreview(
                              data: preview ??
                                  ForwardPreviewData(
                                      kind: ForwardPreviewKind.text,
                                      title: title)),
                        ]))),
            Divider(height: 1, color: border),
            IntrinsicHeight(
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  Expanded(
                      child: TextButton(
                          key: const ValueKey('forward-cancel'),
                          style: TextButton.styleFrom(
                              minimumSize: const Size(
                                  0, ForwardDialogTokens.actionHeight),
                              foregroundColor:
                                  AppTokens.textSecondary(dark: dark),
                              shape: const RoundedRectangleBorder()),
                          onPressed: () => Navigator.of(context).pop(false),
                          child: Text(StrRes.cancel, style: style))),
                  VerticalDivider(width: 1, color: border),
                  Expanded(
                      child: TextButton(
                          key: const ValueKey('forward-send'),
                          style: TextButton.styleFrom(
                              minimumSize: const Size(
                                  0, ForwardDialogTokens.actionHeight),
                              foregroundColor: ForwardDialogTokens.send,
                              shape: const RoundedRectangleBorder()),
                          onPressed: recipients.isEmpty
                              ? null
                              : () => Navigator.of(context).pop(true),
                          child: Text(
                              recipients.length > 1
                                  ? '${StrRes.send}（${recipients.length}）'
                                  : StrRes.send,
                              textAlign: TextAlign.center,
                              style: style.copyWith(
                                  color: recipients.isEmpty
                                      ? AppTokens.textSecondary(dark: dark)
                                      : ForwardDialogTokens.send,
                                  fontWeight: FontWeight.w600)))),
                ])),
          ])),
    );
  }
}
