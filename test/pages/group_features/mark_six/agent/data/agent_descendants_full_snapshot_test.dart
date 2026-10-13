import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/mark_six/agent/data/agent_descendants_visible_rows.dart';

Map<String, dynamic> player(
  String id,
  String no,
  String parent, {
  int balance = 0,
  String name = '',
}) => <String, dynamic>{
  'userId': id,
  'playerNo': no,
  'directParentUserId': parent,
  'displayName': name.isEmpty ? no : name,
  'balance': balance,
  'totalFlow': balance,
  'playerProfitLoss': balance,
};

void main() {
  test('search reaches row outside first 100 of a 2116-player snapshot', () {
    final items = List<Map<String, dynamic>>.generate(
      2116,
      (index) => player('wx_$index', '${12000 + index}', 'q14gkm5swv',
          balance: index),
    );
    items[2048] = player('sj9366yaw1', '9289', 'q14gkm5swv',
        balance: 52, name: '美好');
    final found = agentVisibleRows(items, ownerID: 'q14gkm5swv', keyword: '9289');
    expect(found.map((row) => row.$1['userId']).toList(), ['sj9366yaw1']);
  });

  test('detail child filter retains full 79 / 101 / 48 direct relations', () {
    final items = <Map<String, dynamic>>[
      for (var i = 0; i < 79; i++) player('child9307_$i', '$i', 'owner9307'),
      for (var i = 0; i < 101; i++) player('child9575_$i', '$i', 'owner9575'),
      for (var i = 0; i < 48; i++) player('child9199_$i', '$i', 'owner9199'),
    ];
    int direct(String owner) => items.where((row) =>
        row['directParentUserId'] == owner && row['userId'] != owner).length;
    expect(direct('owner9307'), 79);
    expect(direct('owner9575'), 101);
    expect(direct('owner9199'), 48);
  });

  test('global balance sort is stable and covers all tree levels', () {
    final items = [
      player('child', '9500', 'parent', balance: 391),
      player('parent', '9307', 'owner', balance: 27003),
      player('top', '10671', 'owner', balance: 53487),
      player('middle', '10245', 'owner', balance: 40290),
    ];
    final result = agentVisibleRows(items, ownerID: 'owner', sort: 'balance');
    expect(result.map((row) => row.$1['userId']).toList(),
        ['top', 'middle', 'parent', 'child']);
  });
}
