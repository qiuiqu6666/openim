# 自动通过好友申请

## 行为与入口

客户端入口：设置 → 好友权限 → 自动通过好友申请。默认关闭，开启后新申请通过 Chat 服务端调用 OpenIM 的正式同意申请接口，接收方离线也可处理。关闭后恢复人工审核。历史待审核申请不批量处理；禁止添加、添加来源权限、群保护、黑名单和申请凭证校验继续生效。

对照 `E:/openim/reference-99chat/lib/src/pages/settings/friend_permission_page.dart` 的好友验证设置；使用当前 OpenIM/Chat 数据链路。客户端复用 SettingsScaffold、SettingsGroup、现有开关行和 AppSwitch，支持亮暗主题、大字体和语义标签。没有新增 SDK 依赖。

## 协议与持久化

- 复用已鉴权 `/user/update`，新增可选 `autoAcceptFriend` 布尔字段，仅修改请求中明确提供的设置。原有用户身份检查继续限制普通用户只能修改自己的资料。
- 完整用户资料通过可选布尔值返回该设置；默认明确返回 false。字段缺失表示旧服务不支持，客户端禁用开关，不假报保存成功。
- MongoDB `attributes.auto_accept_friend` 保存账号设置，未设置时为 false；无需回写历史账号。
- `friend_grants.auto_accept` 在第一次提交、占用凭证时保存策略快照。后续开启设置不会改变旧申请的快照。
- 自动审批前重新校验权限和黑名单，并核对当前申请的操作 ID；已同意或已拒绝的申请不重复处理。
- 自动审批接口失败时，申请仍留在 pending/unknown，通过既有申请重试/settle 路径重试；不会先标记成功，也不新增后台扫描历史申请的任务。
- 重试前发现开关关闭，则停止自动审批，申请保留为正常人工审核申请。

## 文件与维护

客户端 API：`lib/pages/mine/settings/friend_permissions/friend_auto_accept_api.dart`。
界面、设置状态与账号资料适配保持在既有 settings 模块和公共资料模型中。
客户端测试：`test/pages/mine/settings/friend_permissions/`。

本目录 `friend_auto_accept.patch` 包含服务端逻辑、数据库映射、协议生成文件和回归测试。`manifest.json` 记录补丁涉及文件的基线和结果 SHA-256，避免覆盖其他任务的更新。

最初补丁基于普通 RPC 源码 `/srv/99chat-production/app/source/chat`，该目录不对应线上安全版 chat-owner。最初独立构建 `/home/ubuntu/friend-auto-accept-20261021/chat` 的普通 RPC 产物未发布。

实际发布使用 `/home/ubuntu/friend-auto-accept-release-20261021/`：
- `chat`：基于与修复后线上 chat-owner 二进制完全匹配的 `/home/ubuntu/otp-latency-20261021/chat`，依赖同批次 `sangong`，保留 TLS、鉴权、后台任务所有权。
- `api`：基于与线上 Chat API 完全匹配的 `/home/ubuntu/fund-risk-unified-20261021`，仅更新接口协议。保留全部既有 JSON 字段标签，避免协议再生成改变旧接口空值输出。
- 本目录 `secure_owner.patch`、`chat_api.patch` 和 `deployment.json` 是实际发布补丁、源码基线及校验记录。原 `friend_auto_accept.patch` / `manifest.json` 仅供最初普通 RPC 实现参考。
本地源码与测试日志：`E:/openim/artifacts/friend-auto-accept-20261021/`。

## 验证与发布状态

- 客户端 19 项相关测试通过，包括保存成功/失败、重复点击、恢复开关、旧服务兼容、切换账号、页面销毁、大字体和亮暗主题。
- 客户端定向 analyze 无问题。
- 服务端 `internal/rpc/chat`、`pkg/common/imapi`、`pkg/common/db/model/chat`、`pkg/protocol/chat` 测试通过。
- Chat API、Chat RPC 编译通过。
- 对当前正式源码执行 `git apply --check` 通过。
- 2026-10-21 18:49:19（Asia/Taipei）已发布安全版 chat-owner 和 Chat API；普通 chat-rpc 未替换、未重启，配置及环境文件校验保持不变。
- 实际发布版 Chat API、好友 RPC、IM 调用、数据库、TLS 和生命周期相关测试通过，两个二进制重新构建成功。workerowner 两项进程测试在候选与原始基线均失败，本次未修改该模块；线上确认单个 owner 成功取得所有权并启动原有 12 项任务。
- 候选服务验证了 mTLS 和权限拒绝；发布后直连 30321 及经 30310 的 RPC 探测均正常，HTTP 无凭证请求被拒绝。临时验证服务已停止。
- 客户端此前 19 项相关测试通过；本次没有重新打包安装，也未进行双账号真机收发验收。

