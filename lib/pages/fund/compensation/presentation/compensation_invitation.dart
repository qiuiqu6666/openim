import 'package:openim_common/localization.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/compensation_detail.dart';
import 'compensation_tokens.dart';

/// Use the approved demo artwork unchanged; only the hit areas are widgets.
class CompensationInvitation extends StatelessWidget {
  const CompensationInvitation({super.key, required this.detail});
  final CompensationDetail detail;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = math.min(
        CompensationTokens.invitationWidth,
        math.min(
            size.width - CompensationTokens.space * 2,
            (size.height -
                    MediaQuery.paddingOf(context).vertical -
                    CompensationTokens.touch -
                    CompensationTokens.space * 2) *
                1086 /
                1448));
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(CompensationTokens.space),
      child: SizedBox(
          width: width,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AspectRatio(
                aspectRatio: 1086 / 1448,
                child: Semantics(
                    button: true,
                    label: AppCopy.text('查看并领取'),
                    hint: AppCopy.text('打开活动详情，不会直接领取'),
                    child: InkWell(
                        key: const ValueKey('compensation-invitation-poster'),
                        onTap: () => Navigator.pop(context, true),
                        child: Image.asset(CompensationTokens.poster,
                            fit: BoxFit.contain, excludeFromSemantics: true)))),
            IconButton(
                tooltip: AppCopy.text('关闭活动提醒'),
                onPressed: () => Navigator.pop(context, false),
                style: IconButton.styleFrom(
                    foregroundColor: CompensationTokens.gold,
                    minimumSize: const Size(
                        CompensationTokens.touch, CompensationTokens.touch)),
                icon: const Icon(Icons.close)),
          ])),
    );
  }
}
