import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import 'mine_profile_localization.dart';

/// OpenIM data adapter around the exact mobile header layout used by
/// 99chat `profile.dart::_buildHeaderCard`.
class MineProfileHeader extends StatelessWidget {
  const MineProfileHeader({
    super.key,
    required this.nickname,
    required this.userId,
    required this.avatarUrl,
    this.avatarBytes,
    required this.signature,
    required this.primaryTextColor,
    required this.secondaryTextColor,
    required this.arrowColor,
    required this.dark,
    required this.onTap,
    required this.onQrTap,
  });

  final String nickname;
  final String userId;
  final String avatarUrl;
  final Uint8List? avatarBytes;
  final String signature;
  final Color primaryTextColor;
  final Color secondaryTextColor;
  final Color arrowColor;
  final bool dark;
  final VoidCallback onTap;
  final VoidCallback onQrTap;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final signatureMaxWidth = screenWidth * 0.56;
    final signatureHPadding = screenWidth * 0.028;
    final signatureVPadding = screenWidth * 0.010;
    final signatureIconSize = screenWidth * 0.034;
    final signatureGap = screenWidth * 0.012;
    final signatureFontSize = screenWidth * 0.034;

    return InkWell(
      key: const ValueKey('mine-profile-header'),
      onTap: onTap,
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        child: Row(
          children: [
            _avatar(),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      color: primaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${mineText(context, zh: '99号ID', en: '99 ID')}: $userId',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      color: secondaryTextColor.withValues(alpha: 0.92),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      key: const ValueKey('mine-signature-pill'),
                      constraints: BoxConstraints(maxWidth: signatureMaxWidth),
                      padding: EdgeInsets.symmetric(
                        horizontal: signatureHPadding,
                        vertical: signatureVPadding,
                      ),
                      decoration: BoxDecoration(
                        color: dark
                            ? AppTokens.profileSignatureBgDark
                                .withValues(alpha: 0.20)
                            : AppTokens.profileSignatureBgLight
                                .withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(AppTokens.rPill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.edit_rounded,
                            key: const ValueKey('mine-signature-edit-icon'),
                            size: signatureIconSize,
                            color: dark
                                ? AppTokens.profileSignatureTextDark
                                : AppTokens.profileSignatureTextLight,
                          ),
                          SizedBox(width: signatureGap),
                          Flexible(
                            child: Text(
                              '${mineText(context, zh: '个性签名', en: 'Bio')}: $signature',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: signatureFontSize,
                                color: dark
                                    ? AppTokens.profileSignatureTextDark
                                    : AppTokens.profileSignatureTextLight,
                                fontWeight: FontWeight.w500,
                                height: 1.16,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            InkWell(
              key: const ValueKey('mine-profile-qr-button'),
              onTap: onQrTap,
              borderRadius: BorderRadius.circular(8),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: AppQrIcon(
                  key: ValueKey('mine-profile-qr-icon'),
                  size: AppTokens.profileQrIconSize,
                  color: AppTokens.accent,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              Icons.chevron_right_rounded,
              key: const ValueKey('mine-profile-chevron'),
              size: 24,
              color: arrowColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar() {
    final bytes = avatarBytes;
    if (bytes == null) {
      return AvatarView(
        url: avatarUrl,
        showLoadingAvatar: false,
        text: nickname,
        width: 72,
        height: 72,
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    return ClipOval(
      child: Image.memory(
        bytes,
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => AvatarView(
          url: avatarUrl,
          showLoadingAvatar: false,
          text: nickname,
          width: 72,
          height: 72,
        ),
      ),
    );
  }
}
