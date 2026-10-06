import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../user_profile_tokens.dart';

/// Identity layout only. The page owns SDK identity and privacy decisions.
class UserProfileIdentity extends StatelessWidget {
  const UserProfileIdentity({
    super.key,
    required this.name,
    required this.signature,
    required this.account,
    required this.copyLabel,
    required this.onCopy,
    this.avatarUrl,
    this.gender,
    this.trailing,
    this.compact = false,
    this.reserveAccountSpace = false,
  });

  final String name, signature, account, copyLabel;
  final String? avatarUrl;
  final int? gender;
  final VoidCallback onCopy;
  final Widget? trailing;
  final bool compact;
  final bool reserveAccountSpace;

  @override
  Widget build(BuildContext context) => Padding(
        padding: compact ? EdgeInsets.zero : UserProfileTokens.headerPadding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AvatarView(
                url: avatarUrl,
                text: name,
                width: UserProfileTokens.avatarSize,
                height: UserProfileTokens.avatarSize,
                isCircle: true,
                enabledPreview: true),
            const SizedBox(width: UserProfileTokens.avatarGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: UserProfileTokens.text(context),
                              fontSize: UserProfileTokens.nameSize,
                              fontWeight: FontWeight.w600)),
                    ),
                    if (gender == 1 || gender == 2)
                      Padding(
                        padding: const EdgeInsets.only(left: AppTokens.s2),
                        child: Icon(
                            gender == 1
                                ? Icons.male_rounded
                                : Icons.female_rounded,
                            size: UserProfileTokens.genderSize,
                            color: gender == 1
                                ? UserProfileTokens.maleColor
                                : UserProfileTokens.femaleColor),
                      ),
                  ]),
                  if (account.isNotEmpty || reserveAccountSpace) ...[
                    const SizedBox(height: UserProfileTokens.identityGap),
                    Visibility(
                      visible: account.isNotEmpty,
                      maintainState: true,
                      maintainAnimation: true,
                      maintainSize: true,
                      child: Material(
                        color: Colors.transparent,
                        child: account.isEmpty
                            ? _accountContent(context)
                            : Tooltip(
                                message: copyLabel,
                                child: InkWell(
                                  onTap: onCopy,
                                  borderRadius: BorderRadius.circular(
                                      UserProfileTokens.accountRadius),
                                  child: _accountContent(context),
                                ),
                              ),
                      ),
                    ),
                  ],
                  const SizedBox(height: UserProfileTokens.identityGap),
                  SizedBox(
                    height: MediaQuery.textScalerOf(context)
                            .scale(AppTokens.captionFontSize) *
                        UserProfileTokens.signatureLineHeight *
                        UserProfileTokens.signatureMaxLines,
                    child: Text(signature,
                        maxLines: UserProfileTokens.signatureMaxLines,
                        overflow: TextOverflow.ellipsis,
                        strutStyle: const StrutStyle(
                            fontSize: AppTokens.captionFontSize,
                            height: UserProfileTokens.signatureLineHeight,
                            forceStrutHeight: true),
                        style: TextStyle(
                            color: UserProfileTokens.muted(context),
                            fontSize: AppTokens.captionFontSize,
                            height: UserProfileTokens.signatureLineHeight)),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );

  // Measure the same typography, border and touch height while disclosure is
  // absent, without creating an account label, copy icon or interactive entry.
  Widget _accountContent(BuildContext context) => ConstrainedBox(
        constraints:
            const BoxConstraints(minHeight: UserProfileTokens.copyTouchTarget),
        child: Align(
          alignment: Alignment.centerLeft,
          heightFactor: 1,
          child: Ink(
            decoration: BoxDecoration(
                color: UserProfileTokens.account(context),
                borderRadius:
                    BorderRadius.circular(UserProfileTokens.accountRadius),
                border: UserProfileTokens.isDark(context)
                    ? null
                    : Border.all(color: AppTokens.borderLight)),
            child: Padding(
              padding: UserProfileTokens.accountPadding,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(account.isEmpty ? ' ' : account,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: AppTokens.captionFontSize,
                            color: UserProfileTokens.muted(context))),
                  ),
                  const SizedBox(width: AppTokens.s3),
                  if (account.isEmpty)
                    const SizedBox(
                        width: UserProfileTokens.copyIconSize,
                        height: UserProfileTokens.copyIconSize)
                  else
                    Icon(Icons.copy_outlined,
                        size: UserProfileTokens.copyIconSize,
                        color: UserProfileTokens.muted(context)),
                ],
              ),
            ),
          ),
        ),
      );
}
