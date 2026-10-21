import 'package:flutter/material.dart';

import '../../res/app_tokens.dart';
import 'in_app_browser_route.dart';

/// A temporary overview; the retained native views stay in their navigators.
class InAppBrowserPagePicker extends StatelessWidget {
  const InAppBrowserPagePicker({
    super.key,
    required this.pages,
    required this.selected,
    required this.onSelect,
    required this.onDismiss,
  });

  final List<InAppBrowserRoute> pages;
  final InAppBrowserRoute selected;
  final ValueChanged<InAppBrowserRoute> onSelect;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final colors = Theme.of(context).colorScheme;
    return BlockSemantics(
      child: Stack(children: [
        Positioned.fill(
          child: ModalBarrier(
            color: colors.scrim.withValues(alpha: .32),
            dismissible: true,
            onDismiss: onDismiss,
            semanticsLabel: zh ? '关闭网页列表' : 'Close web page list',
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.all(AppTokens.s5),
              child: Material(
                color: colors.surface,
                borderRadius: BorderRadius.circular(AppTokens.rLg),
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height *
                        AppTokens.browserPagePickerHeightFactor,
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Padding(
                      padding:
                          const EdgeInsetsDirectional.only(start: AppTokens.s5),
                      child: Row(children: [
                        Expanded(
                          child: Text(
                              zh
                                  ? '已打开的网页（${pages.length}）'
                                  : 'Open web pages (${pages.length})',
                              style: Theme.of(context).textTheme.titleMedium),
                        ),
                        TextButton(
                            onPressed: onDismiss,
                            child: Text(zh ? '关闭' : 'Close')),
                      ]),
                    ),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: pages.length,
                        itemBuilder: (context, index) {
                          final page = pages[index];
                          return ValueListenableBuilder<String>(
                            valueListenable: page.pageLabel,
                            builder: (context, label, _) => ListTile(
                              selected: identical(page, selected),
                              leading: const Icon(Icons.language),
                              title: Text(label,
                                  maxLines: 2, overflow: TextOverflow.ellipsis),
                              trailing: identical(page, selected)
                                  ? const Icon(Icons.check)
                                  : null,
                              onTap: () => onSelect(page),
                            ),
                          );
                        },
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
