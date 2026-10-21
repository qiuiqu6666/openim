import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../contacts/select_contacts/selection/contact_selection_policy.dart';
import '../models/channel_kind.dart';
import '../models/channel_id.dart';
import '../models/channel_preview.dart';

/// One attempt owns a stable group ID so an uncertain response can be retried.
class ChannelCreation {
  ChannelCreation(
      {required this.current,
      required this.owner,
      required this.upload,
      required this.create,
      required this.lookup,
      required this.mute,
      String? id})
      : id = id ?? generateChannelID();
  final bool Function() current;
  final String owner;
  final String id;
  final Future<String> Function(Uint8List) upload;
  final Future<GroupInfo> Function(GroupInfo, List<String>) create;
  final Future<List<GroupInfo>> Function(String) lookup;
  final Future<void> Function(String) mute;
  GroupInfo? _created;
  bool _attempted = false;
  bool _busy = false;

  factory ChannelCreation.sdk() {
    final owner = OpenIM.iMManager.userID;
    final token = DataSp.chatToken;
    final manager = OpenIM.iMManager.groupManager;
    return ChannelCreation(
        owner: owner,
        current: () =>
            owner.isNotEmpty &&
            owner == OpenIM.iMManager.userID &&
            token == DataSp.chatToken,
        upload: _uploadAvatar,
        create: (info, members) =>
            manager.createGroup(groupInfo: info, memberUserIDs: members),
        lookup: (id) => manager.getGroupsInfo(groupIDList: [id]),
        mute: (id) async {
          await manager.changeGroupMute(groupID: id, mute: true);
        });
  }

  void _check() {
    if (!current()) throw StateError('Account changed');
  }

  Future<void> submit(ChannelPreview draft) async {
    if (_busy) throw StateError('Creation already in progress');
    _busy = true;
    try {
      _check();
      if (_attempted && _created == null) {
        final groups = await lookup(id);
        _check();
        for (final group in groups) {
          if (group.groupID == id &&
              group.ownerUserID == owner &&
              isChannelEx(group.ex)) {
            _created = group;
          }
        }
      }
      if (_created == null) {
        if (draft.name.trim().isEmpty) {
          throw ArgumentError('Missing channel details');
        }
        final members = draft.selectedContacts.keys
            .where((id) =>
                id != owner &&
                ContactSelectionPolicy.allowsGroupMemberUserID(id))
            .toSet()
            .toList();
        final url = draft.avatar == null ? '' : await upload(draft.avatar!);
        _check();
        final info = GroupInfo(
            groupID: id,
            groupName: draft.name.trim(),
            introduction: draft.description.trim(),
            faceURL: url,
            groupType: GroupType.work,
            status: 3,
            ex: channelEx());
        _attempted = true;
        _created = await create(info, members);
        _check();
      }
      if (_created!.status != 3) {
        await mute(_created!.groupID);
        _check();
        _created!.status = 3;
      }
      draft.createdGroup = _created;
    } finally {
      _busy = false;
    }
  }

  static Future<String> _uploadAvatar(Uint8List bytes) async {
    final directory = await Directory((await getTemporaryDirectory()).path)
        .createTemp('channel-avatar-');
    try {
      final file =
          await File('${directory.path}/avatar.jpg').writeAsBytes(bytes);
      final result = await OpenIM.iMManager.uploadFile(
          id: const Uuid().v4(), filePath: file.path, fileName: 'avatar.jpg');
      final data = result is String ? jsonDecode(result) : result;
      final url = data is Map ? data['url'] : null;
      if (url is! String || url.isEmpty) {
        throw StateError('Avatar upload failed');
      }
      return url;
    } finally {
      await directory.delete(recursive: true);
    }
  }
}
