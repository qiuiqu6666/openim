# 朋友圈权限同步

服务端是权限名单的来源。进入权限设置、逐人名单或联系人权限控件时，读取 `GET /moments/settings`；成功后刷新按账号、业务服务器隔离的本地缓存。读取失败保留已有缓存并显示重试状态。客户端名单不授予动态阅读权限，资源访问仍由服务端 ACL 检查。

## 接口

现有 GET、PATCH 和逐人 PUT/DELETE 响应增加：

- `blockedViewerIDs`：不让其看本人朋友圈的完整用户 ID 列表。
- `hiddenAuthorIDs`：不看其朋友圈的完整用户 ID 列表。
- `privacyListsLoaded`：完整名单标记，确保空数组被序列化为 null 或省略时仍能清除过期缓存。
- `updatedAt`：服务端最后修改时间，UTC Unix 毫秒。旧记录为 0，客户端不显示虚构时间。

现有 `version` 用于排除较旧响应。逐人命令幂等，重复同方向设置不会更改版本或更新时间。未提供名单的旧接口响应继续按单项确认处理，不清空缓存、不覆盖全局设置。

## 实现边界

- `data/moments_privacy_selections.dart`：名单快照和单项确认模型。
- `data/moments_privacy_selection_store.dart`：按账号和服务器加锁持久化，支持完整替换与单项合并。
- `data/moments_privacy_selection_controller.dart`：保护迟到缓存读取、进行中的写入与账号切换；保存失败保留内存状态，可仅重试本地保存。
- `lib/services/moments_repository.dart`：请求及会话边界、服务端版本检查、读取与修改竞争保护、权限变化后的内容失效。
- 设置页显示完整服务端名单人数及服务端更新时间（转换为设备本地时间）；失败时明确显示缓存状态。

测试涵盖两个独立客户端共享服务端数据、空名单删除旧缓存、迟到读取、账号切换、损坏缓存恢复、持久化失败重试，以及中英文、暗色、大文字和权限控件交互。
