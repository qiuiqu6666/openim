// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 代理查询浮窗的拖拽位置和展开状态。
class AgentRebateFloatPrefs {
  AgentRebateFloatPrefs._();

  static final AgentRebateFloatPrefs instance = AgentRebateFloatPrefs._();

  final Map<String, Offset> _offsetCache = {};
  final Map<String, bool> _expandedCache = {};

  String _key(String conversationId, String field) =>
      'agent_rebate_float_v2:${Uri.encodeComponent(conversationId)}:$field';

  Offset? readOffsetSync(String conversationId) => _offsetCache[conversationId];
  bool? readExpandedSync(String conversationId) =>
      _expandedCache[conversationId];

  Future<Offset?> readOffset(String conversationId) async {
    final cached = _offsetCache[conversationId];
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final left = prefs.getDouble(_key(conversationId, 'left'));
    final top = prefs.getDouble(_key(conversationId, 'top'));
    if (left == null || top == null || !left.isFinite || !top.isFinite) {
      return null;
    }
    final offset = Offset(left, top);
    _offsetCache[conversationId] = offset;
    return offset;
  }

  Future<void> writeOffset(String conversationId, Offset offset) async {
    if (!offset.dx.isFinite || !offset.dy.isFinite) {
      return;
    }
    _offsetCache[conversationId] = offset;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_key(conversationId, 'left'), offset.dx);
    await prefs.setDouble(_key(conversationId, 'top'), offset.dy);
  }

  Future<bool> readExpanded(String conversationId,
      {bool defaultValue = false}) async {
    final cached = _expandedCache[conversationId];
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final expanded =
        prefs.getBool(_key(conversationId, 'expanded')) ?? defaultValue;
    _expandedCache[conversationId] = expanded;
    return expanded;
  }

  Future<void> writeExpanded(String conversationId, bool expanded) async {
    _expandedCache[conversationId] = expanded;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(conversationId, 'expanded'), expanded);
  }
}
