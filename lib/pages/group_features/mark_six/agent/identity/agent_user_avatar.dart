import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'agent_avatar_directory.dart';

/// Uses the IM identity, never the displayed player number, to resolve a photo.
class AgentUserAvatar extends StatefulWidget {
  const AgentUserAvatar({
    super.key,
    required this.directory,
    required this.item,
    required this.name,
    this.size = 40,
  });

  final AgentAvatarDirectory directory;
  final Map<String, dynamic> item;
  final String name;
  final double size;

  String get userID => _first(['imUserId', 'imUserID', 'userId', 'userID']);
  String get fallbackURL =>
      _first(['avatarUrl', 'avatarURL', 'faceURL', 'faceUrl']);
  String _first(List<String> keys) {
    for (final key in keys) {
      final value = item[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  @override
  State<AgentUserAvatar> createState() => _AgentUserAvatarState();
}

class _AgentUserAvatarState extends State<AgentUserAvatar> {
  String? _url;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AgentUserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.userID != oldWidget.userID ||
        widget.directory != oldWidget.directory) {
      _load();
    }
  }

  void _load() {
    final request = ++_request;
    final directory = widget.directory;
    final userID = widget.userID;
    _url = directory.peek(userID);
    unawaited(directory.resolve(userID).then((url) {
      if (!mounted || request != _request || !directory.current) return;
      setState(() => _url = url);
    }));
  }

  @override
  Widget build(BuildContext context) => AvatarView(
        width: widget.size,
        height: widget.size,
        text: widget.name,
        url: widget.directory.current ? _url ?? widget.fallbackURL : null,
      );
}
