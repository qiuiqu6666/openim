# 图片、视频上传主备与后端转存

2026-10-23 已上线广州、香港跨桶容灾。客户端版本 `recovery.49-upload-disaster.1`，Android 四 ABI SDK 已重建并验证，iOS Framework 需要 macOS 重建。现有手机安装包需升级后才使用新策略。

## 上传顺序

| 网络所在地 | 广州直传 | 香港直传 | 后端代传 |
| --- | --- | --- | --- |
| 中国大陆 | 直连 → 加速 | 直连 → 加速 | 广州 → 香港 |
| 其他地区、未知 | 加速 → 直连 | 加速 → 直连 | 广州 → 香港 |

广州源站为 `gz99chat-1416337673.cos.ap-guangzhou.myqcloud.com`，加速域名为 `gz99chat-1416337673.cos.accelerate.myqcloud.com`。香港源站为 `99chat-1416337673.cos.ap-hongkong.myqcloud.com`，加速域名为 `99chat-1416337673.cos.accelerate.myqcloud.com`。各线路使用独立签名，后端代传使用当前 IM API 的 `POST /object/upload_relay`，校验登录状态后流式写入目标桶。

服务端用本地 ip2region 数据库判断网络 IP；仅信任回环地址上的现有 nginx 传入的 X-Real-IP，该接入层从 PROXY protocol 获取并覆盖真实地址。公网直连请求不能用自填头覆盖来源。港澳台、未知地址和数据库不可用时优先加速。VPN/代理以出口 IP 为准。同一次上传固定排序，刷新签名不会重置切换状态。

全程自动，不提供手动选线路入口。两个独立地域的桶互为上传兜底；没有后台磁盘排队落盘，也没有复制历史文件。所有路线都失败或总期限到达时返回失败，不假报发送成功。

服务端分片初始化、合并、HEAD 校验、复制和删除走文件所属桶的源站。香港新文件返回香港源站读取地址，按文件名读取也路由到香港；历史文件地址不改写。

## 协议与边界

- 现有签名响应中的 `X-Openim-Upload-Fallback` 携带对应分片的源站 URL 和签名头，避免直接换域名导致 Host 签名失效。旧客户端原有签名仍可使用。
- SDK 在直传时移除该元数据头；只有转存请求才携带它及 IM 登录令牌。IM 令牌不转发给 COS。
- DNS、连接错误和可重试 HTTP 错误触发切换；权限失败、主动取消和总期限到期不会继续切换。连接和 TLS 分别最多 3 秒；约 8 秒没有请求体读取进展或等待响应头超过 8 秒即切换；签名请求最多 5 秒。网络正在持续传输的视频不会因单次固定两分钟而切断，但仍遵守九分钟总期限。
- 识别为图片且不大于 10 MiB 的单个文件，上传流程总期限 30 秒；其他文件最多九分钟。此期限不包含 UI 压缩准备和消息送达时间，多个资源分别计时。总期限优先于尝试所有线路。
- 失败路线按当前上传服务实例暂避 30 秒，期满重新尝试；不持久化，也不永久禁用。切换无额外的 1/2/4/8 秒等待。
- 同桶重新打开文件并恢复已确认分片；跨桶丢弃旧桶分片状态，创建独立会话重新上传。香港逻辑名使用用户目录下 `__cos_hk__/`，上传 ID 使用 `hk:`，服务端保存独立 Engine 元数据并校验名字与上传 ID 的桶一致。
- 只在 COS 成功或转存明确返回 204 后记为完成，文件合并和完成接口成功后才返回最终 URL。HTTP 200 的鉴权错误 JSON 不会误记成功。
- 转存只接受固定广州或香港源站桶的已签名 PUT 目标，禁止重定向；每片最多 64 MiB，每进程最多 16 个并发转存。视频总大小不受 64 MiB 限制，但每片必须在上限内。

## 源码组织

- `objectstorage/` 复制到后端 `pkg/common/storage/objectstorage/`。
- `uploadrelay/` 复制到后端 `internal/api/uploadrelay/`。
- `integration.patch` 是 `cos.go` 和 `router.go` 的接线差异。
- `uploadregion/` 复制到后端 `internal/api/uploadregion/`；`region-integration.patch` 为 API 初始及续传签名响应接线和固定依赖差异。
- `deploy-region.py` 是地域排序发布记录，含基线校验、测试门禁、备份、上线验证及自动回滚，不可用于其他基线。
- `disaster/storage_route*.go` 复制到 `internal/rpc/third/`，`disaster/integration.patch` 为跨桶 RPC 接线；`disaster/deploy.py` 是本次最终部署记录，使用固定基线，不是通用部署工具。
- `deploy.py` 是本次带基线哈希校验、测试门禁、备份和回滚的发布记录，不可直接用于其他基线。
- 客户端规范源码：`sdk-source/openim-sdk-core-recovery/internal/third/file/`；移动端构建源码：`native_sdk/patch15/core-source/internal/third/file/`。共享源码保留原有上传锁、期限和取消保护。

