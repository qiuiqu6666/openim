import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';

import '../../group/identity/group_member_identity_source.dart';
import '../group_member_order.dart';

/// A small permission-scoped preview, independent of the total member count.
class GroupMemberPreviewController {
  GroupMemberPreviewController({
    required GroupMemberIdentitySource source,
    this.retryDelay = const Duration(seconds: 1),
  }) : _source = source;

  final GroupMemberIdentitySource _source;
  static const _pageSize = 20;
  final Duration retryDelay;
  final members = <GroupMembersInfo>[].obs;
  final loading = false.obs;
  final failed = false.obs;
  Object? _scope;
  int _generation = 0;
  bool _closed = false;
  Future<void>? _flight;
  Timer? _retryTimer;
  Completer<bool>? _waiting;
  final _pendingChanges = <String, (GroupMembersInfo?, bool)>{};

  /// Keep events received during an HTTP read newer than that read's snapshot.
  void applyMemberChange(GroupMembersInfo member,
      {bool deleted = false, bool addIfMissing = true}) {
    final id = member.userID;
    if (_closed || id == null || id.isEmpty) return;
    if (_flight != null) {
      _pendingChanges[id] = (deleted ? null : member, addIfMissing);
    }
    final index = members.indexWhere((value) => value.userID == id);
    if (deleted) {
      members.removeWhere((value) => value.userID == id);
    } else if (index >= 0) {
      members[index] = member;
    } else if (addIfMissing) {
      members.add(member);
    }
    members.sort(compareGroupMembers);
    if (members.length > _pageSize) {
      members.removeRange(_pageSize, members.length);
    }
  }

  Future<void> refresh({
    required String groupID,
    required Object scope,
    required bool Function() isCurrent,
  }) {
    if (_closed || !isCurrent()) return Future.value();
    final flight = _flight;
    if (flight != null && scope == _scope) return flight;
    _stopRetry();
    if (_scope != null && scope != _scope) members.clear();
    final generation = ++_generation;
    _pendingChanges.clear();
    _scope = scope;
    loading.value = true;
    failed.value = false;
    return _flight = _read(groupID, generation, isCurrent).whenComplete(() {
      if (_closed || generation != _generation) return;
      if (!isCurrent()) members.clear();
      loading.value = false;
      _flight = null;
      _pendingChanges.clear();
    });
  }

  Future<void> _read(
      String groupID, int generation, bool Function() isCurrent) async {
    bool current() => !_closed && generation == _generation && isCurrent();
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final page = await _source.list(
          groupID: groupID,
          pageNumber: 1,
          showNumber: _pageSize,
        );
        if (!current()) return;
        // A joined group contains at least its viewer. Empty/missing data must
        // not silently masquerade as a successfully loaded preview.
        if (page.isEmpty) throw const _EmptyMemberPreview();
        final unique = <String, GroupMembersInfo>{};
        for (final member in page) {
          final id = member.userID;
          if (member.groupID == groupID && id?.isNotEmpty == true) {
            unique[id!] = member;
          }
        }
        if (unique.isEmpty) throw const _EmptyMemberPreview();
        for (final entry in _pendingChanges.entries) {
          final (member, addIfMissing) = entry.value;
          if (member == null) {
            unique.remove(entry.key);
          } else if (unique.containsKey(entry.key) || addIfMissing) {
            unique[entry.key] = member;
          }
        }
        final ordered = unique.values.toList()..sort(compareGroupMembers);
        members.assignAll(ordered.take(_pageSize));
        failed.value = false;
        return;
      } catch (error) {
        if (!current()) return;
        if (attempt == 0 && _retryable(error)) {
          if (!await _waitToRetry() || !current()) return;
        } else {
          // Keep the last permitted successful preview on ordinary refresh
          // failure. Permission changes explicitly invalidate and clear it.
          failed.value = true;
          return;
        }
      }
    }
  }

  bool _retryable(Object error) =>
      error is _EmptyMemberPreview ||
      (error is DioException &&
          const {
            DioExceptionType.connectionTimeout,
            DioExceptionType.sendTimeout,
            DioExceptionType.receiveTimeout,
            DioExceptionType.connectionError,
          }.contains(error.type));

  Future<bool> _waitToRetry() {
    final waiting = _waiting = Completer<bool>();
    _retryTimer = Timer(retryDelay, () {
      if (identical(_waiting, waiting)) {
        _waiting = null;
        _retryTimer = null;
      }
      if (!waiting.isCompleted) waiting.complete(true);
    });
    return waiting.future;
  }

  void _stopRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
    final waiting = _waiting;
    _waiting = null;
    if (waiting != null && !waiting.isCompleted) waiting.complete(false);
  }

  void invalidate() {
    _generation++;
    _stopRetry();
    _flight = null;
    _pendingChanges.clear();
    _scope = null;
    loading.value = false;
    failed.value = false;
    members.clear();
  }

  void dispose() {
    if (_closed) return;
    invalidate();
    _closed = true;
  }
}

class _EmptyMemberPreview implements Exception {
  const _EmptyMemberPreview();
}
