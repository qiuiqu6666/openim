class SangongAgentHall {
  const SangongAgentHall(
      {required this.tenantId, required this.name, required this.gameGroupId});

  final String tenantId, name, gameGroupId;

  factory SangongAgentHall.fromJson(Map<String, dynamic> value) {
    final tenant = value['tenantId'];
    final name = value['name'];
    final group = value['imGroupGameId'];
    if (tenant is! String ||
        tenant.isEmpty ||
        name is! String ||
        group is! String ||
        group.isEmpty) {
      throw const FormatException('厅资料无效，请刷新重试');
    }
    return SangongAgentHall(
        tenantId: tenant,
        name: name.trim().isEmpty ? '未命名厅' : name,
        gameGroupId: group);
  }
}