## 初版验证记录（2026-10-22，保留历史）

- 后端存储、转存接口、API、第三方 RPC 和存储控制器相关测试通过，两项服务构建通过。
- 真实加速直传、源站直传、转存写入均逐字节一致；测试临时对象已清理。
- 上线后通过真实 API 管理员鉴权、签名接口及转存接口完成一次临时文件上传和内容读取核验；未发送聊天消息，未创建已完成的业务对象。
- SDK 与移动端共享源码通过故障切换、已完成分片不重复上传、错误鉴权响应、取消与超时相关测试及 race 检查；移动端另用规定的 Go 1.24.0 通过同组检查。
- 15 项原生源码锁工具测试通过。未构建 AAR、iOS Framework 或 App，未做手机端验收。
- SDK 包的无筛选全量测试包含一个原有硬编码 Windows 文件路径的 `TestUpload`，在 Linux 环境失败；上述定向测试不包含该手工测试。

服务器构建与日志：`/home/ubuntu/media-upload-fallback-20261022`。
回滚脚本：`/srv/99chat-production/backups/upload-fallback-20261022-234723/rollback.sh`。

后续在对应平台执行 `native_sdk/patch15/build-android.ps1` 或 `build-ios.sh` 重建 SDK，再构建 App。仅更新后端不能让旧版客户端自动改走备用线路。

## 地域排序发布记录（2026-10-23）

IPv4 复用 `/srv/99chat-production/app/config/chat/ip2region_v4.xdb`；IPv6 补充同目录 `ip2region_v6.xdb`。可通过 `OPENIM_UPLOAD_GEOIP_V4/V6` 指定其他路径，更新后需重启 API。IPv6 数据来自 ip2region 固定提交 `c1a1fc7d5941` 的 `data/ip2region_v6.xdb`，SHA256 为 `939f6b46bd2b8bec3cf7c5ceb8ba782266ae9b1f35b5ba7916700dec0b7506ed`，许可证保留于 `uploadregion/ip2region-LICENSE.md`。

地域分类、代理信任边界和签名保持测试通过；SDK 与移动端共享源码的线路顺序、分片续传及取消期限 race 检查通过。真实 API 的初始签名、国内外 IPv4/IPv6 续传签名、台湾及未知地址策略和鉴权代传通过，临时对象删除、多片会话中止完成。第一次上线检查误将小文件一次性上传用于续传接口，门禁自动回滚；改用真实多片会话后重新发布通过。

构建和日志：`/home/ubuntu/media-upload-region-20261023`。回滚：`/srv/99chat-production/backups/upload-region-20261023-001838/rollback.sh`。只更新 API，原有第三方服务维持运行。未做新版手机真机测试。

## 跨桶容灾发布记录（2026-10-23）

- 服务端 API、第三方 RPC 已更新。香港桶复用现有 legacy COS 配置与独立 Engine，不把凭据写入客户端；所有配置保持不变。
- 香港直连、加速及代传均已真实写入并读取校验；上线后广州与香港鉴权代传通过。香港完整上传完成接口、逻辑文件名读取与最终 URL 内容一致，测试文件、元数据和多片测试会话已清理，没有发送聊天消息。
- 故障模拟覆盖前五条路线失败后香港代传成功、大陆与其他地区顺序、跨桶清空分片、同桶保留分片、无进展计时、冷却恢复与权限/取消边界。Go 1.24 移动源 race、服务端 race、核心构建回归和 15 项源码锁工具测试通过。
- Android 四 ABI AAR 与 ARM64 调试 APK 已构建，包内版本及原生库对应关系已核对；未安装真机。iOS 需 Mac 重建。
- 构建日志：`/home/ubuntu/media-upload-disaster-20261023`；完整回退到跨桶改造前：`/srv/99chat-production/backups/upload-disaster-20261023-004202/rollback.sh`。最后一次错误分类补丁的回退：`/srv/99chat-production/backups/upload-disaster-20261023-004522/rollback.sh`。

限制：这是新上传容灾，不会自动复制历史文件；两桶共用腾讯云。跨桶放弃的未完成多片会话仍依赖桶的生命周期治理，本次未修改存储桶生命周期策略。
