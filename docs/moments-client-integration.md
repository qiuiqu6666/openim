# 朋友圈 Flutter 客户端接入契约

更新日期：2026-10-04。当前接入依据：[用户提供的已实现后端契约](moments-backend-contract.md)。

本文描述客户端对当前后端契约的适配。代码入口是 `lib/services/moments_models.dart`、`moments_api.dart`、`moments_repository.dart`；发布任务位于 `lib/pages/moments/moments_draft_store.dart`。完整产品、权限、数据表、事务及上线设计见 [朋友圈完整设计](moments-full-design.md)。

用户已经提供后端接口说明，随后补充了 Chat API 地址与动态流、默认设置、通知的成功响应字段形态。客户端按这些路径、大小写、空值、能力及错误语义对齐。真实服务尚未使用登录态联调；上传、创建、操作结果、已读、隐私名单及相册的成功响应仍待核对。完整后端样例保存在 [当前后端契约](moments-backend-contract.md)。客户端使用真实业务服务，不提供生产假数据；能力关闭或接口 404/501 时显示未开放状态。

## 1. 地址、身份与响应信封

基础地址取 `Config.appAuthUrl`，去掉末尾 `/` 后追加下表路径。例如基础地址为 `https://business.example/chat`，能力地址就是 `https://business.example/chat/moments/capabilities`。保留基础地址原有路径前缀。

用户确认本项目 Chat API 为 `http://8.217.191.236:10008`，与当前配置默认值一致。远程后端接口目录为 `/www/wwwroot/chat/docs/client/README.md`；这个远程路径不是本地 Flutter README。客户端仍遵守登录所选服务器配置，不能硬编码到别的账号或业务环境。

每次请求携带：

| 请求头 | 规则 |
| --- | --- |
| `token` | 当前登录的 `DataSp.chatToken`，后端验证并映射到稳定 IM userId |
| `operationID` | 每次网络请求新生成 UUID，供追踪；重试仍生成新值 |
| `Content-Type` | 普通请求为 `application/json`；文件上传为 multipart/form-data |
| `Idempotency-Key` | 创建动态、创建评论使用稳定 UUID，必须与 body 的 `clientRequestID` 完全相同 |

不发送 IM token，不发送 `Authorization: Bearer`，也不由客户端提交作者 ID。后端应从业务 token 获取本人身份；所有返回的用户 ID 和受众 ID 必须与 OpenIM SDK 使用的 ID 一致。token 不放进 URL、草稿或发布任务。

JSON 成功响应必须是对象，`errCode` 必须为整数 `0`。读取内容的 `data` 必须是对象，下面另行说明只确认操作时允许的空值：

```json
{"errCode":0,"errMsg":"","data":{"items":[],"nextCursor":null,"hasMore":false}}
```

无需返回内容的删除、点赞和隐私名单 PUT/DELETE 成功可用 `{"errCode":0,"data":{}}`，也可使用 `data:null`。撤销本人互动在失去阅读权后返回资源 ID 和 `removed`，客户端仅确认操作，不要求父动态正文。客户端仍要求 JSON 信封，HTTP 204 空 body 不满足当前适配。数组不能直接作为 `data`。私有媒体内容接口按二进制读取。

错误信封示例：

```json
{"errCode":20012,"errDlt":"MOMENT_UNAVAILABLE","errMsg":"内容已不可用","data":null}
```

参数错误使用 `1001` / `ArgsError`；朋友圈业务错误使用 `20012`，语义从 `errDlt` 读取。客户端不要求另加 `errorCode`。当前模型按 Unix **整数毫秒**解析时间，ID 为非空字符串，资源 `version` 和设置版本为整数；这些成功响应字段需在联调中核实。`viewerContextVersion` 是不透明值，客户端不解析好友名单。

### 1.1 实际响应与内部模型映射

