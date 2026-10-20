import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

class PendingForwardBar extends StatelessWidget {
  const PendingForwardBar({
    super.key,
    required this.count,
    required this.onCancel,
    this.sending = false,
  });

  final int count;
  final VoidCallback onCancel;
  final bool sending;

  @override
  Widget build(BuildContext context) => TextFieldTapRegion(
        child: Material(
          color: ChatComposerTokens.surface(
              dark: Theme.of(context).brightness == Brightness.dark),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppTokens.s3),
                child: SvgPicture.asset(
                  'lib/pages/chat/messages/forwarding/assets/forward.svg',
                  width: AppTokens.s7,
                  height: AppTokens.s7,
                  colorFilter:
                      const ColorFilter.mode(AppTokens.accent, BlendMode.srcIn),
                  excludeFromSemantics: true,
                ),
              ),
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsetsDirectional.only(start: AppTokens.s2),
                  decoration: const BoxDecoration(
                    border: BorderDirectional(
                      start: BorderSide(
                          color: AppTokens.accent, width: AppTokens.s2 / 2),
                    ),
                  ),
                  child: Text(
                    'chatPendingForwardCount'.trParams({'count': '$count'}),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppTokens.accent,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('pending-forward-cancel'),
                tooltip: 'chatCancelForward'.tr,
                onPressed: sending ? null : onCancel,
                color: AppTokens.accent,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      );
}
