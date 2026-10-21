import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'dart:typed_data';
import 'package:openim_common/openim_common.dart';

/// Route-local preview data. Never persisted or passed to the IM SDK.
class ChannelPreview extends ChangeNotifier {
  ChannelPreview(
      {required this.name,
      required this.description,
      this.isPublic = true,
      this.owner = true,
      this.icon = Icons.campaign_outlined,
      this.subscribed = true,
      List<ChannelPost>? posts})
      : posts = posts ?? [];

  String name;
  GroupInfo? createdGroup;
  String description;
  Uint8List? avatar;
  bool restrictSaving = false;
  bool deleted = false;
  bool linkRevoked = false;
  final Map<String, ISUserInfo> selectedContacts = {};
  final List<String> members = ['我'];
  final Set<String> administrators = {'我'};
  final List<String> removedMembers = [];
  final bool owner;
  final IconData icon;
  bool isPublic;
  bool subscribed;
  bool notifications = true;
  bool commentsEnabled = true;
  final List<ChannelPost> posts;

  void update(VoidCallback action) {
    action();
    notifyListeners();
  }

  void publish(String text) {
    if (!owner || text.trim().isEmpty) return;
    update(() => posts.insert(0, ChannelPost(text.trim())));
  }

  void pin(ChannelPost post) {
    if (!owner) return;
    update(() => post.pinned = !post.pinned);
  }

  void react(ChannelPost post) {
    if (!subscribed) return;
    update(() => post.liked = !post.liked);
  }

  void comment(ChannelPost post, String text) {
    if (!subscribed || !commentsEnabled || text.trim().isEmpty) return;
    update(() => post.comments.add(text.trim()));
  }
}

class ChannelPost {
  ChannelPost(this.text, {this.pinned = false});
  final String text;
  final DateTime createdAt = DateTime.now();
  bool pinned;
  bool liked = false;
  final List<String> comments = [];
}
