import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

/// Searches the SDK directory, independently of the loaded ownership pages.
class GroupListSearch {
  GroupListSearch({
    Future<List<GroupInfo>> Function(String)? findGroups,
    required String Function() currentUserID,
    String? Function()? currentToken,
    ValueChanged<List<GroupInfo>>? onResults,
  })  : _findGroups = findGroups ??
            ((query) => OpenIM.iMManager.groupManager.searchGroups(
                keywordList: [query],
                isSearchGroupName: true,
                isSearchGroupID: true)),
        _currentUserID = currentUserID,
        _currentToken = currentToken ?? (() => DataSp.chatToken),
        _onResults = onResults {
    _account = _currentUserID();
    _token = _currentToken();
  }

  final Future<List<GroupInfo>> Function(String) _findGroups;
  final String Function() _currentUserID;
  final String? Function() _currentToken;
  final ValueChanged<List<GroupInfo>>? _onResults;
  late final String _account;
  late final String? _token;
  final controller = TextEditingController();
  final query = ''.obs;
  final results = <GroupInfo>[].obs;
  final loading = false.obs;
  final failed = false.obs;
  Timer? _debounce;
  int _generation = 0;
  bool _closed = false;

  bool get _active =>
      !_closed && _account == _currentUserID() && _token == _currentToken();

  List<GroupInfo> groupsFor({required bool created}) => !_active
      ? const []
      : results
          .where((group) => (group.ownerUserID == _account) == created)
          .toList(growable: false);

  void change(String value) {
    if (!_active) return;
    final next = graphemeTrim(value);
    if (next == query.value) return;
    _debounce?.cancel();
    ++_generation;
    query.value = next;
    results.clear();
    failed.value = false;
    loading.value = next.isNotEmpty;
    if (next.isNotEmpty) {
      _debounce = Timer(const Duration(milliseconds: 250), run);
    }
  }

  Future<void> run() async {
    _debounce?.cancel();
    if (!_active || query.isEmpty) return;
    final generation = ++_generation;
    final keyword = query.value;
    loading.value = true;
    failed.value = false;
    bool applicable() => _active && generation == _generation;
    try {
      final groups = await _findGroups(keyword);
      if (!applicable()) return;
      _onResults?.call(groups);
      results.assignAll({
        for (final group in groups)
          if (group.groupID.isNotEmpty) group.groupID: group,
      }.values);
    } catch (_) {
      if (applicable()) failed.value = true;
    } finally {
      if (applicable()) loading.value = false;
    }
  }

  void dispose() {
    _closed = true;
    ++_generation;
    _debounce?.cancel();
    controller.dispose();
  }
}
