/// Server-confirmed group binding. It carries no personal business permission.
class RobotGroupBinding {
  const RobotGroupBinding({
    required this.groupID,
    required this.bound,
    required this.enabled,
    required this.machineCodeMasked,
  });

  final String groupID;
  final bool bound, enabled;
  final String machineCodeMasked;

  factory RobotGroupBinding.fromJson(Map<String, dynamic> json,
      {required String expectedGroupID}) {
    if (json['groupId'] != expectedGroupID) {
      throw const FormatException('群绑定信息不匹配');
    }
    if (json['bound'] is! bool || json['enabled'] is! bool) {
      throw const FormatException('群绑定状态格式错误');
    }
    final masked = json['machineCodeMasked'];
    if (masked != null && masked is! String) {
      throw const FormatException('群绑定机器码格式错误');
    }
    return RobotGroupBinding(
      groupID: expectedGroupID,
      bound: json['bound'] as bool,
      enabled: json['enabled'] as bool,
      machineCodeMasked: masked as String? ?? '',
    );
  }
}
