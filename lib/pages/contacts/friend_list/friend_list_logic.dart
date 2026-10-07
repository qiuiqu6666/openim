import 'dart:async';
import 'package:get/get.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim_common/openim_common.dart';
import '../../../core/controller/im_controller.dart';
import '../contacts_logic.dart';
import '../directory/contact_directory_indexer.dart';
import '../directory/contact_directory_snapshot.dart';

class FriendListLogic extends GetxController {
  final imLoic = Get.find<IMController>();
  final friendList = <ISUserInfo>[].obs;
  final userIDList = <String>[];
  final _subscriptions = <StreamSubscription>[];
  final _indexer = ContactDirectoryIndexer();
  final _changes = <String, ISUserInfo?>{};
  final _account = DataSp.userID;
  final _token = DataSp.chatToken;
  Timer? _updateTimer;
  ContactsLogic? _owner;
  int _revision = 0;
  bool _closed = false;
  bool get _active =>
      !_closed &&
      !isClosed &&
      DataSp.userID == _account &&
      DataSp.chatToken == _token;

  @override
  void onInit() {
    if (Get.isRegistered<ContactsLogic>()) {
      final owner = Get.find<ContactsLogic>();
      if (owner.isCurrentSession) _owner = owner;
    }
    if (_owner != null) {
      _subscriptions.add(_owner!.friends.stream.listen(_publish));
    } else {
      _subscriptions.addAll([
        imLoic.friendDelSubject.listen((user) => _changed(user.userID, null)),
        imLoic.friendAddSubject.listen((user) =>
            _changed(user.userID, ISUserInfo.fromJson(user.toJson()))),
        imLoic.friendInfoChangedSubject.listen((user) =>
            _changed(user.userID, ISUserInfo.fromJson(user.toJson()))),
      ]);
    }
    _subscriptions.add(imLoic.blacklistChangedSubject.listen((_) {
      if (!_active) return;
      final owner = _owner;
      if (owner != null) {
        unawaited(owner.loadFriends());
      } else {
        unawaited(_getFriendList());
      }
    }));
    super.onInit();
  }

  @override
  void onReady() {
    unawaited(_getFriendList());
    super.onReady();
  }

  Future<void> _getFriendList() async {
    try {
      final result = await loadContactDirectorySnapshot();
      if (!_active) return;
      _publish(result);
      if (_changes.isNotEmpty) await _applyChanges();
    } catch (_) {
      // Keep the existing snapshot on a transient SDK failure.
    }
  }

  void _publish(List<ISUserInfo> result) {
    if (!_active) return;
    final previousIDs = userIDList.toSet();
    final membershipChanged = previousIDs.length != result.length ||
        result.any((user) => !previousIDs.contains(user.userID));
    userIDList
      ..clear()
      ..addAll(result.map((e) => e.userID!));
    if (membershipChanged) onUserIDList(userIDList);
    friendList.assignAll(result);
  }

  void _changed(String? id, ISUserInfo? value) {
    if (!_active || id == null) return;
    _changes[id] = value;
    _revision++;
    _updateTimer ??= Timer(const Duration(milliseconds: 80), () {
      _updateTimer = null;
      unawaited(_applyChanges());
    });
  }

  Future<void> _applyChanges() async {
    if (!_active) return;
    final revision = _revision;
    final byID = {for (final user in friendList) user.userID!: user};
    for (final entry in _changes.entries) {
      if (entry.value == null) {
        byID.remove(entry.key);
      } else {
        byID[entry.key] = entry.value!;
      }
    }
    try {
      final indexed = await _indexer.build([
        for (final user in byID.values)
          ContactNameIndex(userID: user.userID!, displayName: user.showName),
      ]);
      if (!_active || indexed == null || revision != _revision) return;
      _publish([
        for (final name in indexed)
          byID[name.userID]!
            ..tagIndex = name.tagIndex
            ..namePinyin = name.namePinyin
            ..isShowSuspension = name.showHeader,
      ]);
    } catch (_) {/* Retry with the next directory event. */}
  }

  void onUserIDList(List<String> userIDList) {}

  @override
  void onClose() {
    _closed = true;
    _updateTimer?.cancel();
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    _indexer.close();
    _changes.clear();
    super.onClose();
  }

  void viewFriendInfo(ISUserInfo info) => AppNavigator.startUserProfilePane(
        userID: info.userID!,
        nickname: info.nickname,
        faceURL: info.faceURL,
        ex: info.ex ?? '',
      );
}