| 后端实际字段 | 内部 Dart 字段/处理 |
| --- | --- |
| `momentID`、`userID`、`mediaID`、`commentID`、`notificationID` | 对应内部 `momentId/userId/mediaId/commentId/notificationId`；兼容旧拼法 |
| `avatarURL` | `avatarUrl` |
| 点赞 `actor` | `MomentLike.user`；用 actor 身份做当前好友校验 |
| 评论 `actor` | `MomentComment.author` |
| `rootCommentID`、`replyToCommentID`、`replyTo`、`replyToDeleted` | 内部根评论、回复 ID、回复用户、目标删除状态 |
| 通知 `type:like/comment/reply` | 归一为内部 `LIKE/COMMENT/REPLY` |
| 通知 `unread:true/false` | `read:false/true`，优先使用真实 unread 字段 |
| 通知列表 `lastSeq` | 内部 `readThroughSeq`，同 `seenWatermark` 原样回传 |
| 设置 `coverMediaID`、`coverPath` | 内部 `coverMediaId/coverUrl`；空字符串表示尚无封面 |
| 设置中的隐私名单字段缺失 | 当前后端正常契约，不作为功能关闭或名单加载失败判断；名单 UI 使用独立本机确认记录 |
| 旧设置中的隐私名单字段 | 仅保留模型解析兼容，不用于回填或替换本机记录 |
| 数组 `null` | 空列表；其他非法类型仍视为错误响应 |
| `0`、`false`、空字符串 | 合法字段值，不用真假值覆盖 |

通知样例只带身份、目标 ID 与类型，没有动态正文、评论正文和回复对象；页面据类型显示互动提示，通过 `momentID` 进入当前授权详情。不可读占位的 `actor:null/unavailable:true` 不显示，不计入客户端可见未读。评论正文和回复目标来自动态/评论接口，不从业务推送编造。

## 2. 能力握手

`GET /moments/capabilities` 返回：

```json
{
  "errCode":0,
  "data":{
    "supportsMoments":true,
    "maxImages":9,
    "maxTextLength":2000,
    "maxCommentLength":500,
    "maxImageBytes":10485760
  }
}
```

`supportsMoments` 只有显式 `true` 才启用。即使旧字段 `enabled:true`，缺失或关闭 `supportsMoments` 也不会启用；不再要求后端提供 `protocolVersion` 或多组开关。图文读取、发布、互动和设置随该能力开放。本阶段客户端固定关闭视频和举报。用户重试会再次握手。取消本人已有点赞、删除本人评论不要求父动态仍可读。

当前发布 UI 为文字和图片，最多 9 张；文本按 Unicode code point 计数，动态硬上限 2000、评论硬上限 500。上传还遵守能力响应给出的图片数量和单张大小限制；未提供时沿用当前客户端默认限制，需与实际后端校验对照。能力响应即使附带视频或举报为 true，本阶段也不显示这两个入口。

## 3. 已实现的 API 适配路径

下表路径相对于业务基础地址。分页 GET 使用 `cursor`（首屏省略）和 `limit`（默认 20，适配器限制为 1～50）。路径中的 ID 会进行 URI 编码。内部方法参数可仍名为 `pageSize`，线上字段统一为 `limit`。

