import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'package:openim/pages/contacts/add_by_search/add_by_search_logic.dart';
import 'package:openim/routes/app_navigator.dart';
import '../global_search_logic.dart';

/// Explicit handoff; global search never queries strangers or joins a group.
class GlobalSearchAddActions extends StatelessWidget {
  const GlobalSearchAddActions({super.key, required this.logic});
  final GlobalSearchLogic logic;

  @override
  Widget build(BuildContext context) {
    final keyword = logic.query.value.trim();
    bool matches(String? id) => id != null && id == keyword;
    final knownUser = logic.contactsList.any((item) => matches(item.userID)) ||
        logic.conversations.any((item) => matches(item.userID)) ||
        (normalizePublicAccountSearch(keyword) != null &&
            logic.contactsList.isNotEmpty);
    final knownGroup = logic.groupList.any((item) => matches(item.groupID)) ||
        logic.conversations.any((item) => matches(item.groupID));
    Widget action(SearchType type) => ListTile(
          key: ValueKey('global-search-add-${type.name}'),
          leading: Icon(type == SearchType.user
              ? Icons.person_add_alt_1_outlined
              : Icons.group_add_outlined),
          title: Text((type == SearchType.user
                  ? 'globalSearchAddUser'
                  : 'globalSearchAddGroup')
              .tr),
          subtitle: Text(keyword, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () {
            logic.focusNode.unfocus();
            AppNavigator.startAddContactsBySearch(
                searchType: type, initialQuery: keyword);
          },
        );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (!knownUser && !logic.failures.contains(1)) action(SearchType.user),
      if (!knownGroup && !logic.failures.contains(2)) action(SearchType.group),
    ]);
  }
}
