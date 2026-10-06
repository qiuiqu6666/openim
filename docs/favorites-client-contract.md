# 收藏 P0 服务端最终对接契约

用户于 2026-10-04 提供的最终部署契约，来源为服务端 `chat/docs/client/favorites.md`。本契约优先于早期功能设计；前端按以下地址、能力和接口对接。

2026-10-04 真实接口检查补充了下面的 block ID、空封面、发送租约和删除冲突响应规则。已确认的服务端签名地址及删除重放缺陷、修复状态见[接口深入检查记录](favorites-interface-audit-2026-10-04.md)。

**Chat API：** `http://8.217.191.236:10008`

| 头 | 值 |
| --- | --- |
| `operationID` | 每次请求唯一 |
| `token` | 登录返回的 `chatToken` |
| `Content-Type` | 有请求体时为 `application/json` |

用户 ID 只来自 `chatToken`。请求体里的用户 ID 不会被采用。删除收藏只删收藏记录，不删已发出的聊天消息，也不删 OpenIM 原附件。

收藏是私人副本。从消息收藏时，服务端按收藏者身份读取指定 `seq`，并核对 `conversationID`、`seq`、`clientMsgID`。文字完成后就是 `ready`。图片、视频、语音、文件先进入 `pending_archive`，原件复制并校验后才变成 `ready`。进入 `pending_archive` 之后的普通撤回不取消归档。取消息时已经撤回，则拒绝收藏。

发送仍由客户端 OpenIM SDK 完成。`prepare-send` 只固定内容版本并签发短时下载地址。

P0 类型：`text`、`image`、`video`、`audio`、`file`、`note`、`link`。定位、名片、合并消息、标签和分享卡片未开放。请求里带 `tagIDs` 返回 `1001`。

## 配额

`GET /chat/favorites/quota`

默认每个用户 5000 条、5 GiB。图片 20 MiB，视频和普通文件 100 MiB，语音 20 MiB，文字 UTF-8 64 KiB。准备下载租约 10 分钟。

`supportsFavorites` 与 `supportsPrepareSend` 都为 `true` 时，才打开收藏和快捷发送。未拿到能力时不要退回本地假收藏。

## 列表

`GET /chat/favorites?cursor=<opaque>&limit=30&q=<keyword>&kind=image&baseline=<syncAt>`

`limit` 为 1–100，省略时 30。第一页不带 `cursor`，`syncAt` 是这次查询开始时的服务器时间。下一页把该值原样放进 `baseline`，响应继续回传它。`nextCursor` 没有下一页时为 `null`。

搜索只查本人的标题、正文、文件名和来源展示名，关键词最长 64 个字符。

| 字段 | 含义 |
| --- | --- |
| `id` | 收藏 ID |
| `kind` | 类型 |
| `title` | 标题，可为空 |
| `summary` | 摘要 |
| `coverAssetID` | 封面资产，可为空 |
| `status` | `pending_archive`、`ready`、`archive_failed` |
| `version` | 每次修改递增 |
| `contentRevision` | 当前不可变内容版本 |
| `provenance` | `serverVerified` 或 `userCreated` |
| `createdAt` / `updatedAt` | UTC 毫秒 |

## 增量

`GET /chat/favorites/changes?updatedAfter=<syncAt>&limit=100`

`limit` 为 1–100，省略时 100。事件有 `upsert` 和 `delete`。删除事件只有 `id`、`version`、`updatedAt`。

返回条数小于 `limit` 时，这次增量已经拉完。`syncAt` 是服务器当前时间，下次增量仍用它。

返回条数大于或等于 `limit` 时，用本页 `syncAt` 继续请求，直到某一页条数小于 `limit`。页满时 `syncAt` 就是最后一条的 `updatedAt`。同一毫秒的记录会全部放进本页，本页条数可能大于 `limit`。下一页条件是 `updatedAt > syncAt`。

`updatedAfter` 早于 30 天返回 `20064`。客户端重建收藏缓存，再重放自己未提交的操作。`updatedAfter=0` 是全量回补。

变更后服务端发业务通知，key 为 `favoriteChanged`，内容只有 `id`、`version`、`operation`。通知丢失时用增量补齐。

## 详情

