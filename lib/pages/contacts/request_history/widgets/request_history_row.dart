import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../presentation/request_history_style.dart';

class RequestHistoryRow extends StatelessWidget {
  const RequestHistoryRow({
    super.key,
    required this.avatar,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.group = false,
    this.leading,
    this.onTap,
  });

  final Widget avatar;
  final Widget title;
  final Widget subtitle;
  final Widget? trailing;
  final Widget? leading;
  final bool group;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final size =
        group ? RequestHistoryStyle.groupAvatar : RequestHistoryStyle.avatar;
    final gap = group ? RequestHistoryStyle.groupGap : AppTokens.s4;
    return Material(
      color: RequestHistoryStyle.surface(context),
      child: InkWell(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: AppTokens.s5,
                vertical: group ? RequestHistoryStyle.groupGap : AppTokens.s3),
            child: LayoutBuilder(builder: (context, constraints) {
              final stacked = trailing != null &&
                  (constraints.maxWidth < RequestHistoryStyle.stackWidth ||
                      MediaQuery.textScalerOf(context)
                              .scale(RequestHistoryStyle.titleSize) >
                          RequestHistoryStyle.stackTextSize);
              return Row(
                crossAxisAlignment: group
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
                children: [
                  if (leading != null) ...[
                    SizedBox(width: AppTokens.s8, child: leading),
                    const SizedBox(width: AppTokens.s3),
                  ],
                  SizedBox(width: size, height: size, child: avatar),
                  SizedBox(width: gap),
                  Expanded(
                      child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      SizedBox(
                          height: group
                              ? RequestHistoryStyle.titleGap
                              : AppTokens.s2),
                      subtitle,
                      if (stacked) ...[
                        const SizedBox(height: RequestHistoryStyle.titleGap),
                        trailing!,
                      ],
                    ],
                  )),
                  if (trailing != null && !stacked) ...[
                    const SizedBox(width: AppTokens.s4),
                    ConstrainedBox(
                      constraints:
                          BoxConstraints(maxWidth: constraints.maxWidth * .32),
                      child: trailing,
                    ),
                  ],
                ],
              );
            }),
          ),
          Padding(
            padding: EdgeInsetsDirectional.only(
                start: AppTokens.s5 +
                    size +
                    gap +
                    (leading == null ? 0 : AppTokens.s8 + AppTokens.s3)),
            child: Divider(
                height: RequestHistoryStyle.dividerWidth,
                thickness: RequestHistoryStyle.dividerWidth,
                color: RequestHistoryStyle.divider(context)),
          ),
        ]),
      ),
    );
  }
}
