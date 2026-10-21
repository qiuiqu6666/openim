import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../../contacts/select_contacts/select_contacts_logic.dart';
import '../../contacts/select_contacts/friend_list/friend_list_logic.dart';
import '../../contacts/select_contacts/friend_list/group_contact_picker.dart';
import '../models/channel_preview.dart';
import '../presentation/channel_ui.dart';
import 'channel_create_page.dart';

/// Lifecycle adapter only. The UI and directory are the existing group picker.
class ChannelContactPicker extends StatefulWidget {
  const ChannelContactPicker(
      {super.key, this.onCompleted, this.onClose, this.onSubmit});
  final Future<void> Function(ChannelPreview)? onSubmit;
  final ValueChanged<ChannelPreview>? onCompleted;
  final VoidCallback? onClose;
  @override
  State<ChannelContactPicker> createState() => _ChannelContactPickerState();
}

class _ChannelContactPickerState extends State<ChannelContactPicker> {
  late final SelectContactsLogic _selection;
  late final SelectContactsFromFriendsLogic _friends;
  bool _opening = false;
  @override
  void initState() {
    super.initState();
    _selection = SelectContactsLogic.groupPicker(isCurrent: () => mounted)
      ..onStart();
    _friends = SelectContactsFromFriendsLogic(selection: _selection)..onStart();
  }

  @override
  void dispose() {
    _friends.onDelete();
    _selection.onDelete();
    super.dispose();
  }

  Future<void> _next() async {
    if (_opening ||
        !_selection.selectionCurrent ||
        !_selection.enabledConfirmButton) {
      return;
    }
    _opening = true;
    final channel = await channelRoute<ChannelPreview>(
        context,
        ChannelCreatePage(
          onSubmit: widget.onSubmit == null
              ? null
              : (draft) async {
                  if (!_selection.selectionCurrent) {
                    throw StateError('Account changed');
                  }
                  _addContacts(draft);
                  await widget.onSubmit!(draft);
                },
        ));
    _opening = false;
    if (!mounted || !_selection.selectionCurrent) {
      channel?.dispose();
      return;
    }
    if (channel == null) return;
    if (widget.onSubmit == null) _addContacts(channel);
    if (widget.onCompleted != null) {
      widget.onCompleted!(channel);
    } else {
      Navigator.pop(context, channel);
    }
  }

  void _addContacts(ChannelPreview channel) {
    for (final user
        in _selection.checkedList.values.where(_selection.allowsSelection)) {
      final id = SelectContactsLogic.parseID(user);
      if (id == null || id.isEmpty) continue;
      final name = SelectContactsLogic.parseName(user) ?? id;
      channel.selectedContacts[id] = ISUserInfo.fromJson({
        'userID': id,
        'nickname': name,
        'faceURL': SelectContactsLogic.parseFaceURL(user),
      });
      channel.members
          .add(channel.members.contains(name) ? '$name ($id)' : name);
    }
  }

  @override
  Widget build(BuildContext context) => GroupContactPicker(
      friends: _friends,
      selection: _selection,
      onNext: _next,
      onBack: widget.onClose ?? () => Navigator.of(context).pop());
}
