# 收藏服务端审阅补丁（未部署）

这些补丁针对 2026-10-04 在 `/www/wwwroot/chat` 源码与受控接口操作中确认的三个故障。本轮只在本地快照及服务器 `/tmp/favorite-public-signing-review.fP6ztX` 隔离目录准备和验证，**没有修改生产源码或配置，没有重启服务，没有运行新二进制**。是否部署、如何切换及回滚，需要另行明确决定。

2026-10-05 已核实实际启动方式，具体切换范围、配置合并、备份、验收及回滚见 [部署方案](deployment-plan-2026-10-05.md)，尚未执行。只需重启 ChatRPC，Chat API 保持运行。

## 补丁与应用顺序

| 文件 | 解决的问题 | 范围 |
| --- | --- | --- |
| `0001-favorite-public-storage-signing.patch` | 上传与原件访问返回 `localhost:10005` 签名地址，手机无法访问 | 保留内部 MinIO client，新增独立公网 signer；PUT/GET 在签名前选择 signer，签名后不替换 host |
| `0002-favorite-delete-replay-receipts.patch` | 单 DELETE 同 UUID 第二次错误返回 20067；批量 DELETE 同 UUID 第二次返回空 `items` | DELETE 重放免于“结果已删除”检查；批次保存完整逐项结果及版本，已持久回执原样返回 |
| `0003-favorite-openim-object-name-resolution.patch` | 普通聊天媒体 `/object/<name>` 是逻辑对象名，被误当 MinIO 实际 key，归档与重试失败 | 用已验证消息的 snapshot 逻辑名调用 OpenIM `/object/access_url`，限制可信存储来源后读取并生成私有副本 |
| `0004-favorite-source-error-classification.patch` | 归档来源的网络/授权/配置失败被误报 20056 | 保留安全数字诊断，只有可核实缺失才 20056，其余 20066；见 [独立说明](0004-source-diagnostics.md) |

推荐按 **0001 → 0002 → 0003 → 0004** 审阅及应用。0001 和 0002 各自可以应用到本次原始源码快照，0002 已独立做 `git apply --check`。0003 基于前两份补丁的源码状态生成，并使用 0001 的公网 signer 配置；0004 基于前三份补丁。完整顺序已在独立副本做标准 check 和应用检查。不要直接对运行中的 checkout 使用这些操作。

2026-10-05 追加的 0004 需在 0001→0002→0003 之后应用；它不解释或修复“收藏页添加图片/文件”的上传故障，仅改善聊天来源的归档/重试错误分类。本说明后面的原 41 项结果对应 0001–0003；0004 最新全量结果为 53 项检查，详见独立说明。

## 公网签名配置

`config.public-storage.example.yml` 仅提供无凭据片段，需合并到现有 `favorite` 段，不能覆盖完整配置：

```yaml
favorite:
  publicStorageURL: http://8.217.191.236:10005
```

地址必须是完整 HTTP/HTTPS 存储根地址，只允许 scheme、host、端口及可选根 `/`；拒绝用户名/密码、非根路径、query 和 fragment。配置为空保留旧内部 signer，因此仍可能返回手机不能访问的内部地址。已有内部 endpoint、bucket 和凭据保持原配置；公网 signer 使用同一组存储凭据。内部读、写、删除操作继续走原内部 client。

当前公网存储健康接口在外部与 Chat 所在服务器本机只读探测均返回 HTTP 200。这只证明端点可达；**不代表加载本补丁后的手机上传/下载或真实签名已验收**。通过反向代理使用 `/minio/...` 路径前缀不符合本补丁的根端点契约，需要另行验证和设计。

## 删除回执的安全边界

0002 只承诺：**成功持久化后的同 owner、operation、UUID 和 body，逐项结果与版本稳定重放**。原 UUID 换 body 仍返回幂等冲突。create/update 原结果已删除仍保留 20067；仅 delete/batch-delete 免于把自身删除结果当错误。

已保存批次回执重放不再读取或重新删除收藏。旧版本保存的空 batch 回执只做只读恢复：已删项返回 `alreadyDeleted`；仍有效项返回 `versionConflict`，即使当前版本正好等于旧 expectedVersion 也不执行删除；不可确认或无法持久化恢复回执时返回临时错误。客户端需重新读取正文/版本并经用户新动作决定是否删除。

`FavoriteRequest.ResultRef` 在 `pkg/common/db/table/chat/favorite.go:149` 是 Mongo BSON string，没有 SQL varchar 截断限制；`pkg/common/db/model/chat/favorite.go:105-110` 的 `SaveRequest` 是 `$set` + upsert，能补写旧空回执。本次不增加数据库字段或迁移。