| 方法与路径 | 请求关键字段 | `data` 内容 |
| --- | --- | --- |
| GET `/moments/capabilities` | 无 | 能力对象 |
| GET `/moments/feed` | 分页参数 | 动态分页 |
| GET `/moments/users/{userId}` | 分页参数 | 动态分页，附 `user`、`coverUrl`、`visibleRangeDays` |
| GET `/moments/{momentId}` | 无 | 完整动态，或 `{"post":动态}` |
| POST `/moments` | `clientRequestID,text,mediaIDs,visibility,audienceUserIds` | 当前解析完整动态，或 `{"post":动态}`；待真实响应核对 |
| GET `/moments/publish-results/{clientRequestID}` | 无 | 发布执行结果 |
| GET `/moments/{momentId}/likes` | 分页参数 | 点赞分页 |
| POST `/moments/{momentId}/likes` | 无 | 空对象，设置为已点赞 |
| DELETE `/moments/{momentId}/likes/me` | 无 | 空对象，撤销本人点赞 |
| GET `/moments/{momentId}/comments` | 分页参数 | 评论分页，不能以预览代替全量分页 |
| POST `/moments/{momentId}/comments` | `clientRequestID,text,replyToCommentID`；普通评论为空串 | 完整评论，或 `{"comment":评论}` |
| GET `/moments/comment-results/{clientRequestID}` | 无 | 评论执行结果 |
| DELETE `/moments/{momentId}/comments/{commentId}` | 无 | 空对象 |
| POST `/moments/media/upload` | multipart：`file,clientMediaId` | 媒体对象 |
| GET `/moments/media/{mediaId}/content` | 可选 `variant=thumb` | 二进制图片；每次访问鉴权 |
| POST `/moments/cover/upload` | multipart：`file,clientMediaId` | 媒体对象；完成后 PATCH 设置绑定 |
| GET `/moments/settings` | 无 | 本人可见天数、封面与版本，不含名单 |
| PATCH `/moments/settings` | `expectedVersion`，可选 `visibleRangeDays,coverMediaId` | 修改后的可见天数、封面与版本 |
| PUT/DELETE `/moments/settings/blocked-viewers/{userId}` | 无；路径 ID 是对方 IM 号 | 单项操作确认，不用来替换完整设置或名单 |
| PUT/DELETE `/moments/settings/hidden-authors/{userId}` | 无；路径 ID 是对方 IM 号 | 单项操作确认，不用来替换完整设置或名单 |
| GET `/moments/notifications` | 分页参数 | 通知分页及当前可见未读数、水位 |
| POST `/moments/notifications/read` | `notificationIDs,readThroughSeq,seenWatermark,markThrough` | 当前解析 `{"unreadCount":整数}`，待真实响应确认 |
| POST `/moments/sync` | `momentIDs`，最多 50 个 | 不可读项仅 `momentId,unavailable:true` |

`sync` 当前提供 API 适配；前台恢复、好友变更和业务推送通过重新查询更新。图片处理未完成会保留原任务供重试；封面保留已上传的媒体 ID，再次保存尝试绑定，不依赖未声明的 `mediaStatus` 路由。删除动态、修改已发布动态可见范围属于原设计扩展，当前后端说明未确认这些接口；页面只有响应明确授予 `canDelete/canEditVisibility` 时才显示相应操作。举报当前关闭。正式实时推送链路仍需联调。

## 4. 动态、权限与分页响应

创建请求示例，`Idempotency-Key` 同为 `35397e24-c2e8-48e0-a7f0-801437c5c324`：

```json
{
  "clientRequestID":"35397e24-c2e8-48e0-a7f0-801437c5c324",
  "text":"今天的记录",
  "mediaIDs":["media-1"],
  "visibility":"PARTIAL",
  "audienceUserIds":["friend-1"]
}
```

`SELF`、`FRIENDS` 的受众列表为空；`PARTIAL` 必须有选中好友，`EXCLUDE` 可为空。服务端重新校验当前好友、媒体归属和媒体 READY 状态。创建时只传媒体 ID，不能由客户端指定存储地址或作者。

用户提供的实际动态流响应：

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

相册分页额外返回 `user`（MomentUser）、`coverUrl`（私有代理路径或 null）、`visibleRangeDays`。受众列表仅作者返回，普通查看者不应收到该列表，客户端还会主动清空。`canLike/canComment/canDelete/canEditVisibility` 缺省为 false；必须由后端按当前身份计算，UI 提示不能替代写接口授权。资源实际修改时单调增加 `version`；不要用请求次数作为版本。

