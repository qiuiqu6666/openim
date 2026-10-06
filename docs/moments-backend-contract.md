# 朋友圈当前后端契约

来源：项目负责人于 2026-10-03 提供的已实现后端说明，2026-10-04 补充隐私名单行为。本文记录接口事实；客户端字段解析补充与联调要求见 [客户端接入说明](moments-client-integration.md)，完整产品设计见 [朋友圈完整设计](moments-full-design.md)。

## 身份、能力与当前范围

公共地址和公共请求头沿用后端接口目录 `/www/wwwroot/chat/docs/client/README.md`。当前 Chat API 为 `http://8.217.191.236:10008`。`token` 使用当前登录用户的 `chatToken`。操作者由登录态决定，请求体里的作者 ID 不会被采用。

朋友圈能力以 `GET /moments/capabilities` 的 `supportsMoments` 为准。本阶段开放图文，不开放视频和举报。

多端同步：服务端向当前可读受众发送 OpenIM 业务通知，`key` 为 `moments`。`data` 只有 `eventId`、`momentId`、`action`、`aggregateVersion`、`occurredAt`。收到后重新拉取动态、互动和通知。

## 列表

- `GET /moments/feed?limit=20&cursor=`
- `GET /moments/users/{userId}?limit=20&cursor=`
- `GET /moments/{momentId}`

`limit` 缺省 20，最大 50。游标原样回传。`viewerContextVersion` 与当前关系不一致时，`errDlt` 为 `CONTEXT_CHANGED`。

动态里的 `likeCount`、`commentCount` 和预览都是当前查看者能看见的互动。非好友的点赞和评论不会出现。普通查看者看不到 `audienceUserIds`。

## 发布与媒体

- `POST /moments/media/upload`，表单字段 `file` 和 `clientMediaId`。
- `POST /moments/cover/upload`，使用同一套校验。
- `POST /moments`

```json
{
  "clientRequestID": "固定任务 ID",
  "text": "今天的记录",
  "mediaIDs": ["media-id"],
  "visibility": "FRIENDS",
  "audienceUserIds": []
}
```

可选请求头 `Idempotency-Key`，有值时必须等于 `clientRequestID`。

`GET /moments/publish-results/{clientRequestId}` 查询本次发布。`status` 为 `NOT_FOUND`、`PROCESSING` 或 `SUCCEEDED`。

媒体地址为 `/moments/media/{mediaId}/content`，缩略图加 `variant=thumb`。读取使用当前 `chatToken`，支持 `Range`。

## 互动

- `POST /moments/{momentId}/likes`
- `DELETE /moments/{momentId}/likes/me`
- `GET /moments/{momentId}/likes`
- `POST /moments/{momentId}/comments`

```json
{
  "clientRequestID": "固定评论 ID",
  "text": "回复",
  "replyToCommentID": ""
}
```

- `GET /moments/{momentId}/comments`
- `DELETE /moments/{momentId}/comments/{commentId}`
- `GET /moments/comment-results/{clientRequestId}`

失去动态阅读权后，仍可取消自己的赞、删除自己的评论。这时响应只有资源 ID 和 `removed`，没有父动态正文。

## 通知和设置

- `GET /moments/notifications`
- `POST /moments/notifications/read`

```json
{
  "notificationIDs": ["notification-id"],
  "readThroughSeq": 100,
  "seenWatermark": "列表返回的水位",
  "markThrough": true
}
```

- `GET /moments/settings`
- `PATCH /moments/settings`

`visibleRangeDays` 缺省表示不改。`coverMediaId` 为 `null` 时清除封面。允许的天数为 0、3、90、180、365。

- `PUT /moments/settings/blocked-viewers/{userId}`
- `DELETE /moments/settings/blocked-viewers/{userId}`
- `PUT /moments/settings/hidden-authors/{userId}`
- `DELETE /moments/settings/hidden-authors/{userId}`

两项功能已经实现，`userId` 使用对方的 IM 号；每次请求带当前 `chatToken` 和 `operationID`。添加 blocked-viewer 后，对方无法查看本人动态；添加 hidden-author 后，对方动态不出现在本人的动态流。删除同一路径取消对应设置，动态列表在服务端按两份名单过滤。

**`GET /moments/settings` 只返回可见天数、封面和版本，不返回上述名单。** 未返回名单不表示这两项接口未做，也不能用设置接口把已选的人填回来。客户端空的本机选择显示“未选取”，允许选人设置和取消；本机已确认的选择可持久化，但不能当作跨设备完整名单或服务端权限证明。

`POST /moments/sync`，请求体 `momentIDs` 最多 50 个。不可读的项只有 `momentId` 和 `unavailable: true`。

## 错误

参数错误为 `1001` / `ArgsError`。下面这些错误的 `errCode` 为 `20012`，语义位于 `errDlt`：

