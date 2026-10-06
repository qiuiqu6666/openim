# 腾讯云音频转文字代理

本目录是与已实现后端契约一致的本地参考代理，使用 Node.js 20+ 内置模块，无第三方依赖。Flutter 的录音与已有音频均调用同一接口；腾讯云密钥只写在服务器上的 `config/asr.env`，不放进代码仓库或 Flutter。

实际业务后端已提供 Chat API 转发路由、识别代理和本机 Chat 登录校验接口。客户端直接使用当前 Chat API 地址即可；本目录用于协议验证或需要独立部署参考代理的场景，不表示参考代理已经部署。本地测试尚未完成实际登录服务、腾讯云和手机端联调。

## 启动

先在腾讯云控制台开通语音识别服务，创建 API 密钥。代理启动时读取自身目录下的 `config/asr.env`，不依赖当前工作目录。以 `/www/wwwroot/chat/asr-proxy/server.mjs` 为例，默认配置文件是 `/www/wwwroot/chat/asr-proxy/config/asr.env`。可复制 `config/asr.env.example` 创建配置，填入真实值：

```text
TENCENT_ASR_APP_ID=
TENCENT_ASR_SECRET_ID=
TENCENT_ASR_SECRET_KEY=
AUTH_VALIDATE_URL=http://127.0.0.1:10008/internal/validate-session
AUTH_ALLOW_INSECURE_HTTP=true
```

`AUTH_VALIDATE_URL` 必须是上述纯 URL，不要写成 Markdown 的 `[地址](地址)`。配置支持空行、注释和单行引号值，不执行 shell 命令、不展开环境变量；重复配置或语法无效会拒绝启动。真实 `config/asr.env` 已加入 Git 忽略规则，仓库只提供空凭据模板。

```bash
node /www/wwwroot/chat/asr-proxy/server.mjs
```

如果现有部署把配置放在业务根目录 `/www/wwwroot/chat/config/asr.env`，显式指定文件即可，密钥仍只保存在文件中：

```bash
ASR_ENV_FILE=/www/wwwroot/chat/config/asr.env node /www/wwwroot/chat/asr-proxy/server.mjs
```

这里的 `127.0.0.1:10008` 是与代理同机部署的后端 Chat 地址，不是手机地址。配置文件不存在、不可读，或文件里没有 `AUTH_VALIDATE_URL`／腾讯云凭据时，参考代理会拒绝启动；进程环境中的旧密钥不会补齐缺失配置。默认监听 `127.0.0.1:8787`，通过 Chat API 转发或 HTTPS 反向代理对外提供服务。此代理不能自行签发登录 token。

## 可信登录校验合同

本机 Chat 已提供 `POST http://127.0.0.1:10008/internal/validate-session`。代理将客户端 `token` 请求头转发到固定的 `AUTH_VALIDATE_URL`：

```http
POST /internal/validate-session HTTP/1.1
Content-Type: application/json
token: <DataSp.chatToken>
operationID: <服务端生成的 UUID>

{}
```

该接口先走 Chat 现有的 `CheckToken` 中间件，校验 token 的签名和登录态；处理器只读取中间件已经确认的用户 ID，成功时返回 HTTP 2xx：

```json
{"errCode":0,"data":{"userID":"已经鉴权的业务用户 ID"}}
```

只有数值 `errCode: 0` 且非空字符串 `data.userID` 被接受；token 无效时，中间件拒绝请求，不能进入成功处理器。缺失身份、未知结构和校验不可达均拒绝访问；校验服务 HTTP 5xx 返回 `503 AUTH_UNAVAILABLE`。代理不会信任客户端提交的 `userID`。

请求 body 是 `{}`，不包含用户 ID。`operationID` 由代理生成 UUID；客户端登录返回的 `chatToken` 原样放在 `token` 头中。测试只模拟这个可信后端的响应，不访问真实的本机 Chat 服务。

`AUTH_VALIDATE_URL` 默认只允许 HTTPS，禁止重定向和 URL 内嵌账号密码。上述已实现的本机地址使用 HTTP，因此必须同时设置 `AUTH_ALLOW_INSECURE_HTTP=true`。此接口只供本机代理访问，不要改成公网 HTTP。

## Flutter 请求

```http
POST /chat/asr/transcribe?voiceFormat=m4a&duration=12.5 HTTP/1.1
Content-Type: application/octet-stream
token: <DataSp.chatToken>
operationID: <客户端请求 ID，可选>

<原始音频二进制数据>
```