所有读入口、创建响应和幂等重放均使用相同当前 ACL。点赞者、评论者和回复目标只能是当前查看者本人或当前合法好友，作者没有额外例外；同时要求动态、根评论和实际回复目标的权限成立。后端先过滤再计算 `likeCount/commentCount`，预览和分页必须来自同一查看者投影，不返回非好友身份或未经筛选的总数。存在正数时需附至少一项对应可见预览；预览并非完整名单，详情另读分页。

客户端从 OpenIM SDK 分页读取好友、订阅既有关系事件，再做防御过滤。关系未知时第三方互动不显示；评论、点赞名单和通知查询明确报可重试关系错误。发现被过滤条目或计数与预览不一致时，不拿预览条数推算总数，改为隐藏相关数字。

`hasMore:true` 必须附非空且推进的 `nextCursor`。游标是不透明字符串，客户端只透传；服务端绑定账号、范围、过滤参数、精确数据库排序时间和 ID，不从展示用毫秒重新推导边界。ACL 在数据库查询/扫描阶段应用，不能用固定扫描几轮后仍有候选就宣告到底。好友或隐私变更后旧游标应失效或重新建立合法查询；分页错误不得泄漏内容。

## 5. 评论与已删除目标

评论创建示例：

```json
{"clientRequestID":"e9c3d3ef-1099-4a0f-b542-4aab28d50491","text":"收到","replyToCommentID":"comment-root"}
```

普通评论请求的 `replyToCommentID` 发送空串。内部模型仍名为 `replyToCommentId`，响应解析兼容这两种大小写。回复目标用户由后端从原评论推导，不接收客户端指定的目标用户。以下评论响应结构及已删除目标示例仍需核对后端实际返回：

```json
{
  "errCode":0,
  "data":{
    "commentId":"comment-reply",
    "author":{"userId":"friend-1","nickname":"好友","avatarUrl":"","remark":""},
    "text":"收到",
    "createdAt":1790985602000,
    "canDelete":false,
    "replyToCommentId":"comment-root",
    "rootCommentId":"comment-root",
    "replyTargetDeleted":true,
    "replyToUser":{"userId":"friend-2","nickname":"","avatarUrl":"","remark":""}
  }
}
```

此例只有在 `friend-1`、`friend-2` 对当前查看者都仍合法可见时才允许返回。删除目标的 userId 是已经获授权的最小身份凭据，用于客户端好友校验，不是公开身份残片；不附目标正文、原姓名、头像或备注。客户端模型会丢弃删除目标的身份展示字段，UI 用 `MomentComment.replyTargetLabel` 显示“已删除评论”，不显示 ID 回退。`replyTargetDeleted:true` 本身不授予权限：目标缺失、变为非好友、被拉黑或关系未知时，整条回复和对应通知隐藏。后端也不应返回被撤权目标 ID。

已确认的本人评论会写入已加载详情评论状态；未知结果保留稳定请求 ID，先调用评论结果查询。结果查询确认成功但目前不可见时只返回操作事实和 commentId，不能重放旧正文或旧回复身份。

## 6. 发布、上传与未知结果

媒体上传为 multipart，表单只发送 `file` 和固定 `clientMediaId`，不发送 `type`。当前模型解析 `mediaId`、可选 `type/status`、宽高、大小和代理路径；未给类型/状态按图文阶段 IMAGE/READY 处理，服务端最终以绑定校验为准。显式 `PROCESSING` 不直接作为可发布图片；重试保留原键。封面可以保留媒体 ID 再尝试 PATCH 绑定，`MEDIA_NOT_READY` 保留输入和上传结果，不查询未声明的媒体状态路由。未绑定媒体超过 24 小时会返回 `MEDIA_EXPIRED`，原媒体不能继续绑定。

后端以 `(当前账号,操作类型,clientRequestID)` 唯一约束创建动态和评论，并保存内容摘要。相同键、相同内容返回同一个执行事实；同键不同内容返回冲突。稳定键在提交前写入本地任务，网络超时、5xx 或成功响应不可解析时结果未知，不能另换 UUID 重发。`operationID` 与这个稳定键用途不同。

发布结果查询成功响应：

