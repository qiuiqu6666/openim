import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../../../mine/settings/widgets/settings_widgets.dart';
import '../data/fund_transfer_recipient_source.dart';
import '../data/fund_transfer_recipient_policy.dart';
import 'fund_transfer_friend_picker_tokens.dart';

typedef FundTransferFriendsLoader = Future<List<ISUserInfo>> Function(
    int offset, int count);
typedef FundTransferFriendAccountLoader = Future<String?> Function(
    String userID);

/// Selects one actual friend. A public account only changes the displayed
/// identity; the SDK user ID is always returned as the payment recipient.
class FundTransferFriendPicker extends StatefulWidget {
  const FundTransferFriendPicker({
    super.key,
    this.friendsLoader,
    this.ownerProvider,
    this.tokenProvider,
    this.serverProvider,
    this.accountLoader,
  });

  final FundTransferFriendsLoader? friendsLoader;
  final String Function()? ownerProvider;
  final String? Function()? tokenProvider;
  final String Function()? serverProvider;
  final FundTransferFriendAccountLoader? accountLoader;

  @override
  State<FundTransferFriendPicker> createState() =>
      _FundTransferFriendPickerState();
}

class _FundTransferFriendPickerState extends State<FundTransferFriendPicker> {
  final _search = TextEditingController();
  final _friends = <ISUserInfo>[];
  late final (String, String?, String) _scope;
  late final ContactCardProfileResolver _profileResolver;
  int _version = 0;
  bool _loading = true;
  bool _failed = false;
  bool _expired = false;
  String? _selecting;

  (String, String?, String) get _session => (
        widget.ownerProvider?.call() ?? DataSp.userID ?? '',
        widget.tokenProvider == null
            ? DataSp.chatToken
            : widget.tokenProvider!(),
        widget.serverProvider?.call() ?? Config.appAuthUrl,
      );

