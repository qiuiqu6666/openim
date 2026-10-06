# 收藏接口深入检查与修复记录

> 2026-10-05 续查：用户确认“收藏原件不可用”发生在收藏页添加图片／文件。当前生产仍未加载公网签名修复；新增媒体失效恢复与归档确认兼容修复，详见 [续查记录](favorites-original-unavailable-2026-10-05.md)。该入口不能与聊天归档重试混作同一根因。

检查日期：2026-10-04。触发问题：添加收藏提示“参数不对”，图片和文件上传失败。对接基线为[部署契约](favorites-client-contract.md)，检查同时覆盖前端正式调用路径、运行服务器源码及登录态下的真实 HTTP 响应。

## 结论与当前状态

两个主要原因均已复现：

1. **添加请求缺少服务端必填的 block ID。** 前端创建 `b1` 后，序列化却默认省略 `id`；部署服务端明确要求 `block.ID != ""`。旧请求返回 `1001 / block is invalid`；补齐后笔记、链接、图片和文件的创建请求返回 `errCode=0`。前端已修复，笔记和链接也已通过正式 FavoriteRepository 的真实 HTTP 集成测试。
2. **媒体签名地址指向服务端的 localhost。** 初始化上传返回 `errCode=0`，但 `uploadURL` 为 `http://localhost:10005/...`。客户端访问的是自己的设备，所以 PUT 失败。同一条签名 URL 在服务器本机 PUT 返回 200，随后 complete 和创建媒体收藏成功。预览及发送准备的下载 URL 同样指向 localhost，需要服务端独立公网签名端点。

从聊天消息收藏媒体还存在第三个服务端兼容缺陷：**OpenIM 对象网关使用逻辑文件名，收藏归档却直接把它当 MinIO key。** OpenIM 会先查逻辑名映射，再访问实际 `date/userID/random.ext` 存储 key；当前收藏归档缺少这一步。该问题由两边源码确认，与客户端上传签名端点不同。

另外确认了成功响应空封面、发送租约继承、删除冲突响应缺少当前记录、删除幂等重放两项服务端缺陷，以及上传恢复、迟到响应和界面重复操作问题。前端修复已进入当前工作区；服务端修复以独立补丁交付，**本次未修改正在运行的服务端配置、源码或进程，未重启服务**。媒体客户端端到端上传和收发仍需补丁部署后验收。

## 真实检查范围

| 项目 | 实际环境或方式 |
| --- | --- |
| 前端 | 当前 `openim-flutter-demo` 工作区，正式 FavoriteApi / FavoriteRepository |
| Chat API | `http://8.217.191.236:10008` |
| 运行服务源码 | `/www/wwwroot/chat`；实际 chat-api、chat-rpc 进程工作目录均在这里 |
| 对象存储内部端点 | `localhost:10005`，收藏继承 sticker MinIO 配置 |
| 对象存储公网健康检查 | 客户端与服务端本机访问 `http://8.217.191.236:10005/minio/health/live` 均返回 HTTP 200 |
| 身份 | 开发模拟器已有登录态；凭据只在内存和测试子进程环境中使用 |
| 数据保护 | 仅创建和清理本次自有测试记录，不发送 SDK 聊天消息；日志保存字段形状、错误码和 operationID |

现有 GitNexus 索引属于其他旧仓库，没有当前 OpenIM 项目索引。因此没有套用旧图结论，本次按当前源码、服务器运行目录和真实响应逐项核对。服务器已有未提交改动保留不动。

## 接口验证结果

表中的成功表示实际 HTTP 与业务响应成功，不代表已在接收端验收媒体发送。

