import 'package:openim_common/localization.dart';

/// Adapt shared management UI labels only, never user-entered names or SDK data.
String channelLabel(String label, {required bool channel}) {
  if (!channel) return label;
  const terms = {
    '群成员': '订阅者', '群成員': '訂閱者',
    '群主': '频道主', '群管理': '频道设置', '群管理權': '頻道管理權',
    '入群': '加入频道', '群聊': '频道',
    '群組成員': '訂閱者', '群組擁有者': '頻道擁有者', '群組': '頻道',
    'Group members': 'Subscribers', 'group members': 'subscribers',
    'Group owner': 'Channel owner', 'group owner': 'channel owner',
    'Group Owner': 'Channel Owner', 'Management': 'Channel settings',
    'Group management': 'Channel settings', 'Group Management': 'Channel settings',
    'group chat': 'channel', 'group joining': 'channel joining',
  };
  var result = label;
  for (final entry in terms.entries) {
    result = result.replaceAll(entry.key, entry.value);
  }
  return AppCopy.text(result);
}
