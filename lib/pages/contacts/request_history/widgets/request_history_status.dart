import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../presentation/request_history_style.dart';

class RequestHistoryStatus extends StatelessWidget {
  const RequestHistoryStatus(
      {super.key, required this.label, required this.result});
  final String label;
  final int? result;

  @override
  Widget build(BuildContext context) => Container(
        constraints:
            const BoxConstraints(minHeight: RequestHistoryStyle.badgeHeight),
        padding: const EdgeInsets.symmetric(
            horizontal: RequestHistoryStyle.badgeHorizontal,
            vertical: RequestHistoryStyle.badgeVertical),
        decoration: BoxDecoration(
          color: AppTokens.surfaceAlt(dark: RequestHistoryStyle.dark(context)),
          borderRadius: BorderRadius.circular(RequestHistoryStyle.badgeRadius),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
              result == 1
                  ? Icons.check_rounded
                  : result == -1
                      ? Icons.close_rounded
                      : Icons.schedule_rounded,
              size: RequestHistoryStyle.badgeIcon,
              color: RequestHistoryStyle.secondary(context)),
          const SizedBox(width: AppTokens.s2),
          Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: RequestHistoryStyle.subtitle(context)
                      .copyWith(fontWeight: FontWeight.w500))),
        ]),
      );
}

class RequestHistoryAction extends StatelessWidget {
  const RequestHistoryAction(
      {super.key, required this.label, required this.onPressed});
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        // Keep the reference's compact pill within an accessible tap area.
        height: kMinInteractiveDimension,
        child: Center(
            widthFactor: 1,
            child: FilledButton(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                backgroundColor: AppTokens.accent,
                foregroundColor: AppTokens.onAccent,
                minimumSize: const Size(RequestHistoryStyle.actionWidth,
                    RequestHistoryStyle.actionHeight),
                padding: const EdgeInsets.symmetric(horizontal: AppTokens.s5),
                shape: const StadiumBorder(),
                textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontSize: AppTokens.captionFontSize,
                    fontWeight: FontWeight.w600),
              ),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            )),
      );
}