| 操作 | 真实结果 | 判断 |
| --- | --- | --- |
| quota | HTTP 200，`errCode=0`，双能力均为 true | 能力接口正常 |
| 列表、增量 | HTTP 200，`errCode=0` | 基础读接口正常 |
| 添加笔记，旧正文无 block ID | HTTP 200，`errCode=1001`，`block is invalid` | 确定的前端参数缺陷 |
| 添加笔记、链接，正文含 `id:b1` | `errCode=0`，ready | 参数修复有效 |
| 详情、PATCH、搜索、增量、文字 prepare | 正式前端真实 HTTP 集成测试通过 | 正式序列化和解析路径验证通过 |
| 图片、文件 upload init | `errCode=0`，返回 localhost URL | 初始化业务成功，地址配置错误 |
| 客户端原 URL PUT | 网络连接失败 | URL 指向客户端自身 |
| 服务器本机相同 URL PUT | HTTP 200 | 签名本身有效，内部存储可用 |
| 本机 PUT 后 complete | `errCode=0`，图片检测为 image/png | 原件校验和完成流程可工作 |
| 创建图片、文件收藏 | `errCode=0` | block ID 与完成资产正文正确 |
| 媒体 asset-access、prepare | `errCode=0`，URL 仍为 localhost | 预览和快捷发送同样被公网端点阻塞 |
| 现有消息媒体收藏 | 只读观察到 archive_failed，空正文和空 contentRevision | 前端解析已修复；归档存在逻辑名映射缺陷，当前失败项的精确阶段无日志证据 |
| 旧版本 DELETE | `20061`，不带 `data.item` | 前端应补读最新详情并重新确认 |
| 批量删除首次混合结果 | 一项 versionConflict、一项 deleted，返回 version | 逐项处理正常 |
| 相同批量 UUID、相同正文重放 | `errCode=0`，`items:[]` | 确定的服务端幂等缺陷 |
| 首次单项 DELETE | `errCode=0` | 首次删除正常 |
| 相同 DELETE UUID 重放 | `20067` | 不符合“本人已删除仍成功”的删除契约 |
| 本次记录清理 | 所有本次创建的记录已删除 | 未批量清理其他数据 |

本次受控 HTTP 复现创建 5 条记录，正式前端集成测试再创建 2 条，均只按本次已知 ID 清理。最初两个失败上传的少量预留空间遵从服务端 24 小时回收规则；服务端没有上传取消接口，没有清理其他上传。

## 前端修复

### 写入正文和真实响应

- 新构造的 `FavoriteBlock` 默认输出稳定 ID。笔记、链接、媒体创建和正文修改均携带 ID。
- 旧响应缺少 ID 时保留读取兼容；既有 outbox 重放不擅自补字段或改变同一个 UUID 的正文。已经确定为参数失败的动作结束，用户重新添加使用新 UUID。
- 可选 `coverAssetID:""` 等空字符串按无值处理，必填字段、错误类型和版本仍校验。
- pending_archive / archive_failed 尚未生成内容版本时 `contentRevision:""` 按 null 处理，允许列表、详情、增量和轻量缓存读取；这些记录仍不可发送，prepare 的版本要求不放宽。
- `prepare.downloads[]` 缺少逐项到期时间时继承顶层租约；两处都有时间时取较早者。独立 asset-access 继续要求自身有效期。
- 批量删除结果接收部署使用的 `result`、`version`。结果缺项或空项不会被当作全部删除成功。

涉及 `lib/services/favorite_api.dart`、`favorite_models.dart` 与 `lib/pages/favorites/models/favorite_batch_delete.dart`。

### 上传原件和恢复

- 选取原件后结合文件头、原文件名和媒体库 MIME 识别格式；HEIC 原件不替换成 JPEG 缩略图，M4A 使用 audio/mp4。将 PDF 选作图片时在提交前拒绝。
- init 的 declared MIME 保留到 PUT；遵守签名 Content-Type，兼容请求头大小写。独立媒体请求不带业务 token、授权头或 cookie。
- 远程 Chat 服务返回 loopback 媒体地址时显示“媒体地址配置错误，请联系管理员修正收藏存储地址”；不改写签名 host，也不泄露 URL 查询串。该配置错误保留原重试编号，服务端修复后可以继续原操作。
- complete 明确返回 20056 时结束失效 upload ID，下次主动操作重新上传。网络结果未知和 20066 保留原请求编号。
- MIME 修正产生新的上传身份，避免同 UUID 改正文；已完成资产优先恢复。旧视频完成记录缺少封面时重新核对原 complete 操作。

涉及 `lib/pages/favorites/media/favorite_picked_media.dart`、`data/favorite_media_upload.dart` 和 API 媒体入口。

### 仓储、冲突和快捷发送

- 已知 expectedVersion 的删除直接按该版本提交，避免额外详情读取阻断已经删除记录的幂等处理。
- 迟到详情不能覆盖、返回或复活更高版本/删除墓碑；归档轮询按项隔离失败，清除已不存在的归档项。
- 单项和批量删除冲突没有 item 时只读补齐；选择保留，读失败不得再次提交已知冲突的旧版本。拿到最新记录后再次确认才删除。
- 添加入口在打开类型选择器之前加锁，快速连点不会打开多个选择器或重复提交。
- 收藏摘要有正文但没有媒体资产时，快捷发送先读完整详情，并核对固定 contentRevision，再准备原件；不跳过完整性检查，也不静默发送修改后的其他内容。
- 当前动作并行提交不能用新的 UUID 替换尚在处理的旧身份；未知发送结果仍保持原任务核实机制。

涉及 `lib/services/favorite_repository.dart`、`favorite_send_coordinator.dart`、收藏管理/详情页和对应 data 模块。

