import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../../official_account/official_account_chrome_tokens.dart';
import '../../official_account/widgets/official_account_name_label.dart';
import '../presentation/ai_assistant_widgets.dart';

class AiAssistantHeader extends StatelessWidget implements PreferredSizeWidget {
  const AiAssistantHeader(
      {super.key,
      required this.dark,
      required this.searching,
      required this.searchController,
      required this.searchFocus,
      required this.onBack,
      required this.onSearch,
      this.onOverflow,
      required this.onQuery,
      required this.onStep,
      required this.matches,
      required this.activeMatch,
      this.title = '99ChatAI',
      this.userID,
      this.ex,
      this.subtitle,
      this.toolbarHeight = kToolbarHeight});
  final bool dark, searching;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final VoidCallback onBack, onSearch, onQuery;
  final VoidCallback? onOverflow;
  final ValueChanged<int> onStep;
  final int matches, activeMatch;
  final double toolbarHeight;
  final String title;
  final String? userID;
  final String? ex;
  final String? subtitle;
  @override
  Size get preferredSize =>
      Size.fromHeight(toolbarHeight + AiMetrics.headerDividerHeight);

  @override
  Widget build(BuildContext context) {
    final i18n = AiAssistantI18n.of(context);
    final hasQuery = searchController.text.trim().isNotEmpty;
    return AppBar(
      toolbarHeight: toolbarHeight,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 0,
      leadingWidth: AiMetrics.dimension48,
      backgroundColor: AiPalette.headerBg(dark),
      surfaceTintColor: AiPalette.transparent,
      systemOverlayStyle: AppSystemBars.styleFor(AiPalette.headerBg(dark),
          navigationBackground: AiPalette.canvasBg(dark)),
      leading: IconButton(
          onPressed: onBack,
          tooltip: i18n.t(
              zhHans: searching ? '关闭搜索' : '返回',
              en: searching ? 'Close search' : 'Back'),
          color: AppTokens.accent,
          icon: Icon(searching
              ? Icons.close_rounded
              : Icons.arrow_back_ios_new_rounded)),
      title: searching
          ? SizedBox(
              height: math.max(
                  AiMetrics.dimension36,
                  MediaQuery.textScalerOf(context).scale(AiMetrics.font14) *
                          1.4 +
                      AiMetrics.space16),
              child: TextField(
                  key: const ValueKey('ai-search-input'),
                  controller: searchController,
                  focusNode: searchFocus,
                  autofocus: true,
                  onChanged: (_) => onQuery(),
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  style: TextStyle(
                      color: AiPalette.primary(dark),
                      fontSize: AiMetrics.font14),
                  decoration: InputDecoration(
                    hintText: i18n.t(
                        zhHans: '搜索此对话',
                        zhHant: '搜尋此對話',
                        en: 'Search this chat'),
                    hintStyle: TextStyle(
                        color: AiPalette.secondary(dark),
                        fontSize: AiMetrics.font14),
                    filled: true,
                    fillColor: AiPalette.inputBg(dark),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: AiMetrics.space14,
                        vertical: AiMetrics.space8),
                    enabledBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AiMetrics.dimension18),
                        borderSide: BorderSide(color: AiPalette.line(dark))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AiMetrics.dimension18),
                        borderSide: BorderSide(color: AiPalette.line(dark))),
                  )),
            )
          : Row(children: [
              const AiAssistantAvatar(size: AiMetrics.dimension36),
              const SizedBox(width: AiMetrics.space10),
              Expanded(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    OfficialAccountNameLabel(
                        name: title,
                        userID: userID,
                        ex: ex,
                        badgeSize: OfficialAccountChromeTokens.badgeSize,
                        style: TextStyle(
                            color: AiPalette.primary(dark),
                            fontSize: AiMetrics.font17,
                            fontWeight: FontWeight.w600)),
                    Text(
                        subtitle ??
                            i18n.t(
                                zhHans: '智能助手 · 更聪明的聊天体验',
                                zhHant: '智慧助手 · 更聰明的聊天體驗',
                                en:
                                    'Smart assistant · A smarter chat experience'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AiPalette.secondary(dark),
                            fontSize: AiMetrics.font11,
                            fontWeight: FontWeight.w400)),
                  ])),
            ]),
      actions: [
        if (searching && hasQuery) ...[
          Center(
              child: Text(matches == 0 ? '0/0' : '${activeMatch + 1}/$matches',
                  style: TextStyle(
                      color: AiPalette.secondary(dark),
                      fontSize: AiMetrics.font11))),
          IconButton(
              tooltip: i18n.t(zhHans: '上一项', en: 'Previous match'),
              onPressed: matches == 0 ? null : () => onStep(-1),
              icon: Icon(Icons.keyboard_arrow_up_rounded,
                  color: AiPalette.primary(dark))),
          IconButton(
              tooltip: i18n.t(zhHans: '下一项', en: 'Next match'),
              onPressed: matches == 0 ? null : () => onStep(1),
              icon: Icon(Icons.keyboard_arrow_down_rounded,
                  color: AiPalette.primary(dark))),
        ],
        if (!searching) ...[
          IconButton(
              tooltip: i18n.t(zhHans: '搜索此对话', en: 'Search this chat'),
              onPressed: onSearch,
              icon: Icon(Icons.search_rounded, color: AiPalette.primary(dark))),
          if (onOverflow != null)
            IconButton(
                tooltip: i18n.t(zhHans: '更多', en: 'More'),
                onPressed: onOverflow,
                icon: Icon(Icons.more_horiz_rounded,
                    color: AiPalette.primary(dark))),
        ],
      ],
      bottom: PreferredSize(
          preferredSize: const Size.fromHeight(AiMetrics.headerDividerHeight),
          child: SizedBox(
              height: AiMetrics.headerDividerHeight,
              child: ColoredBox(color: AiPalette.line(dark)))),
    );
  }
}
