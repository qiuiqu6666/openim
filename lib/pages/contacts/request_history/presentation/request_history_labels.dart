import 'package:get/get.dart';

abstract final class RequestHistoryLabels {
  static bool get english => Get.locale?.languageCode == 'en';
  static String get friends => english ? 'New Friends' : '新的朋友';
  static String get incoming => english ? 'Requests Received' : '对方添加我';
  static String get outgoing => english ? 'Requests Sent' : '我添加对方';
  static String direction(bool sent) => sent
      ? (english ? 'Sent by you' : '你发起的申请')
      : (english ? 'Received from them' : '对方发起的申请');
  static String get verify => english ? 'Verify' : '验证';
  static String get review => english ? 'Review' : '审核';
  static String get pending => english ? 'Pending' : '待审核';
  static String get more => english ? 'More' : '更多';
  static String get clearGroups => english ? 'Clear Group Notices' : '清空群通知';
  static String get deselect => english ? 'Deselect All' : '取消全选';
  static String get emptyFriends => english ? 'No new contacts' : '暂无新联系人';
  static String deletePrompt(int count) =>
      english ? 'Delete $count selected records?' : '确定删除选中的 $count 条记录吗？';
  static String handler(String name) =>
      english ? 'Handled by: $name' : '处理管理员：$name';
  static String groupContent(String applicant, String group, String? inviter) =>
      inviter != null
          ? (english
              ? '$inviter invited $applicant to the group'
              : '$inviter 邀请 $applicant 加入群聊')
          : (english
              ? '$applicant requested to join $group'
              : '$applicant 申请加入 $group');
}