## 服务端必须修复的部分

### 公网签名端点

实际服务使用 `favorite.go` 构造的 MinIO client，端点只有 InternalAddress。`favorite_archive.go` 的 presignPut / presignGet 也使用这个内部 client，所以正确的内部地址泄漏成客户端不可访问的媒体地址。

修复要求：

1. 保留内部 MinIO client 供上传完成校验、复制、归档等服务端操作。
2. 增加明确的公网存储 URL 配置，用同一存储凭据创建独立签名 client。
3. PUT 和 GET 在签名之前选用公网 client。不得签名后替换 host，因为签名包含 host。
4. 校验 URL 协议、host 和端口；不能包含凭据、查询串、片段或额外路径。
5. 本环境公网存储根地址为 `http://8.217.191.236:10005`。若以后改为域名/HTTPS，应让代理保留签名所使用的 host。

隔离补丁及应用说明位于 `server/favorites/patches/`。完整生产 YAML 含存储凭据，本次没有复制到前端仓库，也没有打印。

可审阅产物：

- [服务端补丁说明与验证结果](../server/favorites/patches/README.md)
- [0001 公网签名](../server/favorites/patches/0001-favorite-public-storage-signing.patch)
- [0002 删除回执重放](../server/favorites/patches/0002-favorite-delete-replay-receipts.patch)
- [0003 原件逻辑名解析与归档重试](../server/favorites/patches/0003-favorite-openim-object-name-resolution.patch)
- [无凭据配置片段](../server/favorites/patches/config.public-storage.example.yml)

完整系列按 0001 → 0002 → 0003 应用，不能用示例片段替换含现有设置的完整配置。补丁基于本次实际服务器源码快照，部署时若源码有新改动应重新核对和测试。

本次上传复现中私人媒体资产合计只有 96 字节。删除记录后若仍处于已准备的下载租约内，资产保留与容量释放可能有延迟；不能仅凭 usedBytes 非零断言记录未清理。配额、对象延迟回收和列表记录是不同状态。

### 删除幂等重放

批量处理在 replay 命中时直接返回空响应，没有持久保存首次逐项结果。必须保存并重放第一次的每项状态和版本，不能重新执行删除：首次 versionConflict 的记录仍然存在，重放不能顺手删掉它。

通用 replay 又对已经删除的 ResultRef 返回 20067，连 DELETE 自己也被拦截。DELETE 应重放第一次的成功；已删除对象的旧 create/update 请求继续遵守 20067，不自动复活。

旧的批量请求没有保存完整结果时，不能伪造原结果或重跑删除。补丁应给出可识别的未确认结果，或仅在证据足够时只读恢复，具体处理及回归见补丁说明。

本次补丁范围是**已经成功持久化收据之后的顺序重放**。另一个预存问题没有被掩盖：首次处理缺少原子请求占位，Mongo SaveRequest 为无条件 upsert。相同 UUID 首次并发可都进入删除循环并互相覆盖收据；删除后、收据保存前崩溃或保存失败也无法保证原始逐项结果重放。SoftDelete 的版本/删除状态校验可避免对已经删除的同项再次释放配额，但不能替代完整请求幂等。后续需要数据库原子 claim、请求 hash 不可变和崩溃恢复策略；不能靠单进程锁解决多实例问题。本报告不把这部分宣称已修复。

### 从消息归档的对象映射

证据链：

| 服务 | 源码行为 |
| --- | --- |
| Chat `internal/rpc/chat/favorite_archive.go` | objectNameFromMessageURL 提取 `/object/` 后的 name；statKey / copyKey 直接将其作为 MinIO key |
| OpenIM `internal/api/third.go` | ObjectRedirect 将路径 name 交给 AccessURL |
| OpenIM `internal/rpc/third/s3.go` | 上传保存 `Object{Name:req.Name, Key:result.Key}`，网关 URL 使用逻辑 Name |
| OpenIM `pkg/common/storage/controller/s3.go` | AccessURL 先 GetName 查对象映射，再对 `obj.Key` 取访问地址 |
| OpenIM 上传存储 | 实际 key 形如 date/userID/random.ext，与逻辑 Name 独立 |

因此不能对所有原会话附件直接执行 `StatObject(bucket, logicalName)`。修复应在原消息已经核验访问权限之后，通过已有 OpenIM 对象接口解析真实存储位置，再归档；应校验返回端点、bucket、key，禁止任意 URL 下载和猜测路径。

