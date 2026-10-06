import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';

import '../../../models/contact_card/contact_card_identity.dart';
import '../../../services/contact_card/contact_card_profile_resolver.dart';
import '../../contact_card.dart';

/// Keeps public card identity separate from the native target used on tap.
class ContactCardIdentityView extends StatefulWidget {
  const ContactCardIdentityView({
    super.key,
    required this.card,
    required this.isSelf,
    required this.time,
    this.status,
    this.resolver,
  });

  final CardElem card;
  final bool isSelf;
  final String time;
  final Widget? status;
  final ContactCardProfileResolver? resolver;

  @override
  State<ContactCardIdentityView> createState() =>
      _ContactCardIdentityViewState();
}

class _ContactCardIdentityViewState extends State<ContactCardIdentityView> {
  String? _account;
  String _target = '';
  String? _extension;
  int _generation = 0;

  ContactCardProfileResolver get _resolver =>
      widget.resolver ?? ContactCardProfileResolver.shared;

  @override
  void initState() {
    super.initState();
    _refreshIdentity();
  }

  @override
  void didUpdateWidget(covariant ContactCardIdentityView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // SDK elements can be mutated in place; compare captured identity fields.
    if (_target != (widget.card.userID ?? '') ||
        _extension != widget.card.ex ||
        oldWidget.resolver != widget.resolver) {
      _refreshIdentity();
    }
  }

  void _refreshIdentity() {
    final generation = ++_generation;
    _target = widget.card.userID ?? '';
    _extension = widget.card.ex;
    final snapshot = contactCardAccount(_target, _extension);
    _account =
        snapshot ?? _resolver.peek(_target) ?? legacyCardAccount(_target);
    if (snapshot == null && _target.trim().isNotEmpty) {
      unawaited(_resolveAccount(_target, generation));
    }
  }

  Future<void> _resolveAccount(String userID, int generation) async {
    String? resolved;
    try {
      resolved = await _resolver.resolve(userID);
    } catch (_) {
      // A failed optional profile lookup must not interrupt card rendering.
    }
    if (!mounted || generation != _generation) return;
    final account = resolved ?? legacyCardAccount(userID);
    if (_account == account) return;
    setState(() => _account = account);
  }

  @override
  void dispose() {
    ++_generation;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nickname = widget.card.nickname?.trim() ?? '';
    final name = nickname.isNotEmpty && nickname != _target
        ? nickname
        : _account ?? 'personalContactCard'.tr;
    return ContactCardView(
      userID: _account ?? '',
      name: name,
      faceURL: widget.card.faceURL,
      isSelf: widget.isSelf,
      time: widget.time,
      status: widget.status,
      reserveUserIDLine: _account == null,
    );
  }
}
