# 0004：归档来源错误分类（独立补丁，未部署）

本补丁基于 0001→0002→0003 的源码状态，修正归档与 `retry-archive` 的错误分类，不改变存储来源白名单，不做数据库迁移。**它不是 2026-10-05 用户“收藏页添加图片/文件”报错的根因证明或上传修复。**新建上传、complete、create 流程另行核对；本补丁只处理聊天来源的归档诊断。

## 确定的问题

0003 中 `probeFavoriteSource` 把任何解析、网络、授权、HTTP 或白名单错误都转成 20056，`RetryChatFavoriteArchive` 外层再次无条件转成 20056。并且 AccessURL caller 脱敏时丢弃了上游数字错误码，因此授权故障、过期 lease、存储故障、配置不匹配都可能误报“收藏原件不可用”。

## 返回与安全日志

| 情况 | 返回 | 可记录字段 |
| --- | --- | --- |
| AccessURL 明确返回元数据 1004 | 20056 | metadata、metadata_not_found、upstreamCode=1004 |
| 已验证存储 URL，HTTP 404 且有限 XML `Code=NoSuchKey` | 20056 | storage、object_not_found、httpStatus=404 |
| 普通/代理 404、NoSuchBucket、410、401/403、5xx、重定向 | 20066 | storage、http_unavailable、数字 HTTP 状态 |
| 网络失败、来源 endpoint/bucket/path 白名单拒绝 | 20066 | storage/network_error 或 policy/origin_or_path_rejected |
| 元数据授权、网络、内部错误，空/过期 lease | 20066 | metadata、固定类别、数字上游码或 HTTP 状态 |

所有日志类别为固定字符串。签名 URL、对象名、query、token、headers、上游原始 errMsg/errDlt/响应体和带 URL 的 transport error 不写入这些诊断日志。只在 `/object/access_url` 调用边界保留脱敏后的数字错误码；该接口的 HTTP 非 200 响应也不会因伪造 `errCode=0` 被当作成功 lease。

错误 body 的 XML 解析最多读取 8 KiB，仅检查 `Code`；不会记录 body 或 `Message`。仅凭 HTTP 404/410 不推断原件丢失。所有失败仍在占用 quota、重新排队或重开归档项之前返回。

## 1004 的核实范围

已只读核对本次部署 OpenIM 源码链：`internal/api/third.go:107` AccessURL → `internal/rpc/third/s3.go:178` → `pkg/common/storage/controller/s3.go:92-96` → `cache/redis/s3.go:72-75` → `database/mgo/object.go:86-91` 根据 `name + engine` 查询对象元数据。`mongoutil` 将 `mongo.ErrNoDocuments` 转为 1004；此 handler/controller 没有以 1004 遮蔽对象权限的逻辑。管理员 token 校验在 Gin middleware 及 auth 服务单独执行，签名/过期等错误有独立 token 码。

**1004 只证明该 engine/name 元数据查询未找到，不能证明物理 bytes 已删除。**元数据缺失、engine 配置改变或不同存储部署也可导致不可解析；诊断类别明确叫 `metadata_not_found`，不叫 `deleted`。换版本/存储引擎/鉴权实现时应重新核实错误码语义。

## 隔离验证

只写本地 `.dart_tool/favorite-public-storage-patch-20261004/diagnostics-20261005` 与服务器 `/tmp/favorite-public-signing-review.fP6ztX/diagnostics-20261005`，未写生产源码或配置，未重启或运行新二进制。

所有改动 Go 文件已在隔离目录 gofmt。通过 Go overlay 测试真实 `internal/rpc/chat` 与 `pkg/common/imapi` 全量测试：**41 个顶层测试函数、12 个子测试，共 53 项检查通过**。其中新增 4 个顶层函数；增加 8 种 storage 状态的实际 retry route 回归、resolver/network/policy 回归、metadata 数字错误分类与脱敏、非 200 HTTP 不可假成功 lease。既有 job 私有归档、端点/大小/跳转限制与 lease 脱敏测试继续通过。

完整 `./cmd/rpc/chat-rpc` 构建通过，产物 `/tmp/favorite-public-signing-review.fP6ztX/chat-rpc-review-0004` 未启动。0004 单独对“已应用 1→2→3”的副本及完整 1→2→3→4 顺序做 apply check/dry run，通过后与测试 overlay 源码一致。测试只使用 httptest 和假凭据，无真实上传、收藏写入或 IM 发送。

```sh
go test -overlay /tmp/favorite-public-signing-review.fP6ztX/diagnostics-overlay.json \
  ./internal/rpc/chat ./pkg/common/imapi -count=1
go build -overlay /tmp/favorite-public-signing-review.fP6ztX/diagnostics-overlay.json \
  -o /tmp/favorite-public-signing-review.fP6ztX/chat-rpc-review-0004 ./cmd/rpc/chat-rpc
```

部署后仍需受控验证不同来源故障的实际错误码和脱敏日志；这些隔离测试不等同于生产部署或手机上传验收。
