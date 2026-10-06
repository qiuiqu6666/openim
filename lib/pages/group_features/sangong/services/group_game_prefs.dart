// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 群游戏浮窗入口的本地显示偏好、位置和展开态（全部按群维度）。
class GroupGamePrefs {
  GroupGamePrefs._();

  static final GroupGamePrefs instance = GroupGamePrefs._();

  static const String _floatVisiblePrefix = 'group_game_float_visible_';
  static const String _positionPrefix = 'group_game_float_v2:';
  final Map<String, bool> _visibleCache = {};
  final Map<String, Offset> _offsetCache = {};
  final Map<String, bool> _expandedCache = {};

  String _positionKey(String groupId, String field) =>
      '$_positionPrefix${Uri.encodeComponent(groupId.trim())}:$field';

  bool? isFloatVisibleSync(String groupId) => _visibleCache[groupId.trim()];
  Offset? readFloatOffsetSync(String groupId) => _offsetCache[groupId.trim()];
  bool? readFloatExpandedSync(String groupId) => _expandedCache[groupId.trim()];

  String _key(String groupId) => '$_floatVisiblePrefix${groupId.trim()}';

  /// 在 runApp 前灌入内存，使聊天页首帧可以同步决定可见性、位置和展开态。
  Future<void> preload() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys()) {
      if (key.startsWith(_floatVisiblePrefix)) {
        final id = key.substring(_floatVisiblePrefix.length).trim();
        final value = prefs.getBool(key);
        if (id.isNotEmpty && value != null) _visibleCache[id] = value;
        continue;
      }
      if (!key.startsWith(_positionPrefix)) continue;
      final suffix = key.substring(_positionPrefix.length);
      final separator = suffix.lastIndexOf(':');
      if (separator <= 0) continue;
      final id = Uri.decodeComponent(suffix.substring(0, separator)).trim();
      final field = suffix.substring(separator + 1);
      if (id.isEmpty) continue;
      if (field == 'expanded') {
        final value = prefs.getBool(key);
        if (value != null) _expandedCache[id] = value;
      }
    }
    // 坐标需要成对读取，避免只存在一个字段时生成无效 Offset。
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_positionPrefix) || !key.endsWith(':left')) continue;
      final encoded = key.substring(
        _positionPrefix.length,
        key.length - ':left'.length,
      );
      final id = Uri.decodeComponent(encoded).trim();
      final left = prefs.getDouble(key);
      final top = prefs.getDouble(_positionKey(id, 'top'));
      if (id.isNotEmpty &&
          left != null &&
          top != null &&
          left.isFinite &&
          top.isFinite) {
        _offsetCache[id] = Offset(left, top);
      }
    }
  }

  Future<bool> isFloatVisible(String groupId) async {
    final id = groupId.trim();
    if (id.isEmpty) {
      return true;
    }
    final prefs = await SharedPreferences.getInstance();
    final visible = prefs.getBool(_key(id)) ?? true;
    _visibleCache[id] = visible;
    return visible;
  }

  Future<void> setFloatVisible(String groupId, bool visible) async {
    final id = groupId.trim();
    if (id.isEmpty) {
      return;
    }
    _visibleCache[id] = visible;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(id), visible);
  }

  /// 读取浮窗左上角坐标；从未拖动过则返回 `null`。
  Future<Offset?> readFloatOffset(String groupId) async {
    final id = groupId.trim();
    final cached = _offsetCache[id];
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final left = prefs.getDouble(_positionKey(id, 'left'));
    final top = prefs.getDouble(_positionKey(id, 'top'));
    if (left == null || top == null) {
      return null;
    }
    if (!left.isFinite || !top.isFinite) {
      return null;
    }
    final offset = Offset(left, top);
    _offsetCache[id] = offset;
    return offset;
  }

  Future<void> writeFloatOffset(String groupId, Offset offset) async {
    if (!offset.dx.isFinite || !offset.dy.isFinite) {
      return;
    }
    final id = groupId.trim();
    _offsetCache[id] = offset;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_positionKey(id, 'left'), offset.dx);
    await prefs.setDouble(_positionKey(id, 'top'), offset.dy);
  }

  /// 浮窗是否展开；从未设置过则默认收起。
  Future<bool> readFloatExpanded(String groupId) async {
    final id = groupId.trim();
    final cached = _expandedCache[id];
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final expanded = prefs.getBool(_positionKey(id, 'expanded')) ?? false;
    _expandedCache[id] = expanded;
    return expanded;
  }

  Future<void> writeFloatExpanded(String groupId, bool expanded) async {
    final id = groupId.trim();
    _expandedCache[id] = expanded;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_positionKey(id, 'expanded'), expanded);
  }
}