```json
{"errCode":0,"data":{"status":"SUCCEEDED","momentId":"moment-1"}}
```

实际后端查询状态为 `NOT_FOUND`、`PROCESSING`、`SUCCEEDED`。客户端还保留旧设计状态兼容，但不要求后端增加。执行成功与内容当前可读是两件事。`NOT_FOUND` 应以成功信封返回；HTTP 404 不表示幂等记录不存在。

成功结果可按当前权限附完整 `post` 或 `comment`，不可读时只附 `resourceId` 与执行状态。发布任务会用资源 ID 再读取，确认提交但无权取得内容时仍清理已成功任务；不能为了恢复结果重放旧响应。`REJECTED` 是明确拒绝，`UNKNOWN/PROCESSING` 保留任务，`NOT_FOUND` 重试原键原载荷，防止原请求迟到重复创建。客户端取消上传不等于撤销已发送的发布事务；结果未知仍需确认。

## 7. 私有图片、封面与撤权

内容和缩略图路径推荐 `/moments/media/{id}/content` 与 `?variant=thumb`。封面也返回位于 `/moments/` 下的代理路径，可以用 `/moments/media/{coverMediaId}/content`。完整 URL 必须与 `Config.appAuthUrl` 同源，并位于该基础地址路径前缀下的 `/moments/` 内；例如 `/chat/moments/...`。相对路径 `/moments/...` 会追加到基础地址，而非忽略 `/chat`。

客户端拒绝跨域私有 URL、协议相对 URL、token 查询参数、含凭据或路径穿越的 URL；禁用重定向，不把 token 转发至对象存储/CDN。服务端代理内部读取私有桶，HTTP 响应应直接输出图片 bytes，设置合适 Content-Type 与 `Cache-Control: private, no-store`。不能用 JSON 信封包图片，也不能跳转到永久公开 URL。

服务端每次读取原图、缩略图和封面重新确认当前会话、动态/相册权限以及未发布媒体归属。首期私有代理避免签名链接在撤权后继续有效的额外窗口；已经显示或传到设备的像素无法远程回收，正在传输的响应也需约定撤权检查边界。客户端账号、token、服务器或权限上下文改变后丢弃旧异步 bytes，清空画面和内存图片缓存，不使用共享磁盘 NetworkImage 缓存。

当前下载适配按整文件 bytes 读取图片；视频 Range 与播放器鉴权仍属后续阶段，不能因预留 VIDEO 类型就开启视频。媒体撤权错误使用 HTTP 401/403/410；404/501 会关闭当前朋友圈内容缓存并显示不可用。

## 8. 设置、通知与已读水位

用户提供的默认设置响应：

```json
{
  "errCode": 0, "errMsg": "", "errDlt": "",
  "data": {
    "visibleRangeDays": 0, "coverMediaID": "", "coverPath": "", "version": 0,
    "viewerContextVersion": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  }
}
```

保存封面后 `coverPath` 是私有代理地址。用户已确认此接口不返回两份隐私名单，缺字段属于正常响应；名单页不再依据这些字段禁用“添加朋友”。

历史范围允许 `0/3/90/180/365`，0 为全部。PATCH 示例 `{"expectedVersion":4,"visibleRangeDays":3}`；清除封面用 `{"expectedVersion":4,"coverMediaId":null}`，省略字段表示不修改。版本冲突返回 `VERSION_CONFLICT`，后续重新读取并保留用户选择。

两类隐私设置已开放，通过独立 PUT/DELETE 逐人提交，ID 是对方 OpenIM userId。成功响应只确认操作，不能把空确认对象当成完整设置，覆盖已有可见天数、封面或版本。仓库在成功后更新本机已确认记录，立即使旧动态查询失效，再从服务器读取过滤后的动态；读取 GET 设置不会覆盖本机记录。失败或未知结果不改变已确认成员，用户可以显式重试同一人、同一方向的命令。

