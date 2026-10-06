import 'dart:async';
import 'dart:math' as math;

import 'package:azlistview/azlistview.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../chat_history_search_strings.dart';
import '../chat_history_search_tokens.dart';
import '../../../contacts/contacts_logic.dart';
import '../../../contacts/presence/contact_presence_policy.dart';
import '../../../contacts/presence_label.dart';
import 'chat_history_sender_directory.dart';
import 'chat_history_sender_source.dart';

class ChatHistorySenderPage extends StatefulWidget {
  const ChatHistorySenderPage({
    super.key,
    required this.conversationID,
    this.source,
  });

  final String conversationID;
  final ChatHistorySenderSource? source;

  @override
  State<ChatHistorySenderPage> createState() => _ChatHistorySenderPageState();
}

class _ChatHistorySenderPageState extends State<ChatHistorySenderPage>
    with WidgetsBindingObserver {
  static const _pageSize = 50;
  static const _searchDelay = Duration(milliseconds: 300);
  final _search = TextEditingController();
  final _members = <ChatHistorySender>[];
  List<ChatHistorySenderRow> _directory = [];
  final _itemScroll = ItemScrollController();
  final _itemPositions = ItemPositionsListener.create();
  int _directoryVersion = 0;
  late final ChatHistorySenderSource _source;
  late final String _ownerID;
  late final ContactsLogic? _contacts;
  final _registeredPresence = <String>{};
  bool _hasPresenceOwner = false, _routeActive = true, _appActive = true;
  Timer? _debounce;
  int _generation = 0, _offset = 0;
  bool _loading = false, _hasMore = true, _failed = false;
  bool _accountChanged = false;

  @override
  void initState() {
    super.initState();
    _source = widget.source ?? OpenIMChatHistorySenderSource();
    _ownerID = _source.currentUserID;
    _contacts =
        Get.isRegistered<ContactsLogic>() ? Get.find<ContactsLogic>() : null;
    _appActive = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    FriendDisplayPreferences.changes.addListener(_syncPresence);
    _itemPositions.itemPositions.addListener(_syncPresence);
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeActive = (ModalRoute.isCurrentOf(context) ?? true) &&
        TickerMode.valuesOf(context).enabled;
    _syncPresence();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    _syncPresence();
  }

  bool get _canReadPresence =>
      !_accountChanged &&
      _source.currentUserID == _ownerID &&
      _contacts != null &&
      !_contacts.isClosed &&
      _contacts.isCurrentSession &&
      FriendDisplayPreferences.showOnlineStatus;

  void _syncPresence() {
    final contacts = _contacts;
    if (contacts == null || contacts.isClosed) return;
    final ids = _routeActive && _appActive && _canReadPresence
        ? {
            for (final position in _itemPositions.itemPositions.value)
              if (position.itemLeadingEdge < 1 &&
                  position.itemTrailingEdge > 0 &&
                  position.index >= 0 &&
                  position.index < _directory.length)
                _directory[position.index].sender.userID,
          }
        : const <String>{};
    if (_hasPresenceOwner &&
        ids.length == _registeredPresence.length &&
        _registeredPresence.containsAll(ids)) {
      return;
    }
    contacts.setDirectoryPresenceVisible(this, Set<String>.unmodifiable(ids));
    _hasPresenceOwner = true;
    _registeredPresence
      ..clear()
      ..addAll(ids);
  }

  bool _checkAccount() {
    if (_ownerID.isNotEmpty && _source.currentUserID == _ownerID) return true;
    if (mounted) {
      ++_generation;
      _debounce?.cancel();
      setState(() {
        _accountChanged = true;
        _members.clear();
        _directory = [];
        ++_directoryVersion;
        _loading = false;
        _hasMore = false;
      });
      _syncPresence();
    }
    return false;
  }

  void _searchChanged(String value) {
    _debounce?.cancel();
    if (!_checkAccount()) return;
    ++_generation;
    setState(() {
      _members.clear();
      _directory = [];
      ++_directoryVersion;
      _offset = 0;
      _hasMore = true;
      _loading = true;
      _failed = false;
    });
    _syncPresence();
    _debounce = Timer(_searchDelay, () => _load(replace: true));
  }

  Future<void> _load({bool replace = false}) async {
    if (!mounted || (_loading && !replace) || !_checkAccount()) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await _source.load(
        conversationID: widget.conversationID,
        query: _search.text.trim(),
        offset: _offset,
        count: _pageSize,
      );
      if (!mounted || generation != _generation || !_checkAccount()) return;
      // New pages may insert letters above the visible row. Keep that sender
      // anchored while refreshing the alphabetical projection.
      final visible = _itemPositions.itemPositions.value
          .where((position) =>
              position.itemTrailingEdge > 0 &&
              position.itemLeadingEdge >= 0 &&
              position.index < _directory.length)
          .toList()
        ..sort((a, b) => a.index.compareTo(b.index));
      final anchor = visible.isEmpty ? null : visible.first;
      final anchorID =
          anchor == null ? null : _directory[anchor.index].sender.userID;
      setState(() {
        _hasMore = page.hasMore && page.nextOffset > _offset;
        _offset = page.nextOffset;
        final seen = _members.map((member) => member.userID).toSet();
        _members.addAll(page.items.where(
            (member) => member.userID.isNotEmpty && seen.add(member.userID)));
        _directory =
            buildChatHistorySenderDirectory(_members, previous: _directory);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _generation) _syncPresence();
      });
      if (anchorID != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              generation != _generation ||
              !_itemScroll.isAttached) {
            return;
          }
          final index =
              _directory.indexWhere((row) => row.sender.userID == anchorID);
          if (index >= 0) {
            _itemScroll.jumpTo(
                index: index,
                alignment: anchor!.itemLeadingEdge.clamp(0.0, 1.0));
          }
        });
      }
    } catch (_) {
      if (mounted && generation == _generation && _checkAccount()) {
        setState(() => _failed = true);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    ++_generation;
    FriendDisplayPreferences.changes.removeListener(_syncPresence);
    _itemPositions.itemPositions.removeListener(_syncPresence);
    WidgetsBinding.instance.removeObserver(this);
    if (_hasPresenceOwner) _contacts?.setDirectoryPresenceVisible(this, null);
    _registeredPresence.clear();
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: GlassAppBar(
        backgroundColor: theme.colorScheme.surface,
        centerTitle: true,
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: Styles.c_0089FF),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(chatHistorySearchText(context, 'chooseSender'),
            style: Styles.ts_0C1C33_17sp_semibold),
      ),
      body: SafeArea(
        top: false,
        child: Column(children: [
          SearchBox(
            key: const ValueKey('chat-history-sender-search'),
            controller: _search,
            enabled: !_accountChanged,
            height: MediaQuery.textScalerOf(context)
                    .scale(AppTokens.listTitleFontSize) +
                AppTokens.s8,
            margin: const EdgeInsets.all(AppTokens.s5),
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.s4),
            borderRadius: BorderRadius.circular(AppTokens.rSm),
            backgroundColor: AppTokens.surfaceAlt(dark: dark),
            textStyle: theme.textTheme.bodyLarge,
            hintStyle: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            searchIconColor: theme.colorScheme.onSurfaceVariant,
            searchIconHeight: AppTokens.chevronSize,
            searchIconWidth: AppTokens.chevronSize,
            hintText: chatHistorySearchText(context, 'searchMembers'),
            onChanged: _searchChanged,
            onCleared: () => _searchChanged(''),
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (event) {
                if (event is ScrollStartNotification &&
                    event.dragDetails != null) {
                  FocusScope.of(context).unfocus();
                }
                if (event is ScrollUpdateNotification &&
                    event.metrics.extentAfter < AppTokens.listItemHeight * 3 &&
                    _hasMore &&
                    !_loading &&
                    !_failed &&
                    _debounce?.isActive != true) {
                  unawaited(_load());
                }
                return false;
              },
              child: _directory.isEmpty
                  ? Align(
                      alignment: Alignment.topCenter, child: _footer(context))
                  : Column(children: [
                      Expanded(child: _buildDirectory(context)),
                      _footer(context),
                    ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildDirectory(BuildContext context) {
    final theme = Theme.of(context);
    final scale = MediaQuery.textScalerOf(context);
    final sectionHeight = scale.scale(AppTokens.captionFontSize) + AppTokens.s5;
    final tags = SuspensionUtil.getTagIndexList(_directory);
    return LayoutBuilder(builder: (context, constraints) {
      final indexHeight = math.min(scale.scale(AppTokens.s4) + AppTokens.s3,
          constraints.maxHeight / tags.length);
      final indexStyle = theme.textTheme.bodySmall;
      final indexFont = math.min(
          AppTokens.s4,
          math.max(1.0, indexHeight - AppTokens.s2) /
              ((scale.scale(AppTokens.s4) / AppTokens.s4) *
                  (indexStyle?.height ?? 1.2)));
      return AzListView(
        key: ValueKey('chat-history-sender-index-$_directoryVersion'),
        data: _directory,
        itemCount: _directory.length,
        itemScrollController: _itemScroll,
        itemPositionsListener: _itemPositions,
        padding: const EdgeInsets.only(right: AppTokens.s8),
        itemBuilder: (context, index) {
          final member = _directory[index].sender;
          return ListenableBuilder(
              listenable: FriendDisplayPreferences.changes,
              builder: (_, __) => _contacts == null
                  ? _buildMember(context, member)
                  : Obx(() => _buildMember(context, member)));
        },
        susItemHeight: sectionHeight,
        susItemBuilder: (_, index) => Container(
          key: ValueKey(
              'chat-history-sender-section-${_directory[index].getSuspensionTag()}'),
          height: sectionHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.s5),
          alignment: AlignmentDirectional.centerStart,
          color:
              AppTokens.surfaceAlt(dark: theme.brightness == Brightness.dark),
          child: Text(_directory[index].getSuspensionTag(),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
        indexBarData: tags,
        indexBarWidth: AppTokens.s8,
        indexBarItemHeight: indexHeight,
        indexBarMargin: const EdgeInsets.only(right: AppTokens.s2),
        indexBarOptions: directoryIndexBarOptions(
          textStyle: indexStyle?.copyWith(
              color: theme.colorScheme.onSurfaceVariant, fontSize: indexFont),
          selectTextStyle: indexStyle?.copyWith(
              color: AppTokens.onAccent, fontSize: indexFont),
          accentColor: AppTokens.accent,
          hapticFeedback: true,
        ),
      );
    });
  }

  Widget _buildMember(BuildContext context, ChatHistorySender member) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    // Read the shared RxMap even while hidden so the row remains subscribed;
    // only expose the cached value for the current account/session/preference.
    final cached = _contacts?.presence.users[member.userID];
    final presence = _canReadPresence
        ? ContactPresencePolicy.resolve(
            userID: member.userID, ex: member.ex, presence: cached)
        : null;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(
        key: ValueKey('chat-history-sender-${member.userID}'),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppTokens.s5),
        leading: AvatarView(
            url: member.faceURL,
            text: member.name,
            width: AppTokens.listItemHeight - AppTokens.s5,
            height: AppTokens.listItemHeight - AppTokens.s5),
        title: Text(member.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(
                fontSize: ChatHistoryFileTokens.titleFontSize,
                fontWeight: FontWeight.w500,
                color: AppTokens.textPrimary(dark: dark))),
        subtitle: presence == null
            ? SizedBox(
                height: MediaQuery.textScalerOf(context)
                    .scale(ChatHistoryFileTokens.timeFontSize))
            : PresenceLabel(
                key: ValueKey('chat-history-sender-presence-${member.userID}'),
                presence: presence,
                textStyle: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: ChatHistoryFileTokens.timeFontSize,
                    color: AppTokens.textSecondary(dark: dark))),
        onTap: () {
          if (_checkAccount()) {
            Navigator.of(context).pop<ChatHistorySender>(member);
          }
        },
      ),
      Divider(
        height: ChatHistorySearchTokens.dividerThickness,
        thickness: ChatHistorySearchTokens.dividerThickness,
        indent: AppTokens.s5 + AppTokens.listItemHeight,
        endIndent: AppTokens.s5,
        color: ChatHistorySearchTokens.divider(dark: dark),
      ),
    ]);
  }

  Widget _footer(BuildContext context) {
    if (_loading) return const SizedBox(height: AppTokens.listItemHeight);
    if (_accountChanged) {
      return Padding(
        padding: const EdgeInsets.all(AppTokens.s7),
        child: Text(chatHistorySearchText(context, 'accountChanged'),
            textAlign: TextAlign.center),
      );
    }
    if (_failed || _hasMore) {
      return TextButton(
        key: ValueKey(
            _failed ? 'chat-history-sender-retry' : 'chat-history-sender-more'),
        onPressed: _load,
        child: Text(chatHistorySearchText(
            context, _failed ? 'membersFailed' : 'loadMore')),
      );
    }
    if (_members.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppTokens.s7),
        child: Text(chatHistorySearchText(context, 'noMembers'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }
    return const SizedBox.shrink();
  }
}
