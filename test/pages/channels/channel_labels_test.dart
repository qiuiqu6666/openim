import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/channels/presentation/channel_labels.dart';

void main() {
  test('channel management labels use channel terminology only in channels', () {
    const labels = {
      '群主': '频道主',
      '确定将群主转让给：%s？': '确定将频道主转让给：%s？',
      '群成员(2人)': '订阅者(2人)',
      '搜索群成员': '搜索订阅者',
      '群管理': '频道设置',
      '确认修改入群验证': '确认修改加入频道验证',
      '群成员隐私保护': '订阅者隐私保护',
      '开启后不允许查看群成员资料，关闭后允许查看': '开启后不允许查看订阅者资料，关闭后允许查看',
      '群主管理权转让': '频道主管理权转让',
      'Transfer Group Owner': 'Transfer Channel Owner',
    };
    for (final entry in labels.entries) {
      expect(channelLabel(entry.key, channel: true), entry.value);
      expect(channelLabel(entry.key, channel: false), entry.key);
    }
  });
}
