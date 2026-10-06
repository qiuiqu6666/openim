import 'package:azlistview/azlistview.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../contacts_logic.dart';
import '../friend_list/friend_list_logic.dart';
import '../select_contacts_logic.dart';
import 'contact_card_friend_directory.dart';
import 'contact_card_friend_row.dart';
import 'contact_card_picker_tokens.dart';
import 'contact_card_presence_visibility.dart';

/// Single-contact picker for the existing personal card confirmation flow.
class ContactCardFriendPicker extends StatefulWidget {
  const ContactCardFriendPicker({
    super.key,
    required this.friends,
    required this.selection,
  });

  final SelectContactsFromFriendsLogic friends;
  final SelectContactsLogic selection;

  @override
  State<ContactCardFriendPicker> createState() =>
      _ContactCardFriendPickerState();
}

class _ContactCardFriendPickerState extends State<ContactCardFriendPicker>
    with WidgetsBindingObserver {
  final _search = TextEditingController();
  final _focus = FocusNode();
  final _visible = <Object, String>{};
  final _registered = <String>{};
  late final ContactsLogic? _contacts;
  String _query = '';
  bool _routeActive = true;
  bool _appActive = true;
  bool _disposing = false;
  bool _hasPresenceOwner = false;

  @override
  void initState() {
    super.initState();
    _contacts =
        Get.isRegistered<ContactsLogic>() ? Get.find<ContactsLogic>() : null;
    _appActive = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    FriendDisplayPreferences.changes.addListener(_syncPresence);
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

  void _setVisibility(Object rowOwner, String id, bool shown) {
    if (_disposing || !mounted) return;
    if (shown) {
      _visible[rowOwner] = id;
    } else {
      _visible.remove(rowOwner);
    }
    _syncPresence();
  }

  void _syncPresence() {
    final contacts = _contacts;
    if (contacts == null || contacts.isClosed) return;
    final enabled = !_disposing &&
        _routeActive &&
        _appActive &&
        contacts.isCurrentSession &&
        FriendDisplayPreferences.showOnlineStatus;
    final next = enabled ? _visible.values.toSet() : const <String>{};
    if (_hasPresenceOwner &&
        next.length == _registered.length &&
        _registered.containsAll(next)) {
      return;
    }
    contacts.setDirectoryPresenceVisible(this, Set<String>.unmodifiable(next));
    _hasPresenceOwner = true;
    _registered
      ..clear()
      ..addAll(next);
  }

  @override
  void dispose() {
    _disposing = true;
    FriendDisplayPreferences.changes.removeListener(_syncPresence);
    WidgetsBinding.instance.removeObserver(this);
    if (_hasPresenceOwner) _contacts?.setDirectoryPresenceVisible(this, null);
    _registered.clear();
    _visible.clear();
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _searchChanged(String value) {
    final next = value.trim().toLowerCase();
    if (_query != next) setState(() => _query = next);
  }

  void _cancel() {
    _focus.unfocus();
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: FriendDisplayPreferences.changes,
        builder: (context, _) => Scaffold(
          key: const ValueKey('contact-card-friend-picker'),
          backgroundColor: ContactCardPickerTokens.pageBackground(context),
          appBar: GlassAppBar(
            backgroundColor: ContactCardPickerTokens.pageBackground(context),
            centerTitle: true,
            title: Text('contactCardChooseFriend'.tr,
                style: ContactCardPickerTokens.headingStyle(context)),
            leading: IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: _cancel,
              icon: const Icon(CupertinoIcons.back, color: AppTokens.accent),
            ),
          ),
          body: SafeArea(
            top: false,
            child: Column(children: [
              _buildSearch(context),
              Expanded(child: Obx(() => _buildDirectory(context))),
            ]),
          ),
        ),
      );

  Widget _buildSearch(BuildContext context) => Padding(
        padding: ContactCardPickerTokens.searchPadding,
        child: Row(children: [
          Expanded(
            child: SearchBox(
              key: const ValueKey('contact-card-search'),
              controller: _search,
              focusNode: _focus,
              enabled: true,
              height: ContactCardPickerTokens.searchHeight(context),
              borderRadius:
                  BorderRadius.circular(ContactCardPickerTokens.searchRadius),
              padding: const EdgeInsets.symmetric(
                  horizontal: ContactCardPickerTokens.searchHorizontalPadding),
              backgroundColor:
                  ContactCardPickerTokens.searchBackground(context),
              textStyle: ContactCardPickerTokens.searchStyle(context),
              hintStyle:
                  ContactCardPickerTokens.searchStyle(context, hint: true),
              searchIconColor: ContactCardPickerTokens.secondary(context),
              searchIconWidth: ContactCardPickerTokens.searchIconSize,
              searchIconHeight: ContactCardPickerTokens.searchIconSize,
              onChanged: _searchChanged,
              onCleared: () => _searchChanged(''),
            ),
          ),
          const SizedBox(width: ContactCardPickerTokens.cancelGap),
          TextButton(
            key: const ValueKey('contact-card-cancel'),
            onPressed: _cancel,
            style: TextButton.styleFrom(
              minimumSize: const Size(ContactCardPickerTokens.searchMinHeight,
                  ContactCardPickerTokens.searchMinHeight),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: ContactCardPickerTokens.primary(context),
            ),
            child: Text(StrRes.cancel,
                style: ContactCardPickerTokens.cancelStyle(context)),
          ),
        ]),
      );

  Widget _buildDirectory(BuildContext context) {
    final starredAt = <String, int>{
      if (_contacts != null)
        for (final entry in _contacts.stars.records.entries)
          if (entry.value.starred) entry.key: entry.value.updatedAt,
    };
    final data = buildContactCardFriendDirectory(widget.friends.friendList,
        query: _query, starredAt: starredAt);
    if (data.isEmpty) {
      return Center(
        key: const ValueKey('contact-card-empty'),
        child: Text(
            (_query.isEmpty
                    ? 'contactCardNoContacts'
                    : 'contactCardNoMatchingContacts')
                .tr,
            style: ContactCardPickerTokens.secondaryStyle(context,
                size: ContactCardPickerTokens.emptySize)),
      );
    }
    final sectionHeight = ContactCardPickerTokens.sectionHeight(context);
    return AzListView(
      key: const ValueKey('contact-card-index'),
      data: data,
      itemCount: data.length,
      itemBuilder: (_, index) => _buildFriend(data[index]),
      physics: const BouncingScrollPhysics(),
      susItemHeight: sectionHeight,
      susItemBuilder: (_, index) {
        final tag = data[index].getSuspensionTag();
        return Container(
          key: ValueKey('contact-card-section-$tag'),
          height: sectionHeight,
          color: ContactCardPickerTokens.pageBackground(context),
          padding: const EdgeInsets.only(
              left: ContactCardPickerTokens.horizontalPadding),
          alignment: Alignment.centerLeft,
          child: Text(tag,
              style: ContactCardPickerTokens.secondaryStyle(context,
                      size: ContactCardPickerTokens.sectionSize)
                  .copyWith(
                color: ContactCardPickerTokens.secondary(context)
                    .withValues(alpha: ContactCardPickerTokens.indexOpacity),
              )),
        );
      },
      indexBarData: SuspensionUtil.getTagIndexList(data),
      indexBarWidth: ContactCardPickerTokens.indexBarWidth,
      indexBarItemHeight: ContactCardPickerTokens.indexHeight(context),
      indexBarMargin: const EdgeInsets.only(
          right: ContactCardPickerTokens.indexRightMargin),
      indexBarOptions: directoryIndexBarOptions(
        accentColor: AppTokens.accent,
        highlightSelection: true,
        hapticFeedback: true,
        textStyle: ContactCardPickerTokens.secondaryStyle(context,
                size: ContactCardPickerTokens.indexSize)
            .copyWith(
          color: ContactCardPickerTokens.secondary(context)
              .withValues(alpha: ContactCardPickerTokens.indexOpacity),
        ),
        selectTextStyle: ContactCardPickerTokens.secondaryStyle(context,
                size: ContactCardPickerTokens.indexSize)
            .copyWith(color: AppTokens.onAccent),
      ),
    );
  }

  Widget _buildFriend(ISUserInfo friend) {
    final id = friend.userID!;
    Widget row() => ContactCardFriendRow(
          friend: friend,
          presence: _contacts?.presence.users[id],
          starred: friend.tagIndex == '★',
          onTap: widget.selection.isDefaultChecked(friend)
              ? null
              : () {
                  _focus.unfocus();
                  widget.selection.onTap(friend)?.call();
                },
        );
    return ContactCardPresenceVisibility(
      key: ValueKey('contact-card-presence-row-$id'),
      userID: id,
      onVisibilityChanged: _setVisibility,
      child: _contacts == null ? row() : Obx(row),
    );
  }
}