隔离修复使用 OpenIM `/object/access_url` 解析旧 snapshot 保存的逻辑名，保留原会话消息验证和快照策略；仅接受配置中的存储端点、协议与同一 bucket，拒绝路径穿越和重定向，限量读取原件并检查格式后保存私人副本。来源 GET 不携带业务 token。失败重试的来源预检查也走相同解析，不再检查错误的逻辑存储键。

共享 IM API 调用器原先会打印完整返回体。该对象解析接口新增脱敏日志，错误泛化，不把短期签名 URL、上游返回正文或 HTTP URL 错误带入日志和对外错误。其他接口日志行为不在这份补丁中改动。

当前归档错误分支只更新 archive_failed，未记录底层 stat/copy/read/inspect 错误。安全日志检查没有找到本次记录的明确失败原因；没有读取用户原件或直接查询用户 DB，所以本报告不把某一现存记录的具体失败阶段当作已证实。需要独立对象映射回归和不含私有 URL 的错误阶段日志。

## 验证与剩余验收

各项验证区分模拟契约测试、真实 HTTP 和真实设备收发。

| 检查 | 最终结果 |
| --- | --- |
| 前端收藏及相关聊天回归 | 31 个测试文件，207 项通过；2 项真实 HTTP 用例在普通回归中按设计跳过 |
| 真实 HTTP 写入集成 | 显式启用后通过：正式仓储笔记/链接创建、详情、编辑、搜索、增量、prepare 与本次记录清理 |
| 真实 HTTP 只读集成 | 显式启用后通过：现有列表、详情与增量，包括新出现的 archive_failed 响应 |
| 定向静态检查 | 62 个相关源码/测试文件，No issues found |
| Android 调试 APK | 最终前端修改后编译成功，`build/app/outputs/flutter-apk/app-debug.apk` |
| 当前范围修改行空白检查 | 通过 |
| 服务端隔离 Go 检查 | 真实 chat 包 39 项、imapi 包 2 项，共 41 项通过；15 项新增、26 项已有。完整 chat-rpc 编译成功，新二进制未运行 |
| 服务端补丁应用检查 | 0001/0002 独立检查及 0001→0002→0003 完整系列检查/副本应用通过；最终 12 个文件与测试 overlay 的 gofmt 源码一致 |
| Android/iOS 双账号媒体实际收发 | 尚未验收，仍需服务端补丁部署 |

新增 `test/integration/favorites/favorites_deployed_contract_test.dart` 显式启用真实 HTTP，默认跳过。通过进程环境提供专用测试账号，不在源码或命令参数里写 token。该测试经过正式 API/仓储，创建自己的笔记和链接，读取、编辑、搜索、同步和 prepare 后清理自己的记录。首次运行时排除了 Flutter 测试默认的 HTTP 400 替身，随后真实服务测试通过。

现有模拟 HTTP/SDK 测试此前未包含部署服务强制 block ID、空封面和逐项下载无 expiry 的响应，因而不能证明真实链路可用；本次补上部署响应回归，并加入显式真实 HTTP 测试。此前“167 项通过”的记录仍保留为当时测试范围，不代表服务端验收。

尚待服务端补丁部署后的验收：

1. 客户端实际 PNG/JPEG、HEIC、普通文件上传、complete、创建、预览。
2. 视频封面和音频元数据的真实原件上传。
3. 公网签名 PUT/GET 的访问、到期与重新 prepare，大小/SHA-256 仍需一致。
4. 相同 UUID 的单删成功重放、批量混合结果原样重放，冲突项仍存在。
5. Android/iOS 双账号接收原生文字、图片、视频、音频、文件；删除收藏后已发消息继续可用。
6. 从已有会话消息收藏的权限、撤回、归档失败重试和跨设备通知。

本次没有向真实对话发送测试消息，也没有替换开发模拟器当前安装包。当前模拟器包早于本轮最终修复；新 APK 编译成功与已安装设备验收是两项不同检查。

## 排查证据位置

临时检查日志位于项目 `.dart_tool/`，不会作为生产配置提交：

- `favorites-deployed-before.json`：无 ID 的 1001 与客户端媒体 PUT 失败。
- `favorites-deployed-write-repro.json`：同 URL 服务器本机上传、complete、媒体创建及清理。
- `favorites-deployed-batch-repro.json`：单删/批量冲突与原 UUID 重放。
- `favorites-audit-live-flutter.log`：正式前端真实 HTTP 集成测试结果。
- `favorites-audit-live-readonly.log`：正式前端只读解析现有归档失败项。
- `favorites-audit-regression.log`、`favorites-audit-scoped-analyze.log`、`favorites-audit-android-build.log`：最终前端验证。

日志只记录字段类型、长度、空值、状态和 operationID，便于对应服务端日志；不保存账号 token、媒体签名查询串或其他用户收藏正文。