本机记录按业务服务器和当前账号隔离，重新进入页面及重启应用后恢复。空记录显示“未选取”，添加可正常使用。因为后端没有名单读取接口，本机记录不能表示其他设备的全部设置；页面允许重新选择好友幂等添加，也允许选任意好友发送 DELETE，取消本机未记录的既有设置。后端已成功但本机存储失败时保留内存成员，单独提示并重试本机保存，不重复发送已成功请求。模块维护入口见 [隐私名单说明](../lib/pages/moments/privacy/README.md)。

详细资料页也提供对应好友的两项朋友圈权限开关，与名单页共用当前仓库及本机确认记录；开关不调用 GET settings 获取名单。当前联系人或登录态变更后取消旧页面的重试意图，不把旧请求重新发送给新账号。界面与验证记录见 [资料页对齐说明](user-profile-99chat-validation.md)。

用户提供的实际通知响应：

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

通知操作者、评论、回复目标和动态均按当前 ACL 过滤，未读数也只统计当前可见未读。客户端发现非好友、不可用或未知目标时防御隐藏条目，并抑制未经确认的未读 badge，不能把已加载条数当成总数。已删除目标引用遵守第 5 节匿名契约。

单项已读请求为 `{"notificationIDs":["notification-100"],"markThrough":false}`；“全部已读”请求为 `{"notificationIDs":[],"readThroughSeq":100,"seenWatermark":"opaque-watermark-100","markThrough":true}`。watermark 属于该账号和首屏观察到的上界，后端校验归属/完整性，只标记到 100，执行期间到达的 101 保持未读。旧分页不能覆盖首屏水位。当前解析要求响应带真实 `unreadCount`；若实际后端仅回确认标志，需改为重拉通知取得未读数，不能用本地已加载条数推算。

## 9. 错误处理和权限边界

| 返回 | 当前客户端处理 |
| --- | --- |
| HTTP 404/501 | Unavailable，清除旧私有内容；不伪造空列表或写成功 |
| HTTP 401 | 登录失效，清除旧私有内容 |
| HTTP 403/410 | 权限撤销/内容不可用，清除旧私有内容 |
| `20012 / MOMENT_UNAVAILABLE`、`PERMISSION_REVOKED` | 权限错误，清除旧私有内容，不暴露资源存在性 |
| `20012 / RELATION_UNAVAILABLE` | 关系暂未确认，清除旧私有投影，保留可重试能力 |
| `20012 / CONTEXT_CHANGED` | 丢弃旧上下文内容与游标，重新从首屏查询 |
| `20012 / CURSOR_EXPIRED` | 旧游标失效，清空当前分页，下一次从首屏开始 |
| `1001 / ArgsError` | 参数明确失败，保留用户输入 |
| `20012 / IDEMPOTENCY_CONFLICT` | 原请求 ID 的载荷冲突，不盲目重发 |
| `20012 / MEDIA_NOT_READY`、`MEDIA_EXPIRED` | 媒体未就绪或已过期，保留任务并提示处理 |
| AUTH_REQUIRED/UNAUTHORIZED | 身份错误，清除旧私有内容 |
| 写请求超时、网络断开、HTTP 5xx、错误成功信封 | 结果未知，发布/评论保留原幂等键并查询 |
| `VERSION_CONFLICT`、校验和配额错误 | 明确失败，保留用户输入，刷新后重试 |
| 客户端 `SESSION_CHANGED/CONTEXT_CHANGED` | 丢弃旧会话/权限响应，不恢复旧缓存 |

普通资源不可用使用 `MOMENT_UNAVAILABLE` 或 HTTP 403/410，避免与未部署路由的 404 混淆。幂等查询确定不存在使用成功信封 `NOT_FOUND`。即使 HTTP 非 2xx，只要包含明确的 `1001` 或 `20012` 已知业务错误信封，客户端仍解析其 `errDlt`；没有明确业务拒绝的 5xx 写请求保留结果未知状态。

