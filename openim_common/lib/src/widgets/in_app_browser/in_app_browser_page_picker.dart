import 'package:flutter/material.dart';

import '../../res/app_tokens.dart';
import 'in_app_browser_route.dart';

/// Hit targets sit above the retained, transformed native pages in the host.
/// No WebView is copied, reparented or reloaded for the overview.
class InAppBrowserPagePicker extends StatelessWidget {
  const InAppBrowserPagePicker(
      {super.key,
      required this.pages,
      required this.selected,
      required this.onSelect,
      required this.onDismiss,
      required this.onClose,
      required this.scrollController});

  final List<InAppBrowserRoute> pages;
  final InAppBrowserRoute selected;
  final ValueChanged<InAppBrowserRoute> onSelect, onClose;
  final VoidCallback onDismiss;
  final ScrollController scrollController;

  static double step(BuildContext context) =>
      MediaQuery.sizeOf(context).height * AppTokens.browserOverviewStep;

  static Matrix4 previewTransform(
      BuildContext context, int index, double scroll) {
    final size = MediaQuery.sizeOf(context);
    final safeTop = MediaQuery.paddingOf(context).top;
    final pageTop = safeTop +
        (size.height - safeTop) * (1 - AppTokens.browserSheetHeightFactor);
    final top = safeTop + kToolbarHeight + index * step(context) - scroll;
    return Matrix4.identity()
      ..translateByDouble(size.width / 2, top, 0, 1)
      ..multiply(Matrix4.identity()
        ..setEntry(3, 1, AppTokens.browserOverviewPerspective / size.height))
      ..scaleByDouble(
          AppTokens.browserOverviewScale, AppTokens.browserOverviewScale, 1, 1)
      ..translateByDouble(-size.width / 2, -pageTop, 0, 1);
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final colors = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    return BlockSemantics(
        child: SafeArea(
            bottom: false,
            child: Column(children: [
              SizedBox(
                  height: kToolbarHeight,
                  child: Row(children: [
                    const SizedBox(width: AppTokens.s5),
                    Expanded(
                        child: Text(
                            zh
                                ? '已打开的网页（${pages.length}）'
                                : 'Open web pages (${pages.length})',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: AppTokens.onAccent))),
                    TextButton(
                        onPressed: onDismiss,
                        style: TextButton.styleFrom(
                            foregroundColor: AppTokens.onAccent),
                        child: Text(zh ? '完成' : 'Done')),
                  ])),
              Expanded(
                  child: ListView.builder(
                controller: scrollController,
                padding: EdgeInsets.zero,
                itemCount: pages.length,
                itemBuilder: (context, index) {
                  final page = pages[index];
                  return SizedBox(
                      height: step(context) +
                          (index == pages.length - 1
                              ? size.height * AppTokens.browserOverviewTail
                              : 0),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: size.width *
                                (1 - AppTokens.browserOverviewScale) /
                                2),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onSelect(page),
                          child: ValueListenableBuilder<String>(
                            valueListenable: page.pageLabel,
                            builder: (context, label, _) => Semantics(
                              button: true,
                              label: label,
                              selected: identical(page, selected),
                              child: Column(children: [
                                Material(
                                  color: colors.surface,
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(AppTokens.rLg)),
                                  child: SizedBox(
                                      height: kToolbarHeight,
                                      child: Row(children: [
                                        IconButton(
                                            tooltip: zh
                                                ? '关闭网页 $label'
                                                : 'Close page $label',
                                            onPressed: () => onClose(page),
                                            icon: const Icon(Icons.close)),
                                        Expanded(
                                            child: Text(label,
                                                textAlign: TextAlign.center,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w600))),
                                        const SizedBox(
                                            width: kMinInteractiveDimension),
                                      ])),
                                ),
                                const Expanded(child: SizedBox.expand()),
                              ]),
                            ),
                          ),
                        ),
                      ));
                },
              )),
            ])));
  }
}