发布时先核对正式源码和当前二进制对应的版本及其他待发布改动，再备份、应用补丁、重新编译并按实际服务管理方式更新。实际对外链路为 Chat API → 30310 mTLS 转发 → 30321 chat-owner；chat-owner 使用保留 TLS、鉴权及 worker 所有权逻辑的独立构建。必须在该安全构建的源码上合入功能并测试，不能用普通 chat-rpc 二进制替换 chat-owner。本次编译的普通 chat-rpc 产物不能直接作为 chat-owner 发布。无需因为这个功能修改 OpenIM 服务或扫描历史好友申请。

验收需使用授权测试账号：确认开关关闭时需要审核；开启后接收方离线仍形成好友关系；重复提交不重复建关系；黑名单与关闭添加入口仍拒绝申请；关闭开关恢复人工审核；切换设备后设置一致；既有待审核申请保持原状。


## 2026-10-21 权限加载错误 14 修复

18:30（Asia/Taipei）另一轮服务部署后，chat-owner 与普通 chat-rpc 的 SHA-256 均为 `28b2336b4eaaa3566170485b6ee41617225a4b93ba453c09c63df77a8fd62f72`，30321 返回明文而加密转发仍按 mTLS 连接，导致 FindUserFullInfo、GetPresenceVisibility 及其他 Chat RPC 请求失败。

本次已备份故障二进制至 `/srv/99chat-production/backups/friend-permissions-rpc-repair-20261021/chat-owner.before`，从本轮部署前备份 `/srv/99chat-production/backups/fund-spend-security-20261021-1830/chat-owner` 恢复 chat-owner，并重启 chat-owner、chat-api 以恢复连接。未替换 chat-rpc 或修改用户权限数据，也未降低 TLS/鉴权要求。

核验：30321 TLS 1.3 证书验证成功；30310 转发到 30321 存在活跃连接；无用户凭证的 GetPresenceVisibility 返回 NoPermissionError（1002），FindUserFullInfo 空参数返回 ArgsError（1001），均已正常到达服务；18:35 后检查到 18:36 的最新日志未再出现 RPC 错误 14。未使用真实用户凭证读取隐私设置，客户端仍需点击重试确认实际账号的显示。

该恢复将 chat-owner 恢复到 18:30 部署前的行为，因此那次部署中新加到普通 RPC 的业务变更不能视为已在安全入口生效。后续需按正确安全构建合入，而不是再次覆盖 chat-owner。自动通过好友申请随后已按正确安全源码合入并于 18:49 上线，详见下面记录。


## 2026-10-21 最小范围发布

上线时间：18:49:19（Asia/Taipei）。仅替换并重启 `99chat-sec-chat-owner`、`99chat-sec-chat-api`。个人设置默认关闭，未修改历史账号或批量处理历史申请；未新增后台任务。

备份目录：`/srv/99chat-production/backups/friend-auto-accept-20261021-184915`。可在服务器执行 `sudo bash /srv/99chat-production/backups/friend-auto-accept-20261021-184915/rollback.sh` 恢复发布前两个二进制并重启服务；配置未变，无需数据库回滚。回滚前应检查后续是否还有其他发布，避免覆盖较新的版本。

发布后检查：三个原有服务均 active；新 owner 日志确认 `workerowner active`、12 项既有任务；30321 和 30310 探测返回预期业务拒绝码 1001/1002，无 RPC 14；截至 18:50 的发布后日志检查未发现 RPC Unavailable 或 panic。测试、发布和探测记录存于 `E:/openim/artifacts/friend-auto-accept-20261021/release/`。

用户验收入口：设置 → 好友权限 → 自动通过好友申请。截图所示客户端已有该开关，可重新进入页面或点击重试加载服务端新字段；开关开启后应由新申请验证离线自动通过。没有使用真实用户凭证代替用户进行此验收。
