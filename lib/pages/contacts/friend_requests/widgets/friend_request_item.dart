import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../../request_history/presentation/request_history_labels.dart';
import '../../request_history/presentation/request_history_style.dart';
import '../../request_history/presentation/request_history_time.dart';
import '../../request_history/widgets/request_history_row.dart';
import '../../request_history/widgets/request_history_status.dart';
import '../source/friend_application_source.dart';

class FriendRequestItem extends StatelessWidget {
  const FriendRequestItem({
    super.key,
    required this.application,
    required this.outgoing,
    required this.onView,
    this.onOpenChat,
    this.onSelect,
    this.selected = false,
  });

  final FriendApplicationInfo application;
  final bool outgoing;
  final VoidCallback onView;
  final VoidCallback? onOpenChat;
  final VoidCallback? onSelect;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final name = outgoing ? application.toNickname : application.fromNickname;
    final face = outgoing ? application.toFaceURL : application.fromFaceURL;
    final reason = friendApplicationVerification(application.reqMsg,
        english: RequestHistoryLabels.english, nickname: name);
    final time = requestHistoryTime((application.handleTime ?? 0) > 0
        ? application.handleTime
        : application.createTime);
    return Semantics(
        selected: onSelect == null ? null : selected,
        child: RequestHistoryRow(
          leading: onSelect == null
              ? null
              : Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: selected
                      ? AppTokens.accent
                      : RequestHistoryStyle.secondary(context),
                  size: RequestHistoryStyle.backIcon,
                ),
          onTap: onSelect ?? (application.isAgreed ? onOpenChat : null),
          avatar: AvatarView(
              url: face,
              text: name,
              width: RequestHistoryStyle.avatar,
              height: RequestHistoryStyle.avatar),
          title: Text(name ?? '',
              style: RequestHistoryStyle.title(context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          subtitle: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(reason,
                  style: RequestHistoryStyle.subtitle(context),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: AppTokens.s2),
              Text(
                  [
                    if (time.isNotEmpty) time,
                    RequestHistoryLabels.direction(outgoing)
                  ].join(' · '),
                  style: RequestHistoryStyle.metadata(context),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
          trailing: onSelect != null
              ? null
              : application.isWaitingHandle && !outgoing
                  ? RequestHistoryAction(
                      label: RequestHistoryLabels.verify, onPressed: onView)
                  : RequestHistoryStatus(
                      result: application.handleResult,
                      label: application.isAgreed
                          ? StrRes.approved
                          : application.isRejected
                              ? StrRes.rejected
                              : StrRes.waitingForVerification,
                    ),
        ));
  }
}