后端需统一授权：Feed、相册、详情、评论/点赞分页、创建和修改响应、通知及摘要、未读数、幂等重放/结果查询、媒体和封面全部检查当前权限。本人取消点赞/删除评论可在父动态不可读时清理，但不能返回父动态或非好友正文。跨服务关系不可确认或投影不新鲜时回查 authority，失败关闭相关访问；客户端好友缓存只能提供额外防御，不能成为服务端权威。

## 10. 验证与上线

在项目目录运行针对新增模块的检查：

```powershell
$momentsRootTests = @(Get-ChildItem -LiteralPath test -Filter 'moments*_test.dart' | Select-Object -ExpandProperty FullName)
$momentsModuleTests = @(Get-ChildItem -LiteralPath test/pages/moments -Recurse -Filter '*_test.dart' | Select-Object -ExpandProperty FullName)
$momentsTests = $momentsRootTests + $momentsModuleTests
flutter analyze --no-pub lib/services/moments_models.dart lib/services/moments_api.dart lib/services/moments_repository.dart lib/pages/moments @momentsTests
flutter test --no-pub @momentsTests
flutter build apk --debug --no-pub
```

纯接口测试不依赖应用页面，工程其他模块正在改动时仍可独立验证当前契约：

```powershell
flutter test --no-pub test/moments_api_contract_test.dart
```

使用实际登录态联调时，在可信环境设置 `MOMENTS_APP_AUTH_URL` 与 `MOMENTS_CHAT_TOKEN`，使用本人业务 token 做只读握手检查。不要把 token 写进文档或终端输出：

```powershell
$momentsBase = $env:MOMENTS_APP_AUTH_URL.TrimEnd('/')
$momentsHeaders = @{ token = $env:MOMENTS_CHAT_TOKEN; operationID = [guid]::NewGuid().ToString() }
$momentsCapabilities = Invoke-RestMethod -Method Get -Uri "$momentsBase/moments/capabilities" -Headers $momentsHeaders
if ($momentsCapabilities.errCode -ne 0 -or $momentsCapabilities.data.supportsMoments -ne $true) { throw '朋友圈能力握手未通过' }
$momentsCapabilities.data | ConvertTo-Json
```

**2026-10-04 最终验证：17 个朋友圈测试文件共 207 项全部通过；定向静态检查的 21 个目标无问题；Android Debug APK 整包构建成功。** 本次实际产物为 [app-debug.apk](../build/app/outputs/flutter-apk/app-debug.apk)，不是前一轮的旧包。日志分别为 [统一回归](../build/moments-privacy-all-tests.log)、[静态检查](../build/moments-privacy-fix-analyze.log)、[APK 构建](../build/moments-privacy-apk-build.log)。之前共享模块缺失引起的测试编译阻塞，在此次验证时已解除。

新增隐私子模块的 **54 项测试**分别为 API 6 项、仓库 11 项、页面 13 项、存储与控制器 24 项。覆盖四条真实 PUT/DELETE 路径及鉴权、无名单字段的正常空态、添加与取消未缓存好友、设置刷新不擦记录、幂等重选、批量部分失败仅续剩余项、未知结果重试、账号及服务器隔离、应用重建后的恢复、迟到读写、并发保存及本机保存失败只补存。另验证后端确认后立即使旧动态和图片失效，不等待本机存储完成。页面用例覆盖中文、亮暗主题和大字号。

既有用例继续验证真实字段及 `items:null`、通知 `unread/lastSeq`、默认设置版本 0、能力握手、发布与评论请求、上传表单、错误语义、本人互动清理、发布任务恢复、非好友互动过滤、通知水位、图片与解码缓存清理。后端样例位于 `test/fixtures/moments_backend_responses.json`；测试假 API 和注入存储只用于 test，生产页面仍读取真实服务。复用现有设置页面、分组、单元格、头像、好友选择及状态提示组件，保持当前界面风格，不新增另一套设置组件。

