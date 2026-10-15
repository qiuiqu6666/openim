import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../../widgets/loading/skeleton_shimmer.dart';
import '../moments_text.dart';
import '../moments_theme.dart';

/// Finite placeholders inside the feed's existing scroll view.
class MomentsFeedSkeleton extends StatelessWidget {
  const MomentsFeedSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = momentsDark(context);
    final fill = MomentsTheme.border(dark);
    Widget bone(double width, double height, {bool avatar = false}) =>
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(avatar
                  ? MomentsLayout.avatarSize
                  : MomentsLayout.mediaRadius)),
        );
    return SkeletonShimmer(
      baseColor: fill,
      highlightColor: MomentsTheme.card(dark),
      label: momentsText(context, zh: '正在加载朋友圈', en: 'Loading Moments'),
      child: Column(children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.all(MomentsLayout.cardMargin),
            child: Padding(
              padding: MomentsLayout.cardPadding,
              child: LayoutBuilder(
                  builder: (context, bounds) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            bone(MomentsLayout.avatarSize,
                                MomentsLayout.avatarSize,
                                avatar: true),
                            const SizedBox(width: AppTokens.s3),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  bone(bounds.maxWidth * .35,
                                      MomentsLayout.nameSize),
                                  const SizedBox(height: AppTokens.s2),
                                  bone(bounds.maxWidth * .2,
                                      MomentsLayout.timeSize),
                                ])),
                          ]),
                          const SizedBox(height: AppTokens.s4),
                          bone(bounds.maxWidth, MomentsLayout.bodySize),
                          const SizedBox(height: AppTokens.s2),
                          bone(bounds.maxWidth * .65, MomentsLayout.bodySize),
                          const SizedBox(height: AppTokens.s3),
                          bone(bounds.maxWidth * .65,
                              MomentsLayout.timelineMediaSize),
                          const SizedBox(height: AppTokens.s4),
                          Divider(color: fill),
                        ],
                      )),
            ),
          ),
      ]),
    );
  }
}