- `voiceFormat` 必填，支持 `wav`、`pcm`、`ogg-opus`、`speex`、`silk`、`mp3`、`m4a`、`aac`、`amr`，必须与真实文件格式一致。不能上传 multipart、Base64 或 HTTP gzip 压缩体。
- `duration` 为可选的实际播放时长，单位秒，支持小数。有值时必须为正数且不超过 7200。压缩音频的真实时长最终由腾讯解码检查，代理也校验返回的 `audio_duration`；客户端传入的时长不能扩大腾讯 2 小时限制。
- 原始音频上限为 100 MiB（100 × 1024 × 1024 字节）；`Content-Length` 和实际流式接收字节数均检查。腾讯文档表述为 100 MB，以腾讯最终校验为准。
- 只接受本地二进制上传，接口没有音频 URL 下载功能，未知参数（包括 `url`、`userID`）会被拒绝。
- PCM 应与引擎采样率匹配，例如默认 `16k_zh` 使用 16 kHz PCM；建议手机录音直接使用带格式信息的 m4a/aac。

成功响应：

```json
{"errCode":0,"data":{"text":"识别出的文字。","requestId":"腾讯云请求 ID"}}
```

失败时 HTTP 状态和 `errCode` 一致，公开错误码只使用以下识别契约：

| HTTP / errCode | errorCode | 含义 |
| --- | --- | --- |
| 400 | `BAD_REQUEST`、`BAD_FORMAT`、`BAD_DURATION`、`EMPTY_AUDIO`、`UNKNOWN_PARAM` | 参数或音频无效 |
| 401 | `AUTH_INVALID_TOKEN` | 登录失效或缺少 token |
| 413 | `PAYLOAD_TOO_LARGE` | 超过大小限制 |
| 415 | `UNSUPPORTED_MEDIA` | 不是未压缩的原始音频二进制 |
| 422 | `NO_SPEECH`、`AUDIO_TOO_LONG` | 没有识别出文字，或音频超过 2 小时 |
| 429 | `RATE_LIMITED` | 请求过于频繁或并发已满 |
| 502 | `UPSTREAM_ERROR` | 识别服务暂时不可用 |
| 503 | `AUTH_UNAVAILABLE` | 登录校验暂时不可用 |
| 504 | `TIMEOUT` | 请求超时 |

例如没有识别出文字时：

```json
{"errCode":422,"errMsg":"未识别到文字，请确认音频中包含清晰语音","errorCode":"NO_SPEECH","data":{"requestId":"腾讯云请求 ID"}}
```

请求 `duration` 超过 7200 秒和腾讯返回的真实音频时长超过 2 小时，都返回 `422 AUDIO_TOO_LONG`。参考代理将内部错误归一化为上述公开错误码与固定安全文案；不会把腾讯原始错误消息、token、签名或密钥返回给客户端。接口路径、方法和 CORS 来源检查仍分别使用 HTTP 404、405、403。

Flutter 默认沿用当前 Chat API 地址，最新后端入口为 `http://8.217.191.236:10008/chat/asr/transcribe`，不需要传入 `ASR_PROXY_URL`。即使登录服务地址包含 `/chat`，识别请求也只使用一次 `/chat/asr/transcribe`。

Chat API 将 POST 原样转发到本机 `http://127.0.0.1:8787/chat/asr/transcribe`，保留查询参数、`token`、`operationID`、`Content-Type` 和原始音频正文，响应原样返回；该转发路由不另做登录校验，由独立代理调用固定的登录校验接口。Chat API 等待响应头的时间为 200 秒，本机代理不可达时返回 JSON `502 UPSTREAM_ERROR`。Flutter 接收超时为 300 秒，覆盖这段等待时间。

反向代理应允许至少 100 MiB（104857600 字节）的请求体，并设置大于 180 秒的上游超时；调整 `REQUEST_TIMEOUT_MS` 时，上游超时也应相应增大。这些本机地址均指后端服务器，不是运行 Flutter 的手机或本开发机器。

如果以后改用独立公共代理，可以通过以下可选配置覆盖识别地址：

```text
--dart-define=ASR_PROXY_URL=https://asr.example.com/chat/asr/transcribe
```

独立代理的 `ASR_PROXY_URL` 必须使用手机可访问的 HTTPS 公共地址，不能配置为后端的 `127.0.0.1:8787`。

## 客户端排查日志

