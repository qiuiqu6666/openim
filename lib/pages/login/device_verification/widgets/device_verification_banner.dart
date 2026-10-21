import 'package:flutter/material.dart';
import '../../../../widgets/auth/auth_reference.dart';

/// Device challenge artwork is decorative; instructions remain readable text.
class DeviceVerificationBanner extends StatelessWidget {
  const DeviceVerificationBanner(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.email});
  final String title;
  final String subtitle;
  final bool email;

  @override
  Widget build(BuildContext context) {
    final brand =
        AuthReferenceTokens.color(context, AuthReferenceTokens.brand500);
    return Container(
      padding: const EdgeInsets.all(AuthReferenceTokens.bannerPadding),
      decoration: BoxDecoration(
        color: AuthReferenceTokens.color(context, AuthReferenceTokens.brand50),
        borderRadius: BorderRadius.circular(AuthReferenceTokens.rLg),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final showArtwork = constraints.maxWidth >= 280 &&
            MediaQuery.textScalerOf(context).scale(14) < 20;
        return Row(children: [
          ExcludeSemantics(
              child: Icon(Icons.verified_user_rounded,
                  color: brand, size: AuthReferenceTokens.plainFormButtonGap)),
          const SizedBox(width: AuthReferenceTokens.bannerIconGap),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: AuthReferenceTokens.style(
                      context,
                      AuthReferenceTokens.caption.copyWith(
                          color: AuthReferenceTokens.ink900,
                          fontWeight: FontWeight.w700))),
              const SizedBox(height: AuthReferenceTokens.messageGap),
              Text(subtitle,
                  style: AuthReferenceTokens.style(
                      context,
                      AuthReferenceTokens.caption
                          .copyWith(color: AuthReferenceTokens.ink400))),
            ],
          )),
          if (showArtwork) ...[
            const SizedBox(width: AuthReferenceTokens.labelGap),
            ExcludeSemantics(
                child: SizedBox(
              width: AuthReferenceTokens.heroTopGap,
              height: AuthReferenceTokens.heroTopGap,
              child: !email
                  ? Image.asset(
                      'lib/pages/login/device_verification/assets/phone_verification.png',
                      fit: BoxFit.contain,
                      excludeFromSemantics: true,
                    )
                  : Stack(alignment: Alignment.center, children: [
                      Icon(Icons.drafts_rounded,
                          size: AuthReferenceTokens.heroTopGap,
                          color: brand.withValues(alpha: .25)),
                      Align(
                          alignment: AlignmentDirectional.topEnd,
                          child: CircleAvatar(
                            radius: AuthReferenceTokens.bannerRadius,
                            backgroundColor: brand,
                            child: Icon(Icons.alternate_email,
                                size: AuthReferenceTokens.formBackIcon,
                                color: AuthReferenceTokens.surface),
                          )),
                    ]),
            )),
          ],
        ]);
      }),
    );
  }
}
