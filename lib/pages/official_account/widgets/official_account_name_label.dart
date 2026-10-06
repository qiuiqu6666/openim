import 'package:flutter/material.dart';

import '../models/official_account.dart';
import '../official_account_chrome_tokens.dart';

/// 99chat's verified name layout, shared by contact and conversation surfaces.
/// Identity stays with SDK metadata; nicknames and remarks remain untouched.
class OfficialAccountNameLabel extends StatelessWidget {
  const OfficialAccountNameLabel({
    super.key,
    required this.name,
    this.userID,
    this.ex,
    this.account,
    this.isSingleChat = true,
    this.style,
    this.badgeSize = OfficialAccountChromeTokens.listBadgeSize,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
  });

  final String name;
  final String? userID;
  final String? ex;
  final OfficialAccount? account;
  final bool isSingleChat;
  final TextStyle? style;
  final double badgeSize;
  final int maxLines;
  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    final text =
        Text(name, maxLines: maxLines, overflow: overflow, style: style);
    final verified = account != null && account!.userID == userID?.trim() ||
        OfficialAccount.hasVerifiedIdentity(userID: userID, ex: ex);
    if (!isSingleChat || !verified) {
      return text;
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(child: text),
      const SizedBox(width: OfficialAccountChromeTokens.badgeGap),
      ExcludeSemantics(
        child: Image.asset(
          OfficialAccountChromeTokens.badgeAsset,
          width: badgeSize,
          height: badgeSize,
          fit: BoxFit.contain,
        ),
      ),
    ]);
  }
}
