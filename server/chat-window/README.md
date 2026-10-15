# 消息窗口服务端修复

目标源码：`/srv/99chat-production/app/source/open-im-server`（124.156.151.7）。独立构建目录：`/home/ubuntu/chat-window-server-20261015`。

`history-coverage.patch` 修复两处错误覆盖证明：MongoDB 未落盘/预分配空槽不能转换成删除占位；控制器缺少请求序号时返回可重试错误。明确删除、旧版 `{msg:null}` 物理删除、个人可见性范围和撤回继续有效。新增物理删除标记兼容旧版读取。没有数据库迁移、协议变更或新服务。

真实执行结果：Go 1.26，`go test -race ./pkg/common/storage/controller ./pkg/common/storage/database/mgo ./internal/rpc/msg -count=1` 通过。包含 Mongo 驱动模拟响应的“未落盘 → 稍后落盘”重试、空槽/撤回先于正文/旧删除标记区分及原有权限边界测试；未进行线上消息故障注入。

候选二进制：`/home/ubuntu/chat-window-server-20261015/openim-rpc-msg.chat-window`

SHA256：`503ceb55ce9b5ce7965f652282545799aa0c70d72d7cb6e666c8f4aafd68b33c`

回退二进制：`/home/ubuntu/chat-window-server-20261015/rollback/openim-rpc-msg`

SHA256：`bb2b37ff97e4e9e2080c6062317a258238801896ed3cd65131c260ce3d50ef1e`

上线影响范围：只替换并重启 `openimservice-openim-rpc-msg-0.service`；网关与消息投递服务继续运行。重启期间历史拉取/发送请求可能短暂重试。上线前核对原始源码/二进制哈希；失败立即切回备份。`source-receipt.json` 保留逐文件前后哈希；其他源码改动不在本补丁范围。

2026-10-15 01:10 UTC 已获用户批准并完成上线。原进程 13228 替换为 291162，运行二进制哈希与候选包一致，重启后及持续复查均为 active/running、NRestarts=0，两个监听端口连接成功。随后 Android 实际 SDK 在两个已有群完成远程窗口读取（40 条，无缺口，序号有序、ID 唯一）。原始部署记录保存在本任务验证目录的 `deployment-result.json`；未在生产环境注入崩溃或高频测试消息。