| errDlt | 含义 |
| --- | --- |
| MOMENT_UNAVAILABLE | 动态不可读，响应不说明是否存在 |
| PERMISSION_REVOKED | 仍是好友，但当前范围或名单不允许 |
| RELATION_UNAVAILABLE | 5 秒内没有确认好友或拉黑 |
| IDEMPOTENCY_CONFLICT | 同一个请求 ID 对应了不同内容 |
| VERSION_CONFLICT | 设置或可见范围版本不符 |
| MEDIA_NOT_READY | 媒体未就绪或不能绑定 |
| MEDIA_EXPIRED | 未绑定媒体已超过 24 小时 |
| CURSOR_EXPIRED | 游标不能用于当前账号或筛选 |
| CONTEXT_CHANGED | 关系或隐私上下文已变化 |

## 联调边界

用户随后补充了部署地址与下面三份成功响应字段形态，标识均为示例。尚未提供上传、创建、结果查询、已读操作、隐私名单及相册的完整响应样例，也没有声明删除动态、修改已发布动态可见范围、举报、视频或媒体状态查询接口。客户端文档中的扩展路径不能据此当作后端已开放能力。当前阶段的发布和封面流程不能依赖未声明的媒体状态查询接口。

## 成功响应形态（用户补充）

未赋值数组返回 `null`，不是 `[]`；数字 0、空字符串和 `false` 均为合法值。`audienceUserIds` 只有查看者是作者时才是数组。`nextCursor` 没有更多时为空字符串。媒体路径拼接在 Chat API 后面，使用同一个 `chatToken` 读取。

### GET /moments/feed?limit=20

```json
{
  "errCode": 0,
  "errMsg": "",
  "errDlt": "",
  "data": {
    "items": [{
      "momentID": "moment-example",
      "author": {
        "userID": "im_example_author",
        "nickname": "示例昵称",
        "avatarURL": "http://8.217.191.236:10002/object/example/avatar",
        "remark": "示例备注"
      },
      "text": "今天的记录",
      "status": "PUBLISHED",
      "visibility": "FRIENDS",
      "publishedAt": 1790985600000,
      "version": 1,
      "viewerContextVersion": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
      "authorSettingsVersion": 0,
      "mediaList": [{
        "mediaID": "media-example", "type": "IMAGE", "width": 1080, "height": 1440,
        "contentPath": "/moments/media/media-example/content",
        "thumbPath": "/moments/media/media-example/content?variant=thumb"
      }],
      "likedByMe": false,
      "likeCount": 1,
      "commentCount": 1,
      "likesPreview": [{
        "userID": "im_example_friend",
        "actor": {"userID": "im_example_friend", "nickname": "示例好友", "avatarURL": "", "remark": ""},
        "createdAt": 1790985660000
      }],
      "commentsPreview": [{
        "commentID": "comment-example",
        "actor": {"userID": "im_example_friend", "nickname": "示例好友", "avatarURL": "", "remark": ""},
        "text": "示例评论", "rootCommentID": "", "replyToCommentID": "",
        "replyTo": null, "replyToDeleted": false, "createdAt": 1790985720000, "canDelete": false
      }],
      "canLike": true, "canComment": true, "canDelete": false, "canEditVisibility": false,
      "audienceUserIds": null
    }],
    "nextCursor": "", "hasMore": false,
    "viewerContextVersion": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  }
}
```

### GET /moments/settings（尚未保存）

```json
{
  "errCode": 0, "errMsg": "", "errDlt": "",
  "data": {
    "visibleRangeDays": 0, "coverMediaID": "", "coverPath": "", "version": 0,
    "viewerContextVersion": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  }
}
```

保存封面后 `coverMediaID` 是媒体 ID，`coverPath` 是 `/moments/media/{coverMediaID}/content`。`version` 从 1 起，之后每次保存加 1。

### GET /moments/notifications

```json
{
  "errCode": 0, "errMsg": "", "errDlt": "",
  "data": {
    "items": [{
      "notificationID": "notification-example", "type": "like", "seq": 1,
      "createdAt": 1790985660000, "unread": true, "unavailable": false,
      "momentID": "moment-example", "commentID": "",
      "actor": {"userID": "im_example_friend", "nickname": "示例好友", "avatarURL": "", "remark": ""}
    }],
    "nextCursor": "", "hasMore": false,
    "viewerContextVersion": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    "unreadCount": 1, "seenWatermark": "example-watermark", "lastSeq": 1
  }
}
```

通知 `type` 还包括 `comment` 和 `reply`。不可读内容的 `unavailable:true`、`actor:null`，且不计入未读。没有通知时 `items:null`，`lastSeq/unreadCount` 为 0。`seenWatermark` 原样带回已读接口。
