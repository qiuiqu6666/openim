import 'dart:async';

import 'package:azlistview/azlistview.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/moments_repository.dart';
import '../../contacts/directory/contact_directory_indexer.dart';
import '../moments_widgets.dart';
import 'moments_secondary_layout.dart';

class _IndexedMomentFriend extends ISuspensionBean {
  _IndexedMomentFriend(this.friend, this.index);
  final MomentUser friend;
  final ContactNameIndex index;
  @override
  String getSuspensionTag() => index.tagIndex ?? '#';
}

/// Uses the app's contact indexer for 99chat's alphabetical friend selector.
class MomentsFriendPickerList extends StatefulWidget {
  const MomentsFriendPickerList({
    super.key,
    required this.friends,
    required this.selected,
    required this.onToggle,
    this.showIndex = true,
    this.indexWorker,
  });

  final List<MomentUser> friends;
  final Set<String> selected;
  final ValueChanged<MomentUser> onToggle;
  final bool showIndex;
  final ContactIndexWorker? indexWorker;

  @override
  State<MomentsFriendPickerList> createState() =>
      _MomentsFriendPickerListState();
}

class _MomentsFriendPickerListState extends State<MomentsFriendPickerList> {
  late final ContactDirectoryIndexer _indexer;
  List<_IndexedMomentFriend> _indexed = [];
  List<MomentUser> _sourceFriends = const [];
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _indexer = ContactDirectoryIndexer(worker: widget.indexWorker);
    unawaited(_index());
  }

  @override
  void didUpdateWidget(covariant MomentsFriendPickerList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameFriends(_sourceFriends, widget.friends)) {
      unawaited(_index());
    }
  }

  bool _sameFriends(List<MomentUser> first, List<MomentUser> second) {
    if (first.length != second.length) return false;
    for (var i = 0; i < first.length; i++) {
      if (first[i].userId != second[i].userId ||
          first[i].displayName != second[i].displayName ||
          first[i].avatarUrl != second[i].avatarUrl) {
        return false;
      }
    }
    return true;
  }

  Future<void> _index() async {
    final generation = ++_generation;
    // The next build must never use names or callbacks from a previous list
    // while the worker computes the new account or search results.
    _indexed = [];
    _sourceFriends = List<MomentUser>.of(widget.friends, growable: false);
    final friends = {
      for (final friend in _sourceFriends) friend.userId: friend
    };
    final indices = await _indexer.build([
      for (final friend in _sourceFriends)
        ContactNameIndex(
            userID: friend.userId, displayName: friend.displayName),
    ]);
    if (!mounted || generation != _generation || indices == null) return;
    setState(() => _indexed = [
          for (final index in indices)
            if (friends[index.userID] != null)
              _IndexedMomentFriend(friends[index.userID]!, index)
                ..isShowSuspension = widget.showIndex && index.showHeader,
        ]);
  }

  @override
  void dispose() {
    ++_generation;
    _indexer.close();
    super.dispose();
  }

  Widget _row(MomentUser friend, bool divider) {
    final dark = momentsDark(context);
    final selected = widget.selected.contains(friend.userId);
    return Column(children: [
      Material(
          color: MomentsTheme.card(dark),
          child: Semantics(
              checked: selected,
              child: InkWell(
                  key: ValueKey('moments_privacy_friend_${friend.userId}'),
                  onTap: () => widget.onToggle(friend),
                  child: Padding(
                      padding: MomentsSecondaryLayout.friendInset,
                      child: Row(children: [
                        AvatarView(
                            url: friend.avatarUrl,
                            text: friend.displayName,
                            width: MomentsSecondaryLayout.avatarSize,
                            height: MomentsSecondaryLayout.avatarSize),
                        const SizedBox(width: MomentsSecondaryLayout.avatarGap),
                        Expanded(
                            child: Text(friend.displayName,
                                style: TextStyle(
                                    color: MomentsTheme.text(dark),
                                    fontSize: MomentsSecondaryLayout.nameSize,
                                    fontWeight: FontWeight.w600))),
                        ExcludeSemantics(
                            child: Icon(
                                selected
                                    ? Icons.check_circle_rounded
                                    : Icons.circle_outlined,
                                color: selected
                                    ? MomentsTheme.name(dark)
                                    : MomentsTheme.secondary(dark))),
                      ]))))),
      if (divider)
        Divider(
            height: 0,
            thickness: MomentsSecondaryLayout.friendDividerWidth,
            color: MomentsTheme.border(dark)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final dark = momentsDark(context);
    if (_indexed.isEmpty && widget.friends.isNotEmpty) {
      return _dismissKeyboardOnScroll(ListView.builder(
          itemCount: widget.friends.length,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemBuilder: (_, index) =>
              _row(widget.friends[index], index < widget.friends.length - 1)));
    }
    for (final item in _indexed) {
      item.isShowSuspension = widget.showIndex && item.index.showHeader;
    }
    return _dismissKeyboardOnScroll(AzListView(
        data: _indexed,
        itemCount: _indexed.length,
        itemBuilder: (_, index) => _row(
            _indexed[index].friend,
            index + 1 < _indexed.length &&
                !_indexed[index + 1].isShowSuspension),
        susItemHeight: MomentsSecondaryLayout.sectionLabelHeight,
        susItemBuilder: (_, index) => Container(
            height: MomentsSecondaryLayout.sectionLabelHeight,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(
                horizontal: MomentsSecondaryLayout.pageInset),
            color: MomentsTheme.panel(dark),
            child: Text(_indexed[index].getSuspensionTag(),
                style: TextStyle(
                    color: MomentsTheme.secondary(dark),
                    fontSize: MomentsSecondaryLayout.metadataSize,
                    fontWeight: FontWeight.w600))),
        indexBarData:
            widget.showIndex ? SuspensionUtil.getTagIndexList(_indexed) : [],
        indexBarWidth: widget.showIndex ? 20 : 0,
        indexBarItemHeight: 16,
        indexBarOptions: IndexBarOptions(
            needRebuild: true,
            textStyle:
                TextStyle(fontSize: 11, color: MomentsTheme.secondary(dark)),
            selectTextStyle:
                TextStyle(fontSize: 12, color: MomentsTheme.text(dark)))));
  }

  Widget _dismissKeyboardOnScroll(Widget child) =>
      NotificationListener<ScrollStartNotification>(
        onNotification: (notification) {
          if (notification.dragDetails != null) {
            FocusManager.instance.primaryFocus?.unfocus();
          }
          return false;
        },
        child: child,
      );
}
