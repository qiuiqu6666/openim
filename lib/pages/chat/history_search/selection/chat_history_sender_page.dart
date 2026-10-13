import 'dart:async';

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
import 'chat_history_sender_preloader.dart';
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
  final _directory = ChatHistorySenderDirectory();
  var _itemScroll = ItemScrollController();
  var _itemPositions = ItemPositionsListener.create();
  int _directoryVersion = 0;
  late final ChatHistorySenderSource _source;
  late final String _ownerID;
  late final ContactsLogic? _contacts;
  final _registeredPresence = <String>{};
  bool _hasPresenceOwner = false, _routeActive = true, _appActive = true;
  Timer? _debounce;
  late final ChatHistorySenderPreloader _preloader;
  int _generation = 0, _offset = 0;
  bool _loading = false, _hasMore = true, _failed = false;
  bool _accountChanged = false;

  @override
  void initState() {
    super.initState();
    _source = widget.source ?? OpenIMChatHistorySenderSource();
    _ownerID = _source.currentUserID;
    _preloader = ChatHistorySenderPreloader(
      load: _load,
      canLoad: () =>
          mounted &&
          !_accountChanged &&
          _hasMore &&
          !_loading &&
          !_failed &&
          _debounce?.isActive != true,
    );
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
    _syncPreload();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    _syncPresence();
    _syncPreload();
  }

  void _syncPreload() => _preloader.setActive(_routeActive && _appActive);

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
                _directory[position.index].userID,
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
      _preloader.cancel();
      setState(() {
        _accountChanged = true;
        _directory.clear();
        _resetViewport();
        _loading = false;
        _hasMore = false;
      });
      _syncPresence();
    }
    return false;
  }

  void _searchChanged(String value) {
    _debounce?.cancel();
    _preloader.cancel();
    if (!_checkAccount()) return;
    ++_generation;
    setState(() {
      _directory.clear();
      _resetViewport();
      _offset = 0;
      _hasMore = true;
      _loading = true;
      _failed = false;
    });
    _preloader.resetInteraction();
    _syncPresence();
    _debounce = Timer(_searchDelay, () => _load(replace: true));
  }

  Future<void> _load({bool replace = false}) async {
    if (!mounted || (_loading && !replace) || !_checkAccount()) return;
    final generation = ++_generation;
    var refresh = _directory.isEmpty || _failed;
    void startLoading() {
      _loading = true;
      _failed = false;
    }

    if (refresh) {
      setState(startLoading);
    } else {
      startLoading();
    }
    try {
      final page = await _source.load(
        conversationID: widget.conversationID,
        query: graphemeTrim(_search.text),
        offset: _offset,
        count: _pageSize,
      );
      if (!mounted || generation != _generation || !_checkAccount()) return;
      // A request can finish during a drag or after the page is covered. Keep
      // its result pending until the list is idle before appending new rows.
      while (!_preloader.isIdle) {
        if (!await _preloader.waitUntilIdle() ||
            !mounted ||
            generation != _generation ||
            !_checkAccount()) return;
      }
      final added = _directory.addPage(page.items);
      _hasMore = page.hasMore && page.nextOffset > _offset;
      _offset = page.nextOffset;
      if (added) {
        refresh = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && generation == _generation) _syncPresence();
        });
      }
    } catch (_) {
      if (mounted && generation == _generation && _checkAccount()) {
        _failed = true;
        refresh = true;
      }
    } finally {
      if (mounted && generation == _generation) {
        if (refresh) {
          setState(() => _loading = false);
          // Let the newly appended batch paint before continuing.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && generation == _generation) _preloader.schedule();
          });
        } else {
          _loading = false;
        }
      }
    }
  }

  void _resetViewport() {
    _itemPositions.itemPositions.removeListener(_syncPresence);
    _itemPositions = ItemPositionsListener.create();
    _itemPositions.itemPositions.addListener(_syncPresence);
    _itemScroll = ItemScrollController();
    ++_directoryVersion;
  }

  @override
  void dispose() {
    ++_generation;
    _preloader.dispose();
    FriendDisplayPreferences.changes.removeListener(_syncPresence);
    _itemPositions.itemPositions.removeListener(_syncPresence);
    WidgetsBinding.instance.removeObserver(this);
    if (_hasPresenceOwner) _contacts?.setDirectoryPresenceVisible(this, null);
    _registeredPresence.clear();
    _directory.clear();
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
          if (_loading && _directory.isEmpty) const LinearProgressIndicator(),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (event) {
                if (event is ScrollStartNotification) {
                  _preloader.setScrolling(true);
                  if (event.dragDetails != null) {
                    FocusScope.of(context).unfocus();
                  }
                } else if (event is ScrollEndNotification) {
                  _preloader.setScrolling(false);
                }
                return false;
              },
              child: _directory.isEmpty
                  ? Align(
                      alignment: Alignment.topCenter, child: _footer(context))
                  : Column(children: [
                      Expanded(
                        child: Listener(
                          onPointerDown: (event) => _preloader
                              .pointerChanged(event.pointer, down: true),
                          onPointerUp: (event) => _preloader
                              .pointerChanged(event.pointer, down: false),
                          onPointerCancel: (event) => _preloader
                              .pointerChanged(event.pointer, down: false),
                          child: _buildDirectory(context),
                        ),
                      ),
                      _footer(context),
                    ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildDirectory(BuildContext context) {
    return ScrollablePositionedList.builder(
      key: ValueKey('chat-history-sender-list-$_directoryVersion'),
      itemCount: _directory.length,
      itemScrollController: _itemScroll,
      itemPositionsListener: _itemPositions,
      padding: EdgeInsets.zero,
      itemBuilder: (context, index) {
        final member = _directory[index];
        return ListenableBuilder(
            key: ValueKey(member.userID),
            listenable: FriendDisplayPreferences.changes,
            builder: (_, __) => _contacts == null
                ? _buildMember(context, member)
                : Obx(() => _buildMember(context, member)));
      },
    );
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
    if (_loading) return const SizedBox.shrink();
    if (_accountChanged) {
      return Padding(
        padding: const EdgeInsets.all(AppTokens.s7),
        child: Text(chatHistorySearchText(context, 'accountChanged'),
            textAlign: TextAlign.center),
      );
    }
    if (_failed) {
      return TextButton(
        key: const ValueKey('chat-history-sender-retry'),
        onPressed: _load,
        child: Text(chatHistorySearchText(context, 'membersFailed')),
      );
    }
    if (_directory.isEmpty && !_hasMore) {
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