这些结果验证客户端实现与构建，尚未使用实际登录态完成线上联调，也未完成 Android/iOS 真机及多设备验收。缺失名单字段属于已确认的后端契约，不再列作待实现能力或页面阻塞。

随后详细资料页接入两项权限控件，新控件 15 项测试通过，朋友圈全部用例合计 222 项继续通过；与资料页及导航的联合回归共 258 项通过。本次重新生成的 Android 调试包及扩展设置测试的独立失败说明见 [资料页验证](user-profile-99chat-validation.md)。

随后朋友圈展示层按 99chat 源码对齐，保留既有点赞与评论按钮、真实服务及权限逻辑。动态流、相册、详情及次级页面的设计参数、亮暗主题预览与本轮验证见 [朋友圈对齐记录](moments-99chat-validation.md)；组件归属见 [模块 README](../lib/pages/moments/README.md)。

目标后端接入后必须另跑完整设计的 ACL/PUB/SYNC 验收矩阵，至少四个关系不同账号交叉验证：作者无非好友例外、已删除目标、撤权中异步响应、分页精度、重复提交、上传回收竞态、通知 100/101 水位、媒体同源与重定向拒绝。再做 Android/iOS 真机图片选择、后台恢复、亮暗主题和大字体验收。

上线先部署版本化数据迁移、鉴权/好友 authority、统一 ACL、幂等与私有媒体代理，关闭能力进行多账号联调；通过验收后开启 `supportsMoments`。当前已声明的业务推送链路仍需多端验收，视频与举报按后续阶段补齐。不得以单元测试通过替代真实服务端、多设备和平台验收。

### 10.1 已交付前端入口与页面

| 路径 | 实际行为 |
| --- | --- |
| 我的 → 社区广场 | 进入好友朋友圈动态流 |
| 本人资料 → 朋友圈、动态流本人头像 | 进入我的朋友圈 |
| 好友资料 → 朋友圈、动态作者头像 | 进入指定用户朋友圈，读取当前授权的历史范围 |
| 顶部相机按钮 | 进入图文发布页，恢复本人、当前业务环境的草稿和发布任务 |
| 点击动态正文或更多 → 查看详情 | 进入详情，点赞和评论状态与动态流同步 |
| 查看点赞 | 当前查看者可见点赞的游标分页 |
| 评论按钮或底部写评论 | 评论、回复；结果未知时冻结内容并查询原请求结果 |
| 互动消息 | 可见通知、单条已读、带观察水位的全部已读 |
| 朋友圈设置、我的 → 设置 → 朋友圈 | 历史范围及两类已开放设置；名单显示本机确认记录，空时显示未选取且允许添加/取消 |
| 自己的封面 → 更换封面 | 选图、上传与绑定、保存结果确认、版本冲突恢复 |
| 动态或评论菜单 | 后端授权的删除；本人动态修改范围属待确认扩展；当前无举报入口 |

默认封面是合法来源的装饰图，不是伪造动态。服务未开放时保留页面入口并显示明确提示；成功读取的真实空列表显示空态。发布草稿和请求任务支持跨进程恢复；评论的未知结果确认保留在当前编辑器内，重新打开编辑器不会自动重放之前的评论。视频和举报属于后续阶段。

## 11. 当前多端业务通知

OpenIM 自定义业务通知的外层 `key` 为 `moments`，`data` 可为对象或 JSON 字符串，内容只使用 `eventId,momentId,action,aggregateVersion,occurredAt`。客户端按事件 ID 去重，将其作为失效提示，再查询已加载的动态流、个人相册、详情及互动消息；不从通知补出正文、互动身份或受众名单。`aggregateVersion` 不直接当作动态模型版本，也不用于恢复未授权缓存。

好友、拉黑、账号、token 或服务器变化会立即清除旧私有投影、图片及游标，迟到响应必须通过会话与权限世代检查才能写入。推送、后台恢复和关系变更可以合并刷新，但最终内容始终来自当前授权的读接口。
