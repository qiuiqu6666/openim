import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/mark_six/agent/data/agent_descendants_visible_rows.dart';

Map<String, dynamic> player(
  String id,
  String no,
  String parent, {
  int balance = 0,
  String name = '',
  bool agent = false,
}) => <String, dynamic>{
  'userId': id,
  'playerNo': no,
  'directParentUserId': parent,
  'displayName': name.isEmpty ? no : name,
  'isAgent': agent,
  'balance': balance,
  'totalFlow': balance,
  'playerProfitLoss': balance,
};

List<String> ids(List<AgentDescendantVisibleRow> rows) =>
    rows.map((row) => '${row.$1['userId']}').toList();

void main() {
  test('99CHAT default preserves complete A -> B -> C parent chain', () {
    final data = [
      player('C', '9601', 'B', balance: 99999),
      player('D', '9701', 'owner', balance: 200),
      player('B', '9501', 'A', balance: 1000, agent: true),
      player('A', '9307', 'owner', balance: 500, agent: true),
      player('A2', '9502', 'A', balance: 300),
    ];
    final projection = AgentDescendantsProjection(data, ownerID: 'owner');
    final rows = projection.visibleRows();
    expect(ids(rows), ['A', 'B', 'C', 'A2', 'D']);
    expect(rows.map((r) => r.$2).toList(), [0, 1, 2, 1, 0]);
    expect(projection.parentDescription(data.first), '直属上级：9501');
    expect(projection.relationshipPath(data.first),
        '所属关系：当前代理 → 9307 → 9501 → 9601');
  });

  test('sort applies to first-level roots, not grandchildren', () {
    final data = [
      player('childA', '5101', 'A', balance: 9999),
      player('B', '5002', 'owner', balance: 700),
      player('A', '5001', 'owner', balance: 300),
      player('childB', '5102', 'B', balance: 1),
    ];
    final projection = AgentDescendantsProjection(data, ownerID: 'owner');
    expect(ids(projection.visibleRows()), ['B', 'childB', 'A', 'childA']);
    expect(ids(projection.visibleRows(descending: false)),
        ['A', 'childA', 'B', 'childB']);
    expect(ids(projection.visibleRows(view: AgentDescendantView.ranking)),
        ['childA', 'B', 'A', 'childB']);
  });

  test('search all 2116 rows without pagination or unrelated descendants', () {
    final data = List<Map<String, dynamic>>.generate(
      2116,
      (index) => player('wx_$index', '${12000 + index}', 'owner',
          balance: index),
    );
    data[2048] = player('sj9366yaw1', '9289', 'wx_50',
        balance: 52, name: '美好');
    final projection = AgentDescendantsProjection(data, ownerID: 'owner');
    final found = projection.visibleRows(keyword: '9289');
    expect(ids(found), ['sj9366yaw1']);
    expect(projection.relationshipPath(found.single.$1),
        '所属关系：当前代理 → 12050 → 美好（9289）');
    expect(projection.visibleRows().length, 2116);
    expect(projection.visibleRows(view: AgentDescendantView.ranking).length, 2116);
  });

  test('search includes nickname and userId and supports number fragments', () {
    final data = [
      {...player('im_new', '10003', 'owner'), 'nickname': '小乔'},
      player('legacy_wxid_33', '9307', 'owner', name: '蓝贝贝十分'),
    ];
    final projection = AgentDescendantsProjection(data, ownerID: 'owner');
    expect(ids(projection.visibleRows(keyword: '小乔')), ['im_new']);
    expect(ids(projection.visibleRows(keyword: 'wxid')), ['legacy_wxid_33']);
    expect(ids(projection.visibleRows(keyword: '307')), ['legacy_wxid_33']);
    expect(ids(projection.visibleRows(keyword: '失配')), isEmpty);
  });

  test('broken, self-parent and cyclic records are displayed exactly once', () {
    final data = [
      player('root', '100', 'owner'),
      player('child', '101', 'root'),
      player('orphan', '102', 'missing'),
      player('self', '103', 'self'),
      player('cycleA', '104', 'cycleB'),
      player('cycleB', '105', 'cycleA'),
      player('child', '101', 'root'), // duplicated packet
    ];
    final projection = AgentDescendantsProjection(data, ownerID: 'owner');
    final rows = projection.visibleRows();
    expect(rows.length, 6);
    expect(ids(rows).toSet().length, 6);
    expect(ids(rows).sublist(0, 2), ['root', 'child']);
    expect(projection.parentDescription(data[2]), '直属上级：未收录的上级');
    expect(projection.relationshipPath(data[4]), contains('关系异常'));
    expect(projection.visibleRows(view: AgentDescendantView.ranking).length, 6);
  });

  test('direct members who are not agents are still first-level roots', () {
    final data = [
      player('nonAgentRoot', '9198', 'owner', agent: false),
      player('grandchild', '9176', 'nonAgentRoot'),
    ];
    final rows = AgentDescendantsProjection(data, ownerID: 'owner').visibleRows();
    expect(ids(rows), ['nonAgentRoot', 'grandchild']);
    expect(rows[1].$2, 1);
  });

  test('very deep relation cannot overflow recursion or hide users', () {
    const depth = 1200;
    final data = [for (var i = depth - 1; i >= 0; i--)
      player('id_$i', '$i', i == 0 ? 'owner' : 'id_${i - 1}')];
    final rows = AgentDescendantsProjection(data, ownerID: 'owner').visibleRows();
    expect(rows.length, depth);
    expect(rows.first.$2, 0);
    expect(rows.last.$2, depth - 1);
  });

  test('detail direct child counts 79 / 101 / 48 remain untouched', () {
    final data = <Map<String, dynamic>>[
      for (var i = 0; i < 79; i++) player('child9307_$i', '$i', 'owner9307'),
      for (var i = 0; i < 101; i++) player('child9575_$i', '$i', 'owner9575'),
      for (var i = 0; i < 48; i++) player('child9199_$i', '$i', 'owner9199'),
    ];
    int direct(String parent) => data.where((row) =>
        row['directParentUserId'] == parent && row['userId'] != parent).length;
    expect(direct('owner9307'), 79);
    expect(direct('owner9575'), 101);
    expect(direct('owner9199'), 48);
    final all = AgentDescendantsProjection(data, ownerID: 'owner').visibleRows();
    expect(all.length, 228);
  });
}
