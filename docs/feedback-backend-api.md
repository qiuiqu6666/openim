# 意见反馈后端对接（待实现协议）

本文是新增接口的实现约定，不代表线上已提供这些接口。Chat 接口地址、请求头沿用 client/README.md：token 使用 chatToken，operationID 每次唯一。用户 ID 从登录态取得，忽略客户端 userID。Android/iOS 共用协议。

## 功能与限制

反馈类型 suggestion（建议）、bug（错误）、other（其他）。正文去除首尾空白后必填，最多 2000 个 Unicode 字符。截图可选，最多 5 张，每张最多 10 MiB，支持 JPEG、PNG、WebP；服务端检查真实文件类型和大小，不能只信任扩展名。当前前端从相册读取压缩图片，不上传聊天记录。

排查记录直接复用 OpenIM SDK uploadLogs，不新增客户端日志采集或 Chat 日志文件上传接口。截图和 SDK 日志分别存储，后台通过反馈 ID 关联。

## 1. 创建反馈

POST /feedback/create

Content-Type: multipart/form-data（边界由网络库生成）。字段 payload 是以下 JSON 字符串；screenshots 是可重复的二进制文件字段，最多 5 个。

```json
{
  "clientRequestID": "一次反馈的UUID，重试保持不变",
  "type": "bug",
  "content": "修改支付密码时，滑块验证完成但短信未发送",
  "includeSDKLogs": true,
  "deviceID": "本机持久化UUID",
  "platform": "Android",
  "deviceName": "Samsung SM-N9810",
  "appVersion": "3.8.3+235"
}
```

设备信息仅用于展示，不作为身份或权限依据。字段长度应限制：deviceID 128、deviceName 200、appVersion 64。platform 允许 Android/iOS/Web/Windows/macOS/Linux/unknown。

成功：

```json
{
  "errCode": 0,
  "errMsg": "",
  "errDlt": "",
  "data": {
    "feedbackID": "fb_唯一ID",
    "createdAt": 1790956800000,
    "status": "received",
    "sdkLogStatus": "pending"
  }
}
```

includeSDKLogs=false 时 sdkLogStatus=not_requested；true 时 pending。createdAt 是服务端毫秒时间戳。创建成功即可认为反馈已保存。

幂等键为（登录 userID，clientRequestID），必须有唯一约束。相同请求重试返回原 feedbackID，不重复创建或保存附件；同一键而内容、附件摘要不同返回冲突。附件上传失败不能返回成功，清理本次孤立文件。上传失败后的反馈重试复用原 clientRequestID，编辑内容后生成新值。

## 2. SDK 日志上传与关联

创建反馈成功且用户勾选日志时，客户端调用已有 SDK：

```dart
await OpenIM.iMManager.uploadLogs(
  line: 10000,
  ex: jsonEncode({
    'biz': 'feedback',
    'feedbackID': feedbackID,
    'clientRequestID': clientRequestID,
  }),
);
```

line=10000 是本协议建议值：上传最近日志，避免默认 line=0 的全量行为。上线时须验证部署 SDK 版本的日志范围和日志保留行为。operationID 可额外传新的 UUID，不能作为反馈关联的唯一依据。没有勾选时绝不调用 uploadLogs。

复用已有 SDK 上传进度回调，不替换全局 listener；统一进度分发，避免覆盖“关于我们”页的上传监听。日志上传阶段可以显示进度，但创建成功的反馈不因日志失败而丢失或再次创建。

### 后端必需的关联工作

OpenIM 日志接收端成功持久化日志记录后，读取 ex JSON：biz=feedback 时，以实际 IM 登录用户、feedbackID 校验归属，关联真实日志记录 ID 和存储地址。不能信任客户端 ex 中的身份字段，不能凭反馈 ID 给其他用户关联日志。

Chat 与 OpenIM 不同服务时，由服务端通过内部事件/任务或日志记录查询完成关联；需要可靠重试和去重。必须确认当前部署的 OpenIM 日志记录保留 Ex，且可按真实用户及 Ex 查到记录。若当前版本没有这种能力，需要扩展服务端关联链路；仅新增 Chat 反馈表不能完成日志关联。

