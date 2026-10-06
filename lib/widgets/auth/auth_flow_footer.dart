import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import 'auth_tokens.dart';

/// Keeps the secondary navigation centered, including when copy wraps.
class AuthFlowFooter extends StatelessWidget {
  const AuthFlowFooter({
    super.key,
    required this.prompt,
    required this.action,
    required this.onTap,
  });
  final String prompt;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
              child: Divider(color: AuthTokens.welcomeInputBorder(context))),
          const SizedBox(width: AppTokens.s3),
          Expanded(
            flex: 6,
            child: Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppTokens.s3,
                children: [
                  Text(prompt,
                      style: AuthTokens.body(context),
                      textAlign: TextAlign.center),
                  TextButton(
                    onPressed: onTap,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, AuthTokens.touchTarget),
                      foregroundColor: AuthTokens.link(context),
                      textStyle: AuthTokens.body(context)
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    child: Text(action),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppTokens.s3),
          Expanded(
              child: Divider(color: AuthTokens.welcomeInputBorder(context))),
        ],
      );
}