`GET /chat/favorites/{id}`

`data.item` 在列表字段之外还有 `schemaVersion`、`totalBytes`、`content`、`assets`、`source`。`content.blocks` 按类型带文字、`assetID`、文件名或链接。`assets` 带 `mimeType`、`sizeBytes`、`sha256`、宽高和 `durationMs`。`source` 只在从消息收藏时有会话和原消息定位，发送时不要带上。

pending_archive / archive_failed 可能返回 `content:null`、`assets:[]`、`contentRevision:""`；客户端将未生成的内容版本视为 null，正常显示保存中或归档失败，仍禁止发送。

## 从消息创建

`POST /chat/favorites`

```json
{
  "clientRequestID": "ea267930-d049-4a0e-8b5c-a69a132c8cec",
  "origin": "message",
  "source": {
    "conversationID": "si_a_b",
    "clientMsgID": "m_origin",
    "sequence": 101
  }
}
```

`clientRequestID` 必须是 UUID。同一用户、同一操作、同一 ID 和同一请求体重试，返回第一次的结果。请求体不同返回 `20062`。

同一条未删除消息再次收藏返回 `20051`，`data.item` 是已有收藏。文字直接 `ready`。媒体返回 `status=pending_archive` 和 `jobID`。

## 自己创建

`origin` 为 `userCreated`。`kind` 为 `note`、`link`、`image`、`video`、`audio` 或 `file`。

笔记和链接直接提交 `content.blocks`。媒体先上传，`content` 里的 `assetID` 必须出现在 `assetIDs` 或已完成的 `uploadIDs` 里。链接只接受 `http` 和 `https`。

**每个 block 必须携带非空 `id` 和 `type`。** 部署服务端的实际校验会拒绝缺少 `id` 的 block，并返回 `1001 / block is invalid`。新建与编辑均适用；同一次请求重试保留原 ID 和原正文。例如笔记：

```json
{
  "clientRequestID": "f5ab8512-d158-445a-ac76-c5bb4ffb4c46",
  "origin": "userCreated",
  "kind": "note",
  "title": "笔记",
  "content": {"blocks": [{"id": "b1", "type": "text", "text": "待办事项"}]}
}
```

成功响应中的可选 `coverAssetID` 可能为 `""`，客户端按无封面处理；错误类型和必填字段仍严格校验。

## 上传

`POST /chat/favorites/uploads`

```json
{
  "clientRequestID": "4b7c4fbd-dcd6-4705-9c88-c86e17c77e01",
  "fileName": "meeting.m4a",
  "declaredMimeType": "audio/mp4",
  "declaredSizeBytes": 5242880,
  "purpose": "favorite_original"
}
```

`purpose` 还可以是 `image`、`video`、`audio`、`file`。响应有 `uploadID`、`uploadURL`、`expiresAt`、`maxSizeBytes`。客户端把原件 PUT 到 `uploadURL`。24 小时内未完成会释放预留配额。

PUT 使用原件实际 MIME，并遵守服务端返回的签名请求头。媒体请求不携带 Chat token。`uploadURL` 必须是客户端可访问的完整签名地址；不能签发服务端内部 localhost 地址，也不能由前端替换签名地址的 host。

`POST /chat/favorites/uploads/{uploadID}/complete`

```json
{"clientRequestID": "4b7c4fbd-dcd6-4705-9c88-c86e17c77e01"}
```

成功返回 `assetID`、`mimeType`、`sizeBytes`、`sha256`、宽高、`durationMs`、`fileName`。视频另有 `coverAssetID`，创建视频收藏时写进 block 的 `coverAssetID`。上传完成还不等于收藏创建完成。

## 修改和删除

`PATCH /chat/favorites/{id}`

```json
{
  "clientRequestID": "b562d6e6-687a-4c47-920f-c49c42f3ea4d",
  "expectedVersion": 3,
  "title": "新的标题"
}
```

版本一致才更新并递增 `version`。正文变化时生成新的 `contentRevision`。版本冲突返回 `20061`，`data.item` 是当前记录。客户端保留本地编辑内容。

`DELETE /chat/favorites/{id}?clientRequestID=<uuid>&expectedVersion=3`

本人已经删除时仍然成功。他人 ID 返回 `20050`。

