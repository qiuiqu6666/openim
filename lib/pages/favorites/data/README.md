# 收藏数据与恢复

- `favorite_change_synchronizer.dart` 消费 updatedAfter/syncAt 时间分页，20064 时请求重建并从 0 回补；每页先提交再推进。
- `favorite_sync_state.dart` 保存轻量记录和版本墓碑，拒绝旧版本和过期时间水位。
- `favorite_sync_binding.dart` 适配现有 SDK 业务通知、重连与应用前台生命周期；通知仅作提示，后台停周期请求，不替换 SDK listener。
- `favorite_mutation_outbox.dart` 串行持久保存账号/服务隔离的收藏写入正文及 UUID，不保存 token/上传 URL/下载授权。确认前重放原请求；确认后原子保存同 UUID 的完成依据，防止展示缓存清理失败后误用旧请求。它不负责 SDK 消息发送。
- `favorite_mutation_replayer.dart` 按原正文和 UUID 恢复收藏写入，版本冲突保留正文；不调用 prepare-send 或 SDK。
- `favorite_media_upload.dart` 管理上传初始化、PUT、完成资产及恢复检查点。素材身份包含实际字节摘要与声明 MIME；改变声明不复用旧初始化正文的 UUID。上传授权过期或完成请求明确返回 AssetMissing 后更新上传身份；未知完成结果仍复核原上传 ID 和 UUID。

仓储继续由既有 `lib/services/favorite_repository.dart` 持有账号、搜索、分页、归档与操作状态。本轮把新同步、版本和持久化职责拆入独立模块，保留既有构造和共享入口，避免同时迁移 UI 调用、媒体恢复记录和发送日志键。后续仓储分拆按列表查询、归档上传和收藏写入分别提取，先明确每类状态与资源的所有者，再集中目录。

双能力和批量删除结果模型位于 `../models/`。UI 不能直接处理通知中的伪造正文，也不能因能力错误退回内存收藏。

详情返回前也校验删除墓碑和最新已知版本，迟到正文不能覆盖较新的详情或重新打开已删除项。带明确版本的删除直接提交 DELETE，避免先取不存在的详情而破坏幂等删除。同一写入尚在处理时不允许并发替换 UUID；归档轮询逐项处理错误，单个失效项不会阻断其余原件归档。

新增数据测试位于 `test/pages/favorites/data/`，既有 API/仓储兼容测试仍在 test 根目录。测试验证水位推进、同毫秒满页、删除墓碑、跨账号、存储失败、通知合并和 outbox 幂等恢复，不调用真实用户写接口。