  bool get _current {
    if (_expired) return false;
    if (_scope.$1.trim().isEmpty ||
        _scope.$2?.isNotEmpty != true ||
        _scope.$3.trim().isEmpty ||
        _scope != _session) {
      _expired = true;
      return false;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    _scope = _session;
    _profileResolver = ContactCardProfileResolver(
      currentUserID: () => _session.$1,
      currentToken: () => _session.$2,
    );
    unawaited(_load());
  }

  bool _accept(int version) {
    if (!mounted || version != _version) return false;
    if (_current) return true;
    setState(() {
      _friends.clear();
      _loading = false;
      _selecting = null;
    });
    return false;
  }

  Future<List<ISUserInfo>> _sdkFriends(int offset, int count) async {
    if (!_current || OpenIM.iMManager.userID != _scope.$1) {
      _expired = true;
      throw StateError('The friend session changed');
    }
    final page = await OpenIM.iMManager.friendshipManager.getFriendListPage(
      offset: offset,
      count: count,
      filterBlack: true,
    );
    if (!_current || OpenIM.iMManager.userID != _scope.$1) {
      _expired = true;
      throw StateError('The friend session changed');
    }
    return page
        .map((friend) => ISUserInfo.fromJson({
              ...friend.toJson(),
              'userID': friend.ownerUserID?.trim().isNotEmpty == true &&
                      friend.ownerUserID?.trim() != _scope.$1
                  ? ''
                  : friend.userID?.trim().isNotEmpty == true
                      ? friend.userID
                      : friend.friendUserID,
            }))
        .toList(growable: false);
  }

  Future<void> _load() async {
    if (!mounted || (_loading && _version > 0)) return;
    if (!_current) {
      _accept(_version);
      return;
    }
    final version = ++_version;
    setState(() {
      _loading = true;
      _failed = false;
    });
    if (!_accept(version)) return;
    try {
      final staged = <String, ISUserInfo>{};
      var offset = 0;
      for (;;) {
        final page = await (widget.friendsLoader ?? _sdkFriends)(
            offset, FundTokens.memberPageSize);
        if (!_accept(version)) return;
        for (final friend in page) {
          final id = friend.userID?.trim() ?? '';
          if (id == _scope.$1 ||
              friend.isBlacklist ||
              !FundTransferRecipientPolicy.allowsUser(
                  userID: id, ex: friend.ex)) {
            continue;
          }
          if (staged.containsKey(id)) continue;
          // SDK friend records do not contain a public account. Reuse a known
          // profile account without issuing a profile request for every row.
          final account = friend.account?.trim() ?? '';
          final cached = account.isEmpty ? _profileResolver.peek(id) : null;
          staged[id] = ISUserInfo.fromJson({
            ...friend.toJson(),
            'userID': id,
            'account': account.isEmpty ? cached ?? '' : account,
          });
        }
        offset += page.length;
        if (page.length < FundTokens.memberPageSize) break;
      }
      final friends = staged.values.toList()
        ..sort((a, b) => _name(a).compareTo(_name(b)));
      if (!_accept(version)) return;
      setState(() {
        _friends
          ..clear()
          ..addAll(friends);
        _loading = false;
      });
    } catch (_) {
      if (!_accept(version)) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  String _name(ISUserInfo friend) {
    for (final name in [friend.remark, friend.nickname, friend.account]) {
      if (name?.trim().isNotEmpty == true) return name!.trim();
    }
    return settingsText(context, zh: '好友', en: 'Friend');
  }

  bool _matches(ISUserInfo friend) {
    final query =
        _search.text.trim().replaceFirst(RegExp(r'^@'), '').toLowerCase();
    return query.isEmpty ||
        [friend.nickname, friend.remark, friend.account]
            .any((value) => value?.toLowerCase().contains(query) == true);
  }

  Future<void> _select(ISUserInfo friend) async {
    if (_selecting != null || !_accept(_version)) return;
    final id = friend.userID?.trim() ?? '';
    if (id == _scope.$1 ||
        !FundTransferRecipientPolicy.allowsUser(userID: id, ex: friend.ex)) {
      return;
    }
    final version = _version;
    setState(() => _selecting = id);
    var account = friend.account?.trim() ?? '';
    if (account.isEmpty) {
      try {
        account = (await (widget.accountLoader ?? _profileResolver.resolve)(id))
                ?.trim() ??
            '';
      } catch (_) {
        // A missing optional profile account must not replace the actual ID
        // or prevent selecting this already verified friend.
      }
    }
    if (!mounted || !_accept(version)) return;
    Navigator.of(context).pop(FundTransferRecipient(
      userID: id,
      nickname: _name(friend),
      faceURL: friend.faceURL?.trim() ?? '',
      account: account,
    ));
  }

  @override
  void dispose() {
    ++_version;
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = FundTransferFriendPickerColors.of(context);
    final current = _current;
    final friends =
        current ? _friends.where(_matches).toList() : <ISUserInfo>[];
    final theme = Theme.of(context);
    return Theme(
        data: theme.copyWith(
            splashColor: colors.hover,
            highlightColor: colors.hover,
            textSelectionTheme: theme.textSelectionTheme.copyWith(
                cursorColor: colors.accent,
                selectionColor: colors.accent.withValues(
                    alpha: FundTransferFriendPickerTokens.selectionOpacity),
                selectionHandleColor: colors.accent)),
        child: Scaffold(
          key: const ValueKey('fund-transfer-friend-picker'),
          backgroundColor: colors.page,
          appBar: GlassAppBar(
            toolbarHeight: kToolbarHeight,
            backgroundColor: colors.page,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: true,
            systemOverlayStyle: AppSystemBars.styleFor(colors.page),
            leading: IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              icon: Icon(Icons.arrow_back_ios_new_rounded,
                  color: colors.accent, size: FundTokens.memberBackIconSize),
              onPressed: () => Navigator.of(context).pop(),
            ),
            title: Text(
              settingsText(context, zh: '选择收款人', en: 'Select recipient'),
              style: TextStyle(
                  color: colors.text,
                  fontSize: FundTokens.memberToolbarTitleFontSize,
                  fontWeight: FontWeight.w600),
            ),
          ),
          body: SafeArea(
            top: false,
            child: Column(children: [
              SearchBox(
                key: const ValueKey('fund-transfer-friend-search'),
                controller: _search,
                enabled: current && !_loading,
                height: (MediaQuery.textScalerOf(context)
                            .scale(FundTokens.memberSearchFontSize) +
                        AppTokens.s6)
                    .clamp(FundTokens.memberSearchHeight, double.infinity),
                borderRadius:
                    BorderRadius.circular(FundTokens.memberSearchRadius),
                margin: const EdgeInsets.fromLTRB(
                    AppTokens.s5, AppTokens.s2, AppTokens.s5, AppTokens.s3),
                padding: const EdgeInsets.symmetric(
                    horizontal: FundTokens.memberSearchRadius),
                backgroundColor: colors.searchFill,
                textStyle: TextStyle(
                    fontSize: FundTokens.memberSearchFontSize,
                    color: colors.text),
                hintStyle: TextStyle(
                    fontSize: FundTokens.memberSearchFontSize,
                    color: colors.secondary),
                searchIconColor: colors.secondary,
                searchIcon: Icon(Icons.search_rounded,
                    color: colors.secondary,
                    size: FundTokens.memberSearchIconSize),
                clearIcon: Icon(Icons.cancel_rounded,
                    color: colors.secondary,
                    size: FundTokens.memberSearchIconSize),
                searchIconWidth: FundTokens.memberSearchIconSize,
                searchIconHeight: FundTokens.memberSearchIconSize,
                hintText: settingsText(context,
                    zh: '搜索昵称或公开账号', en: 'Search name or public account'),
                onChanged: (_) => setState(() {}),
                onCleared: () => setState(() {}),
              ),
              if (current && (_loading || _selecting != null))
                LinearProgressIndicator(
                    key: const ValueKey('fund-transfer-friend-loading'),
                    color: colors.accent,
                    backgroundColor: colors.searchFill),
              Expanded(
                child: !current
                    ? _message(colors, '账户已切换，请重新打开',
                        'Account changed. Please reopen.')
                    : _failed
                        ? Center(
                            child: TextButton(
                              key: const ValueKey('fund-transfer-friend-retry'),
                              style: TextButton.styleFrom(
                                  foregroundColor: colors.actionText),
                              onPressed: _loading ? null : _load,
                              child: Text(settingsText(context,
                                  zh: '好友加载失败，请重试',
                                  en: 'Could not load friends. Please retry.')),
                            ),
                          )
                        : !_loading && friends.isEmpty
                            ? _message(colors, '未找到相关好友', 'No matching friends')
                            : ListView.separated(
                                key:
                                    const ValueKey('fund-transfer-friend-list'),
                                itemCount: friends.length,
                                separatorBuilder: (_, __) => Divider(
                                    height: FundTransferFriendPickerTokens
                                        .dividerHeight,
                                    thickness: FundTransferFriendPickerTokens
                                        .dividerHeight,
                                    indent: FundTransferFriendPickerTokens
                                        .dividerStart,
                                    endIndent: FundTransferFriendPickerTokens
                                        .dividerEnd,
                                    color: colors.separator),
                                itemBuilder: (_, index) {
                                  final friend = friends[index];
                                  final name = _name(friend);
                                  final account = friend.account?.trim() ?? '';
                                  return ListTile(
                                    key: ValueKey(
                                        'fund-transfer-friend-${friend.userID}'),
                                    tileColor: colors.page,
                                    hoverColor: colors.hover,
                                    leading: AvatarView(
                                      url: friend.faceURL,
                                      text: name,
                                      width: FundTokens.memberAvatarSize,
                                      height: FundTokens.memberAvatarSize,
                                      isCircle: true,
                                    ),
                                    title: Text(name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: colors.text,
                                            fontSize: FundTokens
                                                .memberTitleFontSize)),
                                    subtitle: account.isEmpty
                                        ? null
                                        : Text(
                                            account.startsWith('@')
                                                ? account
                                                : '@$account',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                color: colors.secondary,
                                                fontSize:
                                                    AppTokens.captionFontSize)),
                                    enabled: _selecting == null,
                                    onTap: () => unawaited(_select(friend)),
                                  );
                                },
                              ),
              ),
            ]),
          ),
        ));
  }

  Widget _message(
          FundTransferFriendPickerColors colors, String zh, String en) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.s7),
          child: Text(settingsText(context, zh: zh, en: en),
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: colors.secondary,
                  fontSize: AppTokens.captionFontSize)),
        ),
      );
}
