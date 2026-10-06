# 朋友圈隐私名单

当前后端支持两类逐人设置命令：`blocked-viewers`（不让其看本人动态）、`hidden-authors`（不看其动态流内容）。每个命令均使用对方 OpenIM userId、当前 `chatToken` 与新的 `operationID`。`GET /moments/settings` 只返回历史范围、封面和版本，不承担名单读取。

## 职责

- `data/moments_privacy_selections.dart`：本机已确认选择及单项变更模型。
- `data/moments_privacy_selection_store.dart`：按账号和业务服务器隔离的 SharedPreferences 快照，以单项变更合并写入。
- `data/moments_privacy_selection_controller.dart`：读取、已确认变更及本机持久化重试；保护迟到结果和会话切换。
- 现有 `../moments_privacy_list_page.dart`、`../moments_settings_page.dart`：名单选择、取消与范围设置界面。
- `widgets/moments_peer_privacy_controls.dart`：联系人详细资料内两项逐人权限开关；读取本机记录，沿用同一仓库命令与会话边界。
- 现有 `lib/services/moments_repository.dart`：保留兼容入口、身份检查和 SDK 查询失效协调，委托独立数据控制器保存名单。本轮只局部修正调用桥接，保留既有 SDK 订阅和权限世代；整个仓库及其他朋友圈数据文件的目录迁移另行执行。

## 数据边界

本机列表只记录在此设备上获得成功响应的 PUT/DELETE，不能推断服务器全部名单，不能授予动态阅读权，也不参与构造后台 ACL。空本机记录显示“未选取”，添加与取消操作可正常使用。

设置接口的缺失字段不会清空本机记录。操作失败或结果未知不改变已确认成员，用户可显式重试同一人、同一方向的幂等命令。后端已成功但本机保存失败时，保留内存确认结果并单独重试保存，不重新发送已经成功的命令。

服务器与账号共同定义持久化归属，token 更新不改变归属。会话变化只清当前内存投影；迟到结果不得写入新账号的画面。持久化任务使用开始时捕获的固定归属。缓存内容不发送 token。

本机未记录的服务端设置可以通过选中对应好友再次 PUT，或“选择朋友移除”发送 DELETE。当前契约没有完整名单读取能力，客户端不调用虚构的 GET 名单接口。

## 验证

新测试归属 `test/pages/moments/privacy/`。存储与控制器测试使用模拟偏好和注入存储验证隔离、并发、失败及会话切换；接口测试验证四条 PUT/DELETE 路径、IM 号和鉴权；页面测试验证正常空态、逐项保存和取消。

2026-10-04：名单页面修复时隐私子模块 54 项、朋友圈整体 207 项通过；资料页接入后另增联系人权限控件 15 项，朋友圈全部 222 项继续通过，并与资料页及导航组成 258 项通过的统一回归。定向静态检查和 Android Debug APK 构建成功。线上登录态与真机验收尚未完成，详见 [客户端接入说明](../../../../docs/moments-client-integration.md) 及 [资料页验证](../../../../docs/user-profile-99chat-validation.md)。