实际 DELETE 的版本冲突响应可能只有 `20061` 和版本提示，没有 `data.item`；客户端先只读获取最新详情并保留选择，用户重新确认后才提交新版本。读取失败时不得重复提交已知冲突的旧版本。

`POST /chat/favorites/batch-delete`

```json
{
  "clientRequestID": "c0c0c0c0-c0c0-4000-8000-000000000001",
  "items": [{"id": "fav_01", "expectedVersion": 3}]
}
```

最多 100 条。有任何一条不属于本人时，整单返回 `20050`。否则逐项返回 `deleted`、`alreadyDeleted` 或 `versionConflict`。

部署响应逐项使用 `result` 与 `version` 字段，冲突项可能没有 `item`。客户端按需只读补齐详情，单项补齐失败不撤销已经确认成功的删除。相同请求 ID 重放必须返回原逐项结果；当前部署存在重放 `items: []` 的缺陷，修复前客户端不能将空结果判为全部删除成功。

## 预览和发送准备

`POST /chat/favorites/{id}/asset-access`

```json
{"assetID": "ast_01"}
```

返回短时 `url`、`sha256`、`sizeBytes`、`expiresAt`。过期后重新调用。

`POST /chat/favorites/{id}/prepare-send`

```json
{
  "clientRequestID": "d3df46ec-ed8a-4d15-abfa-dc0d9956d67f",
  "sendAttemptID": "a75b33c0-16d4-4de7-80e0-d4e4236734d3",
  "expectedContentRevision": "rev_02"
}
```

响应有 `prepareID`、`contentRevision`、`expiresAt`、`sendContent`、`downloads`。`sendContent` 只有类型和 blocks。`downloads` 是原件短时地址，不要写进聊天消息。同一 `sendAttemptID` 在租约内重放，到期时间不变。同一请求 ID 在过期后返回 `20063`。过期后用新的 `clientRequestID`、原来的 `sendAttemptID` 和原来的 `contentRevision` 可以重新准备。

实际 `downloads[]` 可省略逐项 `expiresAt`，此时继承顶层 prepare 的 `expiresAt`；如果逐项也返回有效期，按两者较早时间失效。`asset-access` 的独立响应仍要求自己的 `expiresAt`。

`POST /chat/favorites/{id}/retry-archive`

```json
{"clientRequestID": "f0fa5bc9-1e38-4d6b-a389-90ff4b4ba695"}
```

只重试 `archive_failed`。原件还在时回到 `pending_archive`。原件不在返回 `20056`。

## 错误码

| `errCode` | `errMsg` | 情况 |
| --- | --- | --- |
| `1001` | `ArgsError` | 参数、游标、UUID 或链接不合法 |
| `1501`–`1507` | token 错误名 | 登录态无效 |
| `20050` | `FavoriteNotFoundOrForbidden` | 不存在，或不是本人的收藏 |
| `20051` | `FavoriteAlreadyExists` | 这条消息已经收藏，`data.item` 为已有项 |
| `20052` | `SourceNotAccessible` | 会话、序号或消息对不上 |
| `20053` | `SourceRevoked` | 取消息时已经撤回 |
| `20054` | `UnsupportedContent` | 类型不支持 |
| `20055` | `ProtectedContent` | 阅后即焚或私密消息 |
| `20056` | `AssetMissing` | 原件不存在 |
| `20057` | `ArchiveFailed` | 当前状态不能重试归档 |
| `20058` | `MediaTooLarge` | 超过大小上限 |
| `20059` | `MediaInvalid` | 无法解码或格式不对 |
| `20060` | `QuotaExceeded` | 超过条数或容量 |
| `20061` | `VersionConflict` | 版本已变化 |
| `20062` | `IdempotencyConflict` | 同一个请求 ID 对应了不同内容 |
| `20063` | `PrepareExpired` | 发送准备已过期 |
| `20064` | `CursorExpired` | 增量水位太旧 |
| `20065` | `RateLimited` | 写操作超过每分钟 60 次 |
| `20066` | `TemporaryUnavailable` | 上传或准备暂时不能完成 |
| `20067` | `FavoriteRequestDoneDeleted` | 这个请求对应的收藏已经删除 |
