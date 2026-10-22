# 管理员变更系统消息

2026-10-21：正式服务器缺少管理员变更通知配置，1517 / 1518 没有作为聊天消息发送。仅添加 Flutter 渲染分支无法解决。

已将 notification.yml 中的三项配置合并到正式配置并重启群 RPC 服务。保留群成员资料编辑静默行为；仅设为管理员/取消管理员发送系统消息。使用可靠历史记录，关闭离线推送。当前 GetOptionsByNotification 会由 isSendMsg 决定未读，不应将 unreadCount:false 解释为绝对不增加未读。

当前服务配置解析器使用 mapstructure，但 GroupMemberSetToOrdinary 只有 yaml 标签，故同时保留字段名对应键及声明的 YAML 键。

验证：服务端加载配置后 1517、1518 的聊天投递、历史和持久化选项均开启；前端六种操作/查看者场景通过。未在用户真实群内代为调整角色。旧操作不会补发消息，客户端须包含对应渲染修改。

服务器备份：/srv/99chat-production/backups/admin-tips-20261021/notification.yml。
