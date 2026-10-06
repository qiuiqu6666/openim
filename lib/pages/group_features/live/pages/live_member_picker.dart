import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import '../../models/group_feature_context.dart';
import '../widgets/live_style.dart';

class LiveMemberPicker extends StatefulWidget {
  const LiveMemberPicker({super.key, required this.featureContext});
  final GroupFeatureContext featureContext;
  @override
  State<LiveMemberPicker> createState() => _LiveMemberPickerState();
}

class _LiveMemberPickerState extends State<LiveMemberPicker> {
  final _search = TextEditingController();
  final _members = <GroupMembersInfo>[];
  Timer? _debounce;
  bool _loading = false, _more = true;
  Object? _error;
  int _generation = 0, _offset = 0;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load({bool reset = false}) async {
    if (!widget.featureContext.sessionCurrent() || (_loading && !reset)) return;
    final generation = reset ? ++_generation : _generation;
    if (reset) {
      _offset = 0;
      _members.clear();
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final keyword = _search.text.trim();
      final page = keyword.isEmpty
          ? await OpenIM.iMManager.groupManager.getGroupMemberList(
              groupID: widget.featureContext.groupID,
              offset: _offset,
              count: 50)
          : await OpenIM.iMManager.groupManager.searchGroupMembers(
              groupID: widget.featureContext.groupID,
              keywordList: [keyword],
              isSearchUserID: true,
              isSearchMemberNickname: true,
              offset: _offset,
              count: 50);
      if (!mounted ||
          generation != _generation ||
          !widget.featureContext.sessionCurrent()) {
        return;
      }
      setState(() {
        final known = _members.map((m) => m.userID).toSet();
        _members.addAll(page.where((m) => known.add(m.userID)));
        _offset += page.length;
        _more = page.length == 50;
      });
    } catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _searchChanged(String _) {
    _debounce?.cancel();
    ++_generation;
    _debounce =
        Timer(const Duration(milliseconds: 300), () => _load(reset: true));
  }

  @override
  void dispose() {
    ++_generation;
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      backgroundColor: LiveStyle.card(context),
      appBar: AppBar(
          leading: const LiveBackButton(),
          title: const Text('选择主播'),
          backgroundColor: LiveStyle.card(context)),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
                controller: _search,
                onChanged: _searchChanged,
                decoration: InputDecoration(
                    hintText: '搜索群成员',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: LiveStyle.field(context),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none)))),
        Expanded(
            child: _error != null && _members.isEmpty
                ? Center(
                    child: LiveError(
                        error: _error!, retry: () => _load(reset: true)))
                : ListView.builder(
                    itemCount: _members.length + 1,
                    itemBuilder: (context, index) {
                      if (index == _members.length) {
                        return Padding(
                            padding: const EdgeInsets.all(16),
                            child: _loading
                                ? const Center(
                                    child: CircularProgressIndicator())
                                : _error != null
                                    ? LiveError(
                                        error: _error!, retry: () => _load())
                                    : _more
                                        ? TextButton(
                                            onPressed: () => _load(),
                                            child: const Text('加载更多'))
                                        : _members.isEmpty
                                            ? const Center(
                                                child: Text('没有找到群成员'))
                                            : const SizedBox.shrink());
                      }
                      final member = _members[index];
                      final name = member.nickname?.trim().isNotEmpty == true
                          ? member.nickname!
                          : member.userID ?? '';
                      return Column(children: [
                        ListTile(
                            leading: AvatarView(
                                width: 44,
                                height: 44,
                                text: name,
                                url: member.faceURL),
                            title: Text(name,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle:
                                Text(member.roleLevel == GroupRoleLevel.owner
                                    ? '群主'
                                    : member.roleLevel == GroupRoleLevel.admin
                                        ? '管理员'
                                        : '群成员'),
                            onTap: () {
                              if (widget.featureContext.sessionCurrent()) {
                                Navigator.of(context).pop(member);
                              }
                            }),
                        if (index + 1 < _members.length)
                          Padding(
                              padding: const EdgeInsets.only(left: 74),
                              child: Divider(
                                  height: 1,
                                  thickness: .5,
                                  color: AppTokens.border(
                                      dark: LiveStyle.dark(context))))
                      ]);
                    })),
      ]));
}
