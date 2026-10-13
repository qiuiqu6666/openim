# OpenIM 原生恢复补丁

当前使用从官方 **v3.8.3-patch.15** 拉取并修复的 [patch15 方案](patch15/README.md)。Android 原生库已编译接入，手机 `3.0.1+2027` 实际返回 `v3.8.3-patch.15+recovery.1`；iOS 配置切换至官方 patch.15 Framework，尚待 macOS 构建和本地补丁集成。源码位于 `E:/openim/sdk-source/openim-sdk-core-recovery`，构建入口为 `patch15/build-android.ps1`。

以下内容保留为之前 **patch.12** 方案的历史记录；其未编译状态不适用于上面的 patch15 方案。

以下旧方案保存离线恢复、弱网补拉和接收队列修复的历史记录，归属原生 SDK 接入，不修改共享 pub-cache。当前接入状态以上面的 patch15 方案为准。

## 基线

- 上游仓库：<https://github.com/openimsdk/openim-sdk-core>
- 标签：`v3.8.3-patch.12`
- commit：`101cf038eb114bc58bd9298dedeff33e3b1a73f2`
- 补丁：`patches/0001-sdk-recovery.patch`
- 当前可编辑源码：`E:/openim/sdk-source/openim-sdk-core`

补丁保持公开 SDK 接口与消息协议。它传递分批补拉和主要落库错误，等待接收处理回执后推进同步位置，成功后才提交首次安装标记；为长连接请求增加截止与可取消排队，限制缺口序号生成，缩小同步锁范围。单条命令 panic 被记录为失败，接收循环继续处理下一条。

## 应用到受控源码

对上述 commit 的干净 checkout 执行：

```powershell
./native_sdk/apply-recovery-patch.ps1 -SourcePath E:/openim/sdk-source/openim-sdk-core
```

脚本只校验基线和应用补丁。已经应用时直接返回；存在其他源码修改时拒绝叠加，不做重置、覆盖或构建。补丁哈希见同目录 `patches/manifest.json`。

## 接入范围与验证

本轮仅执行格式、语法解析与补丁适用性检查，未编译或运行原生 SDK。`gofmt` 不验证类型、依赖或双平台桥接兼容性。后续在允许构建时，需要从此受控源码产出带独立版本号的 Android AAR / iOS Framework，更新受控分发依赖，再采集恢复和接收数据。不得用相同版本号静默覆盖官方缓存。

处理回执不等于跨表事务或恰好一次投递。部分写入后失败仍可能需要服务端未读校准；好友、群等现有通知处理接口没有返回错误，补丁不能确认这些内部操作全部成功。正常会话保留上游重连取 1 条、唤醒取 10 条的最新摘要策略，完整历史仍由历史查询按缺口读取。详情见 [修复记录](../docs/sdk-recovery-fixes-2026-10-13.md)。
