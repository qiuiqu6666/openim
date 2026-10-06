import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../../services/favorite_repository.dart';
import '../../../favorites/favorite_p0.dart';
import '../../../favorites/widgets/favorite_search_formatter.dart';
import '../../../mine/settings/widgets/settings_widgets.dart';
import '../../../mine/secondary/favorites_page.dart' show favoriteKindLabel;

/// 99chat's compact picker toolbar. Querying remains owned by the collection.
class FavoritePickerFilters extends StatelessWidget {
  const FavoritePickerFilters(
      {super.key,
      required this.search,
      required this.searching,
      required this.onToggleSearch,
      required this.onChanged,
      required this.onSubmitted,
      required this.kind,
      required this.onKind,
      required this.items,
      required this.hasMore,
      required this.disabled,
      required this.onManage});

  final TextEditingController search;
  final bool searching, hasMore, disabled;
  final VoidCallback onToggleSearch, onSubmitted;
  final VoidCallback? onManage;
  final ValueChanged<String> onChanged;
  final ValueChanged<FavoriteKind?> onKind;
  final FavoriteKind? kind;
  final List<FavoriteItem> items;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    String text(String zh, String en) => settingsText(context, zh: zh, en: en);
    final muted = AppTokens.textSecondary(dark: dark);
    final searchBorder = OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.rLg),
        borderSide: BorderSide.none);
    return Column(children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(
              AppTokens.s5, 0, AppTokens.s3, FavoritePickerTokens.cardGap),
          child: Row(children: [
            Expanded(
                child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final type in <FavoriteKind?>[
                        null,
                        ...favoriteP0Kinds
                      ])
                        Padding(
                            padding: const EdgeInsets.only(right: AppTokens.s3),
                            child: ChoiceChip(
                              key: ValueKey(
                                  'favorite-filter-${type?.name ?? 'all'}'),
                              label: Text(
                                  '${type == null ? text('全部', 'All') : favoriteKindLabel(context, type)} (${type == null ? items.length : items.where((item) => item.kind == type).length}${hasMore ? '+' : ''})'),
                              selected: kind == type,
                              showCheckmark: false,
                              onSelected: disabled ? null : (_) => onKind(type),
                              side: BorderSide.none,
                              shape: const StadiumBorder(),
                              backgroundColor:
                                  FavoritePickerTokens.chip(dark: dark),
                              selectedColor:
                                  FavoritePickerTokens.activeChip(dark: dark),
                              labelStyle: TextStyle(
                                  color:
                                      kind == type ? AppTokens.accent : muted,
                                  fontWeight: kind == type
                                      ? FontWeight.w600
                                      : FontWeight.w400),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: FavoritePickerTokens
                                      .chipHorizontalPadding,
                                  vertical: FavoritePickerTokens.sourceGap),
                            )),
                    ]))),
            IconButton(
                key: const ValueKey('favorites-search-toggle'),
                tooltip: text('搜索收藏', 'Search favorites'),
                onPressed: disabled ? null : onToggleSearch,
                icon: Icon(Icons.search_rounded,
                    size: FavoritePickerTokens.toolbarIconSize, color: muted)),
            IconButton(
                key: const ValueKey('favorites-manage'),
                tooltip: text('管理收藏', 'Manage favorites'),
                onPressed: disabled ? null : onManage,
                icon: Icon(Icons.checklist_rounded,
                    size: FavoritePickerTokens.toolbarIconSize, color: muted)),
          ])),
      if (searching)
        Padding(
            padding: const EdgeInsets.fromLTRB(
                AppTokens.s5, 0, AppTokens.s5, AppTokens.s4),
            child: TextField(
              key: const ValueKey('favorites-search'),
              controller: search,
              autofocus: true,
              enabled: !disabled,
              inputFormatters: const [FavoriteSearchFormatter()],
              onChanged: onChanged,
              onSubmitted: (_) => onSubmitted(),
              decoration: InputDecoration(
                  hintText: text('搜索内容或来源', 'Search content or source'),
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  filled: true,
                  fillColor: AppTokens.surfaceAlt(dark: dark),
                  border: searchBorder,
                  enabledBorder: searchBorder,
                  focusedBorder: searchBorder,
                  disabledBorder: searchBorder),
            )),
    ]);
  }
}
