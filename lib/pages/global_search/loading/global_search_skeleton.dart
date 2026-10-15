import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../widgets/loading/skeleton_shimmer.dart';
import '../widgets/global_search_result_tokens.dart';

/// Search placeholders share one sweep, with no interactive or readable rows.
class GlobalSearchSkeleton extends StatelessWidget {
  const GlobalSearchSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fill = AppTokens.border(dark: dark);
    final highlight = AppTokens.surface(dark: dark);
    const avatar = GlobalSearchResultTokens.avatarSize;
    Widget bone(double width, double height, {bool circle = false}) =>
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: fill,
            borderRadius:
                BorderRadius.circular(circle ? avatar : AppTokens.rSm),
          ),
        );
    return SkeletonShimmer(
      label: 'chatHistoryLoading'.tr,
      baseColor: fill,
      highlightColor: highlight,
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(
            horizontal: GlobalSearchResultTokens.horizontalPadding),
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsets.only(
                  top: AppTokens.s4, bottom: AppTokens.s2),
              child: bone(AppTokens.s8 * 2,
                  GlobalSearchResultTokens.metadataStyle(context).fontSize!),
            ),
          ),
          for (var i = 0; i < 8; i++) ...[
            ConstrainedBox(
                constraints: const BoxConstraints(
                    minHeight: GlobalSearchResultTokens.rowMinHeight),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: GlobalSearchResultTokens.verticalPadding),
                  child: Row(children: [
                    bone(avatar, avatar, circle: true),
                    const SizedBox(
                        width: GlobalSearchResultTokens.avatarTextGap),
                    Expanded(
                      child: LayoutBuilder(
                          builder: (context, bounds) => Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  bone(
                                      bounds.maxWidth * (i.isEven ? .6 : .8),
                                      GlobalSearchResultTokens.titleStyle(
                                              context)
                                          .fontSize!),
                                  const SizedBox(
                                      height: GlobalSearchResultTokens.textGap),
                                  bone(
                                      bounds.maxWidth * .45,
                                      GlobalSearchResultTokens.subtitleStyle(
                                              context)
                                          .fontSize!),
                                ],
                              )),
                    ),
                  ]),
                )),
            Divider(
                height: GlobalSearchResultTokens.dividerThickness,
                thickness: GlobalSearchResultTokens.dividerThickness,
                indent: avatar + GlobalSearchResultTokens.avatarTextGap,
                color: fill),
          ],
        ],
      ),
    );
  }
}
