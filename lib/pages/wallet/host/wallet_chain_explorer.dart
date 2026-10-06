import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/wallet_tip.dart';
import 'wallet_i18n.dart';

/// Open the original on-chain transaction in TRONSCAN.
Future<void> openWalletTronTransaction(
    BuildContext context, String transactionHash) async {
  final hash = transactionHash.trim();
  if (hash.isEmpty) return;
  final uri = Uri(
      scheme: 'https',
      host: 'tronscan.org',
      pathSegments: ['transaction', hash, 'overview']);
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } catch (_) {
    // Use the same feedback for an unavailable browser or a launcher failure.
  }
  if (!context.mounted) return;
  final i18n = AppI18n.of(context);
  WalletTip.show(
      context,
      i18n.t(
          zhHans: '无法打开波场浏览器，请稍后重试',
          zhHant: '無法開啟波場瀏覽器，請稍後重試',
          en: 'Unable to open TRONSCAN. Please try again later.',
          ja: 'TRONSCANを開けません。後でもう一度お試しください。',
          ko: 'TRONSCAN을 열 수 없습니다. 잠시 후 다시 시도해 주세요.'));
}
