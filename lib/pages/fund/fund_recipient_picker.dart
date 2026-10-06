import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../mine/settings/widgets/settings_widgets.dart';
import 'widgets/fund_page_colors.dart';

typedef FundMemberLoader = Future<List<GroupMembersInfo>> Function(
    String query, int offset, int count);

/// 99chat's PagedGroupRecipientPicker layout with real OpenIM pagination.
/// Source: lib/src/pages/wallet/red_packet/paged_group_recipient_picker.dart.
class FundRecipientPicker extends StatefulWidget {
  const FundRecipientPicker({
    super.key,
    required this.groupID,
    this.memberLoader,
  });
  final String groupID;
  final FundMemberLoader? memberLoader;

  @override
  State<FundRecipientPicker> createState() => _FundRecipientPickerState();
}

class _FundRecipientPickerState extends State<FundRecipientPicker> {
  final _search = TextEditingController();
  final _items = <GroupMembersInfo>[];
  Timer? _debounce;
  int _version = 0, _offset = 0;
  bool _loading = false, _more = true;
  String? _error;
  late final String _ownerID;

  @override
  void initState() {
    super.initState();
    _ownerID = OpenIM.iMManager.userID;
    _load();
  }

  void _searchChanged(String value) {
    _debounce?.cancel();
    ++_version;
    setState(() {
      _items.clear();
      _offset = 0;
      _more = true;
      _loading = true;
      _error = null;
    });
    _debounce = Timer(FundTokens.searchDebounce, () => _load(replace: true));
  }

  Future<void> _load({bool replace = false}) async {
    if (_loading && !replace) return;
    if (OpenIM.iMManager.userID != _ownerID) {
      setState(() {
        _items.clear();
        _loading = false;
        _more = false;
        _error = settingsText(context,
            zh: '账户已切换，请重新打开', en: 'Account changed. Please reopen.');
      });
      return;
    }
    final version = ++_version;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final query = _search.text.trim();
      final members = widget.memberLoader != null
          ? await widget.memberLoader!(
              query, _offset, FundTokens.memberPageSize)
          : query.isEmpty
              ? await OpenIM.iMManager.groupManager.getGroupMemberList(
                  groupID: widget.groupID,
                  filter: 0,
                  offset: _offset,
                  count: FundTokens.memberPageSize,
                )
              : await OpenIM.iMManager.groupManager.searchGroupMembers(
                  groupID: widget.groupID,
                  keywordList: [query],
                  isSearchUserID: false,
                  isSearchMemberNickname: true,
                  offset: _offset,
                  count: FundTokens.memberPageSize,
                );
      if (!mounted ||
          version != _version ||
          OpenIM.iMManager.userID != _ownerID) {
        return;
      }
      setState(() {
        _offset += members.length;
        _more = members.length == FundTokens.memberPageSize;
        final ids = _items.map((m) => m.userID).toSet();
        _items.addAll(members.where((m) =>
            (m.userID ?? '').isNotEmpty &&
            m.userID != OpenIM.iMManager.userID &&
            ids.add(m.userID)));
      });
    } catch (_) {
      if (mounted && version == _version) {
        setState(() => _error = settingsText(context,
            zh: '成员加载失败，请重试', en: 'Could not load members. Please retry.'));
      }
    } finally {
      if (mounted && version == _version) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    ++_version;
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = FundPageColors.of(context);
    return Scaffold(
      backgroundColor: cs.bg,
      appBar: GlassAppBar(
        toolbarHeight: kToolbarHeight,
        backgroundColor: cs.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        systemOverlayStyle: AppSystemBars.styleFor(cs.bg),
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: cs.blue, size: FundTokens.memberBackIconSize),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          settingsText(context, zh: '选择接收人', en: 'Select recipient'),
          style: TextStyle(
              color: cs.text,
              fontSize: FundTokens.memberToolbarTitleFontSize,
              fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(children: [
          SearchBox(
            key: const ValueKey('fund-member-search'),
            controller: _search,
            enabled: true,
            height: (MediaQuery.textScalerOf(context)
                            .scale(FundTokens.memberSearchFontSize) *
                        1.2 +
                    20)
                .clamp(FundTokens.memberSearchHeight, double.infinity),
            borderRadius: BorderRadius.circular(FundTokens.memberSearchRadius),
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            padding: const EdgeInsets.symmetric(
                horizontal: FundTokens.memberSearchRadius),
            backgroundColor: cs.inputFill,
            textStyle: TextStyle(
                fontSize: FundTokens.memberSearchFontSize, color: cs.text),
            hintStyle: TextStyle(
                fontSize: FundTokens.memberSearchFontSize, color: cs.subText),
            searchIconColor: cs.subText,
            searchIconWidth: FundTokens.memberSearchIconSize,
            searchIconHeight: FundTokens.memberSearchIconSize,
            hintText: settingsText(context, zh: '搜索成员', en: 'Search members'),
            onChanged: _searchChanged,
            onCleared: () => _searchChanged(''),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (event) {
                if (event is ScrollUpdateNotification &&
                    event.metrics.extentAfter <
                        FundTokens.memberPaginationThreshold &&
                    _more &&
                    !_loading &&
                    _error == null &&
                    _debounce?.isActive != true) {
                  unawaited(_load());
                }
                return false;
              },
              child: ListView.builder(
                itemCount: _items.length + 1,
                itemBuilder: (_, index) {
                  if (index == _items.length) {
                    if (_loading) {
                      return const SizedBox(
                          height: FundTokens.memberLoadingHeight);
                    }
                    if (_more || _error != null) {
                      return TextButton(
                        onPressed: _load,
                        child: Text(_error == null
                            ? settingsText(context,
                                zh: '加载更多成员', en: 'Load more members')
                            : _error!),
                      );
                    }
                    return _items.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(AppTokens.s7),
                            child: Center(
                                child: Text(
                                    settingsText(context,
                                        zh: '未找到相关成员',
                                        en: 'No matching members'),
                                    style: TextStyle(
                                        color: cs.subText,
                                        fontSize: AppTokens.captionFontSize))),
                          )
                        : const SizedBox.shrink();
                  }
                  final member = _items[index];
                  final name = member.nickname?.isNotEmpty == true
                      ? member.nickname!
                      : settingsText(context, zh: '群成员', en: 'Group member');
                  return ListTile(
                    key: ValueKey('fund-member-${member.userID}'),
                    leading: AvatarView(
                        url: member.faceURL,
                        text: name,
                        width: FundTokens.memberAvatarSize,
                        height: FundTokens.memberAvatarSize,
                        isCircle: true),
                    title: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: cs.text,
                            fontSize: FundTokens.memberTitleFontSize)),
                    onTap: () {
                      if (OpenIM.iMManager.userID == _ownerID) {
                        Navigator.of(context).pop(member);
                      }
                    },
                  );
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
