import 'package:flutter/material.dart';

import 'auth_reference_tokens.dart';

/// Keeps the hint line stable while allowing translated or enlarged text to wrap.
class AuthFieldMessage extends StatelessWidget {
  const AuthFieldMessage({super.key, this.text, this.reserveSpace = false});
  final String? text;
  final bool reserveSpace;

  @override
  Widget build(BuildContext context) {
    final message = text?.trim();
    final hasMessage = message != null && message.isNotEmpty;
    if (!hasMessage && !reserveSpace) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AuthReferenceTokens.messageGap),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.textScalerOf(context)
              .scale(AuthReferenceTokens.messageHeight),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: hasMessage
              ? Semantics(
                  liveRegion: true,
                  child: Text(message,
                      style: AuthReferenceTokens.caption
                          .copyWith(color: AuthReferenceTokens.error)),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

/// A server error remains visible until the user edits or retries the form.
class AuthFormMessage extends StatelessWidget {
  const AuthFormMessage({super.key, this.text});
  final String? text;

  @override
  Widget build(BuildContext context) {
    final message = text?.trim();
    if (message == null || message.isEmpty) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AuthReferenceTokens.error.withValues(alpha: .05),
          borderRadius: BorderRadius.circular(AuthReferenceTokens.rLg),
          border: Border.all(
              color: AuthReferenceTokens.error.withValues(alpha: .15)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.error_outline,
              size: 18, color: AuthReferenceTokens.error),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style: AuthReferenceTokens.label.copyWith(
                      color: AuthReferenceTokens.error,
                      fontWeight: FontWeight.w400,
                      height: 1.4))),
        ]),
      ),
    );
  }
}