关联后 sdkLogStatus=uploaded；记录 sdkLogRecordID、上传时间和内部对象键。下载 URL 按管理员权限生成短期授权链接，不向普通客户端开放。客户端上传成功回调不作为关联已完成的唯一证据。

SDK 的 Flutter uploadLogs 返回值未明确保证日志 URL，客户端不提交虚构的 logURL，也不另行上传 zip。

日志可能含设备和运行信息。现有页面“不包含聊天正文、密码或请求内容”的承诺必须在审计实际 SDK 日志之后才能保留；上线前改为“附带 SDK 运行日志，帮助排查问题”，并落实权限、保留期与敏感信息处理。

## 3. 查询反馈结果与日志关联状态

POST /feedback/detail

```json
{ "feedbackID": "fb_唯一ID" }
```

只允许查询本人反馈。不存在或不属于当前用户统一返回 not_found。

```json
{
  "errCode": 0,
  "data": {
    "feedbackID": "fb_唯一ID",
    "status": "received",
    "sdkLogStatus": "uploaded",
    "createdAt": 1790956800000,
    "updatedAt": 1790956820000
  }
}
```

反馈状态：received/processing/resolved。日志状态：not_requested/pending/uploaded/failed。pending 表示等待上传或服务端关联，不立即判失败。后台超时策略可将长时间 pending 标为 failed，SDK 上传重试成功仍可转 uploaded。

SDK 上传抛错时，客户端提示“反馈已提交，日志上传失败，可重试”，重试只调用 uploadLogs，沿用同一 feedbackID。服务端关联幂等；允许同一反馈多个上传尝试，后台查看最新成功记录并保留历史。

## 4. 管理后台

新增反馈列表和详情：按时间、用户、类型、处理状态筛选并分页。详情显示正文、截图、设备、版本、SDK 日志状态以及关联日志下载入口；管理员可以变更处理状态、记录内部处理备注。管理权限沿用后台认证，禁止使用普通 chatToken 下载日志或处理他人反馈。所有处理和日志下载记录审计。

## 5. 存储与错误约定

建议集合/表：feedback（正文、userID、clientRequestID、状态、日志开关、设备字段、服务端时间）；feedback_attachment（feedbackID、对象键、真实类型、大小、排序）；feedback_log_link（feedbackID、实际日志用户、OpenIM 日志记录 ID、对象键、上传时间）。使用现有数据库与对象存储，不在新增链路保存 Chat/IM token。

业务错误沿用 HTTP 200 + errCode/errMsg/errDlt。参数错误沿用 1001/ArgsError，登录失效沿用现有错误。新增错误建议标识 FeedbackNotFound、FeedbackRequestConflict、FeedbackAttachmentInvalid、FeedbackRateLimited、FeedbackStorageUnavailable；数值由后端统一分配，避免与已有 200xx 冲突。限流响应可返回 retryAfter 秒，不能因此标记提交成功。

## 6. 验收

- 无截图、1/5 张截图、超过数量和大小、伪造类型、空白正文、2000 字及超长正文。
- 未勾选日志时不调用 SDK；Android/iOS 真实日志上传与服务端 Ex 关联。
- SDK 日志不存在、上传失败、关联延迟、重复上传：反馈保存不丢失，不重复创建。
- 创建请求超时重试只生成一条反馈；相同幂等键不同内容拒绝。
- 跨用户查询、日志关联和下载均被拒绝；后台列表、处理状态、审计可用。

## 核对依据

本地 Flutter SDK 3.8.3+hotfix.12：im_manager.dart 的 uploadLogs 支持 ex/line/operationID；现有“关于我们”页已调用 uploadLogs，IMController 已注册上传进度监听。

OpenIM core 主分支参考（不能代替部署版本验证）：https://github.com/openimsdk/openim-sdk-core/blob/main/internal/third/log.go 。该实现上传日志 zip 后提交包含 FileURLs 和 Ex 的日志记录；line=0 与指定行数的行为不同。
