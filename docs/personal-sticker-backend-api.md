# 个人表情收藏后端接口

本文件记录后端确定的接口契约。公共地址、鉴权请求头与响应外壳沿用现有业务接口；请求使用 `chatToken`。用户 ID 只从已验证的 token 获取，不采用请求体中的用户 ID。

收藏按当前登录用户保存，换设备后重新拉取列表即可恢复。删除收藏只删除收藏记录，不撤回或破坏已经发出的消息。

图片和 GIF 发送仍用 OpenIM `createFaceMessage`，`data` 使用这里返回的稳定 `mediaURL`。短视频不得放进 `createFaceMessage`；发送前下载 `mediaURL` 到本地，再用现有 `createVideoMessageFromFullPath`。

## 媒体

服务端读取对象内容判断类型，不采用扩展名或客户端声明的 MIME。

| 类型 | `mediaType` | 内容 | 上限 |
| --- | --- | --- | --- |
| 静态图片 | `image` | PNG、JPEG、WebP，且能解码 | 10 MiB |
| 动图 | `gif` | GIF 原件，不转成静态图 | 10 MiB |
| 短视频 | `video` | MP4，视频轨 H.264；有音轨时必须是 AAC，可以没有音轨 | 20 MiB、15 秒 |

视频必须能解码。服务端生成 JPEG 封面，`thumbnailURL` 只在视频上有值，图片和 GIF 为 `null`。`durationMs` 只在视频上有值，且大于 0。

`mediaURL` 和 `thumbnailURL` 是 OpenIM 的稳定对象地址，形如 `{OpenIM API}/object/{对象名}`。不要把会过期的签名地址写进收藏或消息。

配额默认每个用户 300 条，媒体总大小 1 GiB。这两项和单文件上限都在 `chat-rpc-chat.yml` 的 `sticker` 里配置。

## 收藏对象

```json
{
  "id": "st_...",
  "mediaType": "gif",
  "mediaURL": "http://8.217.191.236:10002/object/im_1/a.gif",
  "thumbnailURL": null,
  "mimeType": "image/gif",
  "sizeBytes": 281000,
  "width": 320,
  "height": 320,
  "durationMs": null,
  "sortOrder": 1000,
  "version": 1,
  "createdAt": 1790899200000,
  "updatedAt": 1790899200000
}
```

`id` 是收藏记录 ID。新收藏排在当前列表最前面。时间为 UTC 毫秒。

## 获取列表

`GET /chat/stickers?cursor=<opaque>&limit=50`

`limit` 范围 1–100，省略时为 50。不传 `cursor` 表示第一页；下一页原样传上一页的 `nextCursor`。没有下一页时 `nextCursor` 为 `null`。排序按 `sortOrder`、`createdAt`、`id` 升序，只返回当前用户记录。

```json
{
  "errCode": 0,
  "data": {
    "items": [],
    "nextCursor": null
  }
}
```

客户端本地缓存按账号和业务服务地址隔离；切换账号时清除上一账号的内存列表。

## 创建收藏

`POST /chat/stickers`

媒体先通过现有 OpenIM 上传。本接口只接收当前用户自己的对象。

```json
{
  "mediaID": "im_1/a.gif",
  "clientRequestID": "04be0d24-0d71-4c3b-941c-0d5850e326f1"
}
```

`mediaID` 是 OpenIM 对象名，必须以当前用户 ID 加 `/` 开头。上传接口如果只返回 URL，可以改传 `mediaURL`，但只能是本服务允许的 OpenIM `/object/` 地址；外部 URL 拒绝。两个字段都传时以 `mediaID` 为准。

`clientRequestID` 必须是 UUID。同一用户用同一个值重试时返回第一次的收藏，不重复创建。同一用户收藏相同文件内容时返回已有记录。成功响应的 `data.item` 为完整收藏对象。

上传成功但创建收藏失败时，使用同一 `clientRequestID` 重试。孤立上传与普通消息附件共用对象存储，服务端不因“尚未收藏”删除原文件。

## 删除收藏

`DELETE /chat/stickers/{id}`

只能删除自己的收藏。记录不存在时仍返回成功；成功响应 `data` 为 `{}`。原媒体继续保留以保证历史消息有效。收藏服务生成的视频封面在没有收藏继续引用之后，延迟 7 天删除。

## 调整排序

`PUT /chat/stickers/order`

```json
{"ids": ["st_02", "st_01", "st_03"]}
```

`ids` 必须恰好包含当前用户全部收藏 ID，不能缺少、增加或重复。数组顺序即新的显示顺序，服务端在一个事务内更新。若列表已被其他设备修改，返回 `20025`；客户端重新拉取后再提交。

## 错误码

| `errCode` | `errMsg` | 情况 |
| --- | --- | --- |
| `1001` | `ArgsError` | 缺少 token、`limit`、游标、`clientRequestID` 或对象名不合法 |
| `1501`–`1507` | token 错误名 | 登录态无效 |
| `20012` | `Forbidden` | 对象不属于当前用户，或 `mediaURL` 不是允许的地址 |
| `20021` | `StickerNotFound` | 媒体不存在，或此 `clientRequestID` 对应的收藏已经删除 |
| `20022` | `StickerUnsupportedMedia` | 格式不支持，或图片、GIF、视频不能解码 |
| `20023` | `StickerTooLarge` | 超过大小或视频时长上限 |
| `20024` | `StickerQuotaExceeded` | 超过条数或总字节配额 |
| `20025` | `StickerOrderConflict` | 排序时收藏列表已经变化 |

## 客户端接入要点

- 收藏面板共用一个列表显示图片、GIF 和短视频。视频使用 `thumbnailURL` 预览，不把 MP4 当作图片展示。
- 图片/GIF 的发送 URL 使用 `mediaURL`；短视频下载到临时文件后通过现有视频消息链路发送，保留现有缩略图和时长处理。
- 创建请求生成并保存 UUID，在网络重试时复用同一个 `clientRequestID`。
- `20025` 后重新获取完整列表，再让用户确认或重新提交排序。
