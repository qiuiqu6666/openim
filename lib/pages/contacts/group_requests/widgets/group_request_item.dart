import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../../request_history/presentation/request_history_labels.dart';
import '../../request_history/presentation/request_history_style.dart';
import '../../request_history/presentation/request_history_time.dart';
import '../../request_history/widgets/request_history_row.dart';
import '../../request_history/widgets/request_history_status.dart';
import 'group_request_handler_label.dart';

class GroupRequestItem extends StatelessWidget {
  const GroupRequestItem(
      {super.key,
      required this.application,
      required this.groupName,
      required this.groupAvatar,
      required this.outgoing,
      required this.onReview,
      this.onOpenChat,
      this.inviter,
      this.handler});

  final GroupApplicationInfo application;
  final String groupName;
  final String? groupAvatar;
  final bool outgoing;
  final String? inviter;
  final String? handler;
  final VoidCallback onReview;
  final VoidCallback? onOpenChat;

  @override
  Widget build(BuildContext context) {
    final time = requestHistoryTime(application.reqTime,
        group: true, english: RequestHistoryLabels.english);
    final handled =
        application.handleResult == 1 || application.handleResult == -1;
    return RequestHistoryRow(
      group: true,
      onTap: application.handleResult == 1
          ? onOpenChat
          : !outgoing
              ? onReview
              : null,
      avatar: AvatarView(
          url: groupAvatar,
          text: groupName,
          isGroup: true,
          width: RequestHistoryStyle.groupAvatar,
          height: RequestHistoryStyle.groupAvatar),
      title: LayoutBuilder(
          builder: (context, constraints) =>
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Flexible(
                    child: Text(groupName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: RequestHistoryStyle.title(context))),
                if (time.isNotEmpty) ...[
                  const SizedBox(width: AppTokens.s3),
                  ConstrainedBox(
                      constraints:
                          BoxConstraints(maxWidth: constraints.maxWidth * .48),
                      child: Text(time,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: RequestHistoryStyle.subtitle(context))),
                ],
              ])),
      subtitle: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              RequestHistoryLabels.groupContent(
                  application.nickname ?? '', groupName, inviter),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: RequestHistoryStyle.subtitle(context)),
          if (handled)
            GroupRequestHandlerLabel(nickname: handler, compact: true),
        ],
      ),
      trailing: !handled && !outgoing
          ? RequestHistoryAction(
              label: RequestHistoryLabels.review, onPressed: onReview)
          : RequestHistoryStatus(
              result: application.handleResult,
              label: application.handleResult == 1
                  ? StrRes.approved
                  : application.handleResult == -1
                      ? StrRes.rejected
                      : RequestHistoryLabels.pending),
    );
  }
}
