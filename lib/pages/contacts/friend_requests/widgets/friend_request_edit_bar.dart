import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../request_history/presentation/request_history_labels.dart';
import '../../request_history/presentation/request_history_style.dart';

class FriendRequestEditBar extends StatelessWidget {
  const FriendRequestEditBar(
      {super.key,
      required this.count,
      required this.busy,
      required this.onDelete});
  final int count;
  final bool busy;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: RequestHistoryStyle.surface(context),
        child: SafeArea(
            top: false,
            child: Container(
              decoration: BoxDecoration(
                  border: Border(
                      top: BorderSide(
                          color: RequestHistoryStyle.divider(context),
                          width: RequestHistoryStyle.dividerWidth))),
              padding: const EdgeInsets.fromLTRB(
                  AppTokens.s5, AppTokens.s3, AppTokens.s5, AppTokens.s4),
              child: FilledButton(
                key: const ValueKey('friend-requests-delete-selected'),
                style: FilledButton.styleFrom(
                    backgroundColor: AppTokens.danger,
                    foregroundColor: AppTokens.onAccent,
                    minimumSize:
                        const Size.fromHeight(kMinInteractiveDimension),
                    textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontSize: RequestHistoryStyle.titleSize,
                        fontWeight: FontWeight.w600)),
                onPressed: count == 0 || busy
                    ? null
                    : () async {
                        final confirmed = await Get.dialog<bool>(CustomDialog(
                            title: RequestHistoryLabels.deletePrompt(count),
                            rightText: StrRes.delete));
                        if (confirmed == true && context.mounted) {
                          await onDelete();
                        }
                      },
                child: Text(
                    count == 0 ? StrRes.delete : '${StrRes.delete}($count)'),
              ),
            )),
      );
}
