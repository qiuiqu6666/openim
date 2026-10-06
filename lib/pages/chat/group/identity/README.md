# 群成员身份响应

`userID` 始终为原 OpenIM 路由标识，新用户使用 `im_` 开头的标识，旧用户保留数字号；`account` 是成员响应中的独立可选公开账号，现行格式为 `@` 加 10 位字符。应用自有模型扩展 `GroupMembersInfo`，保留额外 JSON 字段，不修改 SDK 或其本地数据库，也不生成、解码或用公开账号替换 IM ID。

服务端负责公开账号权限：`lookMemberInfo=0` 时群成员可取得 `account`；启用成员隐私时只有群主、管理员及系统管理员可取得。接口不返回该字段时，模型保持 `null`，序列化不补 `account`。调用方不可通过通用用户资料查询补齐隐藏字段；权限变化时应清除已有展示资料并重新读取。

| `lookMemberInfo` | 查看者 | 有公开账号的成员响应 |
| --- | --- | --- |
| `0`（查看成员开启） | 群内任何成员 | 返回 `account` |
| `1`（成员隐私开启） | 群主 `100`、管理员 `60`、系统管理员 | 返回 `account` |
| `1`（成员隐私开启） | 普通成员 `20` | 不带 `account` |

没有公开账号的用户在两种开关下都不带 `account`。缺字段不等于接口失败，也不能仅凭客户端角色推断或补齐字段。

新建群在 `/group/create_group` 未传 `lookMemberInfo` 或传 `0` 时，服务端保存并返回 `1`。客户端采用返回的群资料；群主和管理员之后仍通过现有 `/group/set_group_info` 将其改为 `0`。已有群不由客户端统一修改。

`GroupMemberIdentitySource` 使用 `Config.imApiUrl`、当前 `DataSp.imToken`、JSON 和每次独立的 `operationID`，只读取以下群接口：

| 方法 | 路径 | 请求字段 | 成员位置 |
| --- | --- | --- | --- |
| `list` | `/group/get_group_member_list` | `groupID`、`pagination`、`filter`、`keyword` | `members` |
| `members` | `/group/get_group_members_info` | `groupID`、`userIDs` | `members` |
| `incremental` | `/group/get_incremental_group_members` | `groupID`、`versionID`、`version` | `insert`、`update` |
| `batch` | `/group/get_incremental_group_members_batch` | 当前 IM `userID`、`reqList` 增量游标 | `respList[groupID].insert/update` |

每次请求捕获当前账号、SDK 登录账号、IM token 与服务器地址；返回成功或错误时身份已变化则抛出 `GroupMemberIdentitySessionChanged`。列表只接受请求群的成员；指定成员查询还限制请求中的 `userIDs`；增量和批量响应只接受对应请求群的变更，批量中额外的群不会进入结果。本模块不维护跨群账号缓存；接口失败不回退为另一次身份查询。

群成员资料页每次打开都通过 `members()` 读取原始 `data.members[].account`，包含从群内打开的好友和本人；没有字段时隐藏聊天号。SDK `getGroupMembersInfo` 继续提供入群时间、邀请人等元数据，SDK 成员模型没有 `account`。Chat `/user/find/full` 可以核对业务资料，但不是群成员资料页聊天号的来源；非群资料页面保留原有公开账号流程。

`lookMemberInfo` 切换不会增加成员版本号。成员列表在开关变化后撤销已加载的账号，从 `/group/get_group_member_list` 第一页重新读取并重新分页，不以增量版本跳过刷新。群资料、成员列表和群设置预览也在本人角色及本人资料更新后重新查询群接口；系统管理员资格不由客户端自造判定。关闭、离群、会话变化或新的权限请求会废弃旧结果。

HTTP 使用模块自己的 Dio，沿用共享网络选项及超时，不挂接共享认证拦截器。只有完成以上四维会话检查后，当前响应中的 `1506` / `20101` 才按原有 HTTP 语义触发退出通知。测试注入 `poster` 时默认不触发真实退出通知，可注入 `onAuthFailure` 独立验证该行为。

请求 schema 已于 2026-10-05 只读核对后端 OpenIM API 与协议定义。单元测试位于 `test/pages/chat/group/identity/`，覆盖账号可选字段、原 ID 保留、四接口 schema、原始 HTTP JSON、无权响应和会话变化。

2026-10-06：依据明确的后端契约补充新群隐私默认值、开关含义、无账号合法省略及不增加成员版本的规则；群成员资料、列表与设置预览的配套回归包含在 277 项通过、4 项可选预览跳过的整组验证中。公开账号来源仍为原始群接口，不修改服务端、SDK 或 IM 标识。
