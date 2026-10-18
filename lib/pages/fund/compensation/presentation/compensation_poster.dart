import 'package:flutter/material.dart';
import '../models/compensation_detail.dart';
import 'compensation_tokens.dart';

/// User-supplied campaign artwork, unchanged and clickable as a whole.
class CompensationPoster extends StatelessWidget {
  const CompensationPoster(
      {super.key, required this.detail, required this.onTap});
  final CompensationDetail detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(CompensationTokens.space),
        child: Semantics(
          button: true,
          enabled: onTap != null,
          label: '${detail.title}，查看活动详情',
          onTap: onTap,
          excludeSemantics: true,
          child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: const ValueKey('compensation-wallet-banner'),
                onTap: onTap,
                child: AspectRatio(
                    aspectRatio: 2160 / 360,
                    child: Image.asset(CompensationTokens.walletBanner,
                        fit: BoxFit.contain, excludeFromSemantics: true)),
              )),
        ),
      );
}