**尚未解决的预存窗口：**没有跨实例的原子请求 claim，两个并发 miss 可能同时执行；删除已完成但保存回执前崩溃/保存失败可能丢失首次逐项结果，无条件 upsert 也允许并发覆盖回执。本补丁没有用内存锁或先写 pending 来宣称跨实例 exactly-once。后续需要数据库原子 claim、可恢复逐项进度及收据完成机制；不能把本次顺序重放回归测试当作该能力验收。

## 聊天媒体对象解析

OpenIM 网关 `/object/<name>` 经其 metadata controller 把 logical `Name` 转成实际 `Key` 后生成访问 URL。Chat 不直接查询存储数据库，不猜 date/userID/random key，也不把消息中的任意 URL 当下载来源。

0003 保留创建时 `owner + conversationID + clientMsgID + seq` 的原消息资格检查和 snapshot 结构。归档 job 与 `RetryChatFavoriteArchive` 均对 snapshot 的 logical name 请求 OpenIM 管理员 API 得到新 lease，再严格验证返回 URL：HTTP/HTTPS、无 userinfo/fragment、scheme/hostname/有效端口等于配置内部或公网 MinIO endpoint、路径位于配置的 `/<bucket>/`，拒绝遍历、反斜线及重定向。默认 80/443 的显式与省略形式只在来源判断中等价处理；不会改动原签名 URL。

原件 GET 不继承 OpenIM/business token 或调用方 headers，单次 30 秒超时，按原有类型限额流式限读 `limit + 1`，再进行原有媒体 Inspect，并用内部 client 写入 `favorite/<owner>/<assetID>`。重试预检查用同受控链路的 GET `Range: bytes=0-0`，原件缺失仍返回 `ASSET_MISSING`（20056），不先占用 quota 或重新排队。已有旧 snapshot 无需新增 key 字段。已有 `archive_failed` 项不会自动批量恢复，需要用户发起重试。

新增 `/object/access_url` 的共享 caller 日志仅记录 API 名称与耗时，失败使用泛化错误；响应签名 URL、上游错误详情和 JSON 原文不进入该调用日志。存储网络错误同样避免携带带 query 的 URL。

该桥接只覆盖已核实的 MinIO path-style bucket endpoint。不同存储引擎、bucket 迁移、代理路径前缀、virtual-host bucket URL 会被拒绝，需要额外明确配置与验证；不能放宽为允许任意外部 URL。

## 已完成的验证

所有改动 Go 源码在隔离目录执行 gofmt。Go `go1.27.1`，生产 module 源码只读；模块缓存、编译缓存及临时文件设到 `/tmp/favorite-public-signing-review.fP6ztX`，未修改生产 go.mod。使用 overlay 编译真实包，不是简化替代 harness。

最终执行：

```sh
go test -overlay /tmp/favorite-public-signing-review.fP6ztX/bridge-overlay.json \
  ./internal/rpc/chat ./pkg/common/imapi -count=1
go build -overlay /tmp/favorite-public-signing-review.fP6ztX/bridge-overlay.json \
  -o /tmp/favorite-public-signing-review.fP6ztX/chat-rpc-review-0003 \
  ./cmd/rpc/chat-rpc
```

结果：`internal/rpc/chat` **39 个测试项通过（含既有子测试）**，`pkg/common/imapi` **2 个通过**，共 **41 项通过**；chat-rpc 二进制构建成功且未启动。新增 15 个测试函数，包含公网 GET/PUT 签名 host 与内部 client 不变、非法配置、单删/完整 partial 批次/旧空 receipt 重放、真实 job 原件解析及私有复制、旧 snapshot retry、受信任默认端口、来源限制、跳转与超限、管理员接口与签名错误脱敏。其余 26 项为上述真实包的已有测试。

此外完成 0001/0002 各自原始快照 `git apply --check`、0002 独立副本应用，以及完整 0001→0002→0003 副本 dry run；最终 patch 生成自上述 gofmt 后的验证文件。测试使用本地 httptest 及假凭据，没有向真实存储上传、没有实际发送 IM 消息。

## 仍待明确部署后验收

补丁通过源码、隔离测试和编译验证，不能据此宣称生产故障已修复。用户批准部署后需要在受控记录上验证手机图片/文件上传、complete/create/detail、asset-access 与 prepare 返回可访问签名，单删/部分冲突批删同 UUID 重放，以及普通聊天图片/文件归档和历史失败项手动重试。保留前一二进制与配置以供回滚；测试记录完成后清理。真实语音/视频、移动设备 UI 和收藏发送到会话还应按前端集成验收清单验证。
