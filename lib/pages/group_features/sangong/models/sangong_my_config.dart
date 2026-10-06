// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
/// `GET/PUT /api/v1/admin/my-config` 响应。
class SangongMyConfig {
  const SangongMyConfig({
    this.configured = false,
    this.tenantId = '',
    this.name = '',
    this.imGroupGameId = '',
    this.imGroupAdminStatsId = '',
    this.imGroupLedgerId = '',
    this.imGroupWaterId = '',
    this.imBotUserId = '',
    this.myRole = '',
    this.canEditConfig = false,
    this.canManageMembers = false,
  });

  final bool configured;
  final String tenantId;
  final String name;
  final String imGroupGameId;
  final String imGroupAdminStatsId;
  final String imGroupLedgerId;
  final String imGroupWaterId;
  final String imBotUserId;

  /// `owner` | `admin` | 空
  final String myRole;
  final bool canEditConfig;
  final bool canManageMembers;

  bool get isOwner => myRole.trim().toLowerCase() == 'owner';
  bool get isAdmin => myRole.trim().toLowerCase() == 'admin';

  factory SangongMyConfig.fromJson(Map<String, dynamic> json) {
    final configured = _readBool(json['configured']) ?? false;
    final imGroupGameId =
        (json['imGroupGameId'] ?? json['im_group_game_id'] ?? '')
            .toString()
            .trim();
    final tenantId =
        (json['tenantId'] ?? json['tenant_id'] ?? '').toString().trim();
    final myRole = (json['myRole'] ?? json['my_role'] ?? '').toString().trim();
    final canEditConfig =
        _readBool(json['canEditConfig'] ?? json['can_edit_config']) ??
            myRole.toLowerCase() == 'owner';
    final canManageMembers =
        _readBool(json['canManageMembers'] ?? json['can_manage_members']) ??
            myRole.toLowerCase() == 'owner';
    return SangongMyConfig(
      configured: configured,
      tenantId: tenantId,
      name: json['name']?.toString().trim() ?? '',
      imGroupGameId: imGroupGameId,
      imGroupAdminStatsId:
          (json['imGroupAdminStatsId'] ?? json['im_group_admin_stats_id'] ?? '')
              .toString()
              .trim(),
      imGroupLedgerId:
          (json['imGroupLedgerId'] ?? json['im_group_ledger_id'] ?? '')
              .toString()
              .trim(),
      imGroupWaterId:
          (json['imGroupWaterId'] ?? json['im_group_water_id'] ?? '')
              .toString()
              .trim(),
      imBotUserId: (json['imBotUserId'] ?? json['im_bot_user_id'] ?? '')
          .toString()
          .trim(),
      myRole: myRole,
      canEditConfig: canEditConfig,
      canManageMembers: canManageMembers,
    );
  }

  Map<String, dynamic> toSaveBody() {
    return <String, dynamic>{
      'name': name.trim(),
      'imGroupGameId': imGroupGameId.trim(),
      'imGroupAdminStatsId': imGroupAdminStatsId.trim(),
      'imGroupLedgerId': imGroupLedgerId.trim(),
      if (imGroupWaterId.trim().isNotEmpty)
        'imGroupWaterId': imGroupWaterId.trim(),
      'imBotUserId': imBotUserId.trim(),
    };
  }

  /// 本地缓存序列化（含角色 / 权限字段）。
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'configured': configured,
      'tenantId': tenantId,
      'name': name,
      'imGroupGameId': imGroupGameId,
      'imGroupAdminStatsId': imGroupAdminStatsId,
      'imGroupLedgerId': imGroupLedgerId,
      'imGroupWaterId': imGroupWaterId,
      'imBotUserId': imBotUserId,
      'myRole': myRole,
      'canEditConfig': canEditConfig,
      'canManageMembers': canManageMembers,
    };
  }

  bool isSameAs(SangongMyConfig other) {
    return configured == other.configured &&
        tenantId == other.tenantId &&
        name == other.name &&
        imGroupGameId == other.imGroupGameId &&
        imGroupAdminStatsId == other.imGroupAdminStatsId &&
        imGroupLedgerId == other.imGroupLedgerId &&
        imGroupWaterId == other.imGroupWaterId &&
        imBotUserId == other.imBotUserId &&
        myRole == other.myRole &&
        canEditConfig == other.canEditConfig &&
        canManageMembers == other.canManageMembers;
  }

  SangongMyConfig copyWith({
    bool? configured,
    String? tenantId,
    String? name,
    String? imGroupGameId,
    String? imGroupAdminStatsId,
    String? imGroupLedgerId,
    String? imGroupWaterId,
    String? imBotUserId,
    String? myRole,
    bool? canEditConfig,
    bool? canManageMembers,
  }) {
    return SangongMyConfig(
      configured: configured ?? this.configured,
      tenantId: tenantId ?? this.tenantId,
      name: name ?? this.name,
      imGroupGameId: imGroupGameId ?? this.imGroupGameId,
      imGroupAdminStatsId: imGroupAdminStatsId ?? this.imGroupAdminStatsId,
      imGroupLedgerId: imGroupLedgerId ?? this.imGroupLedgerId,
      imGroupWaterId: imGroupWaterId ?? this.imGroupWaterId,
      imBotUserId: imBotUserId ?? this.imBotUserId,
      myRole: myRole ?? this.myRole,
      canEditConfig: canEditConfig ?? this.canEditConfig,
      canManageMembers: canManageMembers ?? this.canManageMembers,
    );
  }

  static bool? _readBool(dynamic raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    if (raw is String) {
      final v = raw.trim().toLowerCase();
      if (v == 'true' || v == '1' || v == 'yes') return true;
      if (v == 'false' || v == '0' || v == 'no') return false;
    }
    return null;
  }
}

/// `GET /api/v1/admin/my-config/members` 成员。
class SangongTenantAccessMember {
  const SangongTenantAccessMember({
    this.imUserId = '',
    this.role = '',
    this.isDefault = false,
  });

  final String imUserId;

  /// `owner` | `admin`
  final String role;
  final bool isDefault;

  bool get isOwner => role.trim().toLowerCase() == 'owner';
  bool get isAdmin => role.trim().toLowerCase() == 'admin';

  factory SangongTenantAccessMember.fromJson(Map<String, dynamic> json) {
    return SangongTenantAccessMember(
      imUserId:
          (json['imUserId'] ?? json['im_user_id'] ?? '').toString().trim(),
      role: (json['role'] ?? '').toString().trim(),
      isDefault: SangongMyConfig._readBool(
            json['isDefault'] ?? json['is_default'],
          ) ??
          false,
    );
  }
}
