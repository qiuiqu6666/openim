import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../friend_list/friend_list_logic.dart';
import '../friend_list/friend_list_view.dart';
import '../group_list/group_list_logic.dart';
import '../group_list/group_list_view.dart';
import '../select_contacts_logic.dart';

enum ContactSingleSelectionKind { groups, contacts }

/// A lifecycle adapter for the existing group/contact pages, with no separate
/// list UI. Local controllers do not replace another route's Get registrations.
class ContactSingleSelection extends StatefulWidget {
  const ContactSingleSelection({
    super.key,
    required this.title,
    required this.kind,
    required this.isCurrent,
    required this.scopeChanges,
    this.loadGroups,
    this.loadContacts,
  });

  final String title;
  final ContactSingleSelectionKind kind;
  final bool Function() isCurrent;
  final Listenable scopeChanges;
  final Future<List<GroupInfo>> Function()? loadGroups;
  final Future<List<ISUserInfo>> Function()? loadContacts;

  @override
  State<ContactSingleSelection> createState() => _ContactSingleSelectionState();
}

class _ContactSingleSelectionState extends State<ContactSingleSelection> {
  late final SelectContactsLogic _selection;
  SelectContactsFromGroupLogic? _groups;
  SelectContactsFromFriendsLogic? _contacts;
  bool _expired = false;
  bool get _current => mounted && !_expired && widget.isCurrent();

  @override
  void initState() {
    super.initState();
    _selection = SelectContactsLogic.single(
      isCurrent: () => _current,
      onPicked: (value) {
        if (_current) Navigator.of(context).pop(value);
      },
    )..onStart();
    widget.scopeChanges.addListener(_scopeChanged);
    if (widget.kind == ContactSingleSelectionKind.groups) {
      _groups = SelectContactsFromGroupLogic(
          selection: _selection, loadGroups: widget.loadGroups)
        ..onStart();
    } else {
      _contacts = SelectContactsFromFriendsLogic(
          selection: _selection, loadDirectory: widget.loadContacts)
        ..onStart();
    }
  }

  void _scopeChanged() {
    if (!mounted || _expired || _current) return;
    setState(() => _expired = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
    });
  }

  @override
  void dispose() {
    widget.scopeChanges.removeListener(_scopeChanged);
    _expired = true;
    _groups?.onDelete();
    _contacts?.onDelete();
    _selection.onDelete();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_current) return const SizedBox.shrink();
    return _groups != null
        ? SelectContactsFromGroupPage(
            title: widget.title, logic: _groups, selection: _selection)
        : SelectContactsFromFriendsPage(
            title: widget.title, logic: _contacts, selection: _selection);
  }
}
