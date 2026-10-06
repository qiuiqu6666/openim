import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';

import '../verification_application_tokens.dart';

/// The route/controller owns identity, request authorization and submission.
class VerificationApplicationForm extends StatelessWidget {
  const VerificationApplicationForm({
    super.key,
    required this.controller,
    required this.onSend,
    this.sending = false,
    this.canSubmit = true,
    this.unavailableMessage,
    this.isEnterGroup = false,
    this.targetName = '',
    this.targetAvatarURL,
    this.targetAccount = '',
    this.maxLength = 20,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final bool sending, isEnterGroup, canSubmit;
  final String targetName, targetAccount;
  final String? targetAvatarURL, unavailableMessage;
  final int maxLength;

  String _text(BuildContext context, String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final name = targetName.trim();
    final account = targetAccount.trim();
    final hasIdentity = name.isNotEmpty ||
        account.isNotEmpty ||
        targetAvatarURL?.trim().isNotEmpty == true;
    return Scaffold(
      backgroundColor: AppTokens.background(dark: dark),
      appBar: GlassAppBar(
        centerTitle: true,
        backgroundColor: AppTokens.background(dark: dark),
        title: Text(isEnterGroup ? StrRes.groupVerification : StrRes.addFriend,
            style: TextStyle(
                color: AppTokens.textPrimary(dark: dark),
                fontSize: AppTokens.listTitleFontSize,
                fontWeight: FontWeight.w600)),
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppTokens.accent,
              size: VerificationApplicationTokens.backIconSize),
        ),
      ),
      body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(AppTokens.s5),
            child: Center(
                child: ConstrainedBox(
              constraints: const BoxConstraints(
                  maxWidth: VerificationApplicationTokens.contentMaxWidth),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (hasIdentity) ...[
                      Container(
                        key: const ValueKey('verification-target'),
                        padding: const EdgeInsets.all(AppTokens.s4),
                        decoration: BoxDecoration(
                            color: AppTokens.surface(dark: dark),
                            borderRadius: BorderRadius.circular(AppTokens.rMd)),
                        child: Row(children: [
                          AvatarView(
                              width: VerificationApplicationTokens.avatarSize,
                              height: VerificationApplicationTokens.avatarSize,
                              url: targetAvatarURL,
                              text: name.isNotEmpty ? name : account,
                              isGroup: isEnterGroup),
                          const SizedBox(width: AppTokens.s4),
                          Expanded(
                              child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (name.isNotEmpty)
                                Text(name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color:
                                            AppTokens.textPrimary(dark: dark),
                                        fontSize: VerificationApplicationTokens
                                            .nameFontSize)),
                              if (account.isNotEmpty) ...[
                                const SizedBox(height: AppTokens.s2),
                                Text(
                                    '${_text(context, '账号：', 'Account: ')}$account',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color:
                                            AppTokens.textSecondary(dark: dark),
                                        fontSize: AppTokens.captionFontSize)),
                              ],
                            ],
                          )),
                        ]),
                      ),
                      const SizedBox(height: AppTokens.s7),
                    ],
                    if (!canSubmit) ...[
                      Container(
                        key: const ValueKey('verification-unavailable'),
                        padding: const EdgeInsets.all(AppTokens.s4),
                        decoration: BoxDecoration(
                            color: AppTokens.surface(dark: dark),
                            borderRadius: BorderRadius.circular(AppTokens.rMd)),
                        child: Text(
                            unavailableMessage ??
                                _text(context, '请通过对方的聊天号、二维码或好友名片添加。',
                                    'Add this person using their chat ID, QR code, or contact card.'),
                            style: TextStyle(
                                color: AppTokens.textPrimary(dark: dark),
                                fontSize: AppTokens.secondaryFontSize)),
                      ),
                      const SizedBox(height: AppTokens.s5),
                    ],
                    Text(
                        _text(
                            context,
                            isEnterGroup ? '填写入群申请' : '填写验证信息',
                            isEnterGroup
                                ? 'Join request'
                                : 'Verification message'),
                        style: TextStyle(
                            color: AppTokens.textPrimary(dark: dark),
                            fontSize: AppTokens.secondaryFontSize,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: AppTokens.s3),
                    Container(
                      decoration: BoxDecoration(
                          color: AppTokens.surface(dark: dark),
                          borderRadius: BorderRadius.circular(AppTokens.rMd)),
                      padding: const EdgeInsets.all(AppTokens.s2),
                      child: TextField(
                        key: const ValueKey('verification-message'),
                        controller: controller,
                        enabled: canSubmit && !sending,
                        minLines: VerificationApplicationTokens.inputLines,
                        maxLines: VerificationApplicationTokens.inputLines,
                        maxLength: maxLength,
                        maxLengthEnforcement:
                            MaxLengthEnforcement.truncateAfterCompositionEnds,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        cursorColor:
                            dark ? AppTokens.onAccent : AppTokens.accent,
                        style: TextStyle(
                            color: AppTokens.textPrimary(dark: dark),
                            fontSize: AppTokens.secondaryFontSize),
                        decoration: InputDecoration(
                            hintText: _text(
                                context, '向对方介绍一下自己', 'Introduce yourself'),
                            hintStyle: TextStyle(
                                color: AppTokens.textSecondary(dark: dark)),
                            counterStyle: TextStyle(
                                color: AppTokens.textSecondary(dark: dark),
                                fontSize: AppTokens.captionFontSize),
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            contentPadding:
                                VerificationApplicationTokens.fieldPadding),
                      ),
                    ),
                    const SizedBox(height: AppTokens.s5),
                    FilledButton(
                      key: const ValueKey('verification-send'),
                      onPressed: sending || !canSubmit ? null : onSend,
                      style: FilledButton.styleFrom(
                          backgroundColor: AppTokens.accent,
                          foregroundColor: AppTokens.onAccent,
                          minimumSize: const Size.fromHeight(
                              AppTokens.s8 + AppTokens.s5),
                          padding: const EdgeInsets.all(AppTokens.s4),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  VerificationApplicationTokens.buttonRadius))),
                      child: sending
                          ? const SizedBox.square(
                              dimension: AppTokens.s6,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppTokens.onAccent))
                          : Text(StrRes.send,
                              style: const TextStyle(
                                  fontSize: AppTokens.listTitleFontSize,
                                  fontWeight: FontWeight.w600)),
                    ),
                  ]),
            )),
          )),
    );
  }
}