Flutter 转文字服务复用现有控制台日志，筛选 `[ASR]` 查看一次请求的音频来源、下载、上传完成、响应和失败记录。同一次操作的 `operationID` 与发给代理的请求头一致，记录包括阶段、耗时、接口域名和端口、音频格式、字节数、HTTP 状态、白名单错误码，以及格式有效的腾讯 `requestId`。日志不输出登录 token、URL 签名、原始错误内容、音频、本地文件名或识别文字。

出现“语音识别服务暂不可用”时，重点查看 `failure` 中的 `httpStatus`、`errorCode` 和 `bodyType`：`404` 常用于排查入口或反向代理路由，`503 AUTH_UNAVAILABLE` 指向登录校验服务，`502 UPSTREAM_ERROR` 指向识别代理的上游请求。`bodyType: non-json` 和 `contentType: text/html` 可帮助发现网关错误页面；请求超时同时记录 `transport`。这些日志提供定位线索，实际原因仍需结合相同请求 ID 的后端日志确认。

## 配置与运行边界

以下配置均可写入 `config/asr.env`；`ASR_ENV_FILE` 是用于指定配置文件位置的进程环境变量。

| 配置项 | 默认 | 用途 |
| --- | --- | --- |
| `HOST` / `PORT` | `127.0.0.1` / `8787` | 监听地址与端口 |
| `TENCENT_ASR_ENGINE_TYPE` | `16k_zh` | 腾讯识别引擎 |
| `MAX_AUDIO_BYTES` | 104857600 | 可以降低上传上限，不能高于 100 MiB |
| `MAX_CONCURRENT` | 2 | 全部鉴权、上传及识别的总并发上限 |
| `MAX_USER_CONCURRENT` | 1 | 每个已鉴权用户的并发上限 |
| `MAX_USER_REQUESTS_PER_MINUTE` | 10 | 每个已鉴权用户每分钟的请求上限 |
| `MAX_TRACKED_USERS` | 5000 | 内存中限流身份条数的上限 |
| `AUTH_TIMEOUT_MS` | 5000 | 登录校验超时 |
| `UPLOAD_TIMEOUT_MS` | 60000 | 接收音频超时 |
| `UPSTREAM_TIMEOUT_MS` | 120000 | 腾讯识别超时 |
| `REQUEST_TIMEOUT_MS` | 180000 | 单次请求的总超时 |
| `CORS_ALLOWED_ORIGINS` | 空 | 浏览器 Origin 白名单，逗号分隔且不允许 `*` |

音频在进程内短暂缓冲，并发上限用于控制内存；最大文件在拼接时会暂时占用约两份音频空间，请按实例内存降低上传大小或并发。代理不保存音频或识别结果，不推送同步通知；多端使用同一份请求与响应契约。默认只识别首声道，保留标点、智能转换数字。客户端断开或超时会取消上游请求；取消后是否已产生用量以腾讯计费为准。

限流为单进程内存状态，重启会清空。多副本部署应在可信网关增加共享的用户限流和云服务总并发预算。移动客户端不需要 CORS；Flutter Web 跨域使用时必须配置准确的允许 Origin。

## 服务器端鉴权适配

如果直接集成到已有 Node 业务服务，可以注入 `authenticate(token, { signal })`。函数必须执行可信服务器端校验，返回 `{ userID }`，不能从未经验证的 JWT 内容或客户端字段直接提取身份；失败时抛出 `HttpError`。注入后可省略 `AUTH_VALIDATE_URL`，其他腾讯配置仍必填。

```javascript
import { createAsrProxy, HttpError } from './server.mjs';
import { loadAsrEnvFile } from './config-file.mjs';

const server = createAsrProxy({
  env: loadAsrEnvFile(),
  authenticate: async (token, { signal }) => {
    const session = await trustedSessionService.validate(token, { signal });
    if (!session) throw new HttpError(401, 'AUTH_INVALID_TOKEN', '登录已失效，请重新登录');
    return { userID: session.userID };
  },
});
server.listen(8787, '127.0.0.1');
```

这里的 `trustedSessionService` 是实际后端的适配入口，需要替换为本业务的已实现校验。测试通过 `fetchImpl` 注入模拟腾讯与业务校验响应，不请求真实云服务、不使用真实密钥：

```text
node --test
```

协议来源：[用户指定的 API 概览](https://cloud.tencent.com/document/product/1093/134682)、[腾讯云录音文件识别极速版](https://cloud.tencent.com/document/api/1093/52097)、[腾讯官方签名实现](https://github.com/TencentCloud/tencentcloud-speech-sdk-python/blob/master/asr/flash_recognizer.py)。超过 2 小时或格式不支持的文件需另行接入异步录音文件识别，当前代理不会自动切换产品。
