# 相册与定位同步验收记录

实现记录：2026-10-05；默认启用及四项默认开启调整：2026-10-06。协议以用户粘贴的「相册和定位上传」为准，所有 Chat 请求携带与登录一致的 deviceID、deviceName、platform；数据归属 token 对应账号，不在请求体传用户号。

## 本次完成

- 设置入口为「相册与定位同步」。账号没有保存偏好时，照片、视频、登录定位、仅 Wi-Fi 相册同步四项默认开启，缺少已保存选择的开关也按开启处理；已保存的关闭选择继续按账号生效。首次登录不显示应用内同意弹窗，手动重新开启视频仍需单独确认。仅使用已有系统权限，未授权时跳过；定位每次登录只获取一个新点。
- 接入 `/chat/device-sync/media/probe`、`ticket`、`finish` 和 `/locations`。媒体原始字节直传签名 OSS URL；Chat 只接收元数据与完成确认。
- 限制 OSS 为 HTTPS、精确 `99chat.oss-cn-hongkong.aliyuncs.com` 主机，无用户信息/片段、不跟随重定向。上传使用独立传输，只携带协议要求的 Content-Type/Content-Length，不继承 Chat token 或其拦截器。
- SHA-256 使用独立 isolate，文件读取与 OSS PUT 流式进行。每页只读 24 条元数据，一次一个文件/分片，不解码、压缩图片。照片上限 30 MiB，视频上限 512 MiB，分片 4 MiB。
- 本地完成与重试数据按账号、服务地址、登录 deviceID 隔离。内容修改、冲突、未完成 finish、取消后晚结果及排队写入均受校验；不把 token、签名地址或媒体字节写入同步数据库。
- iOS 原件桥禁止网络访问，只导出本地 PHAssetResource，跳过 iCloud；缓存随机命名，取消和释放只删除本桥自有原件导出文件。
- GPS 只收集本次开始后的新位置。10 秒超时取消订阅并跳过该登录内的定位请求，旧的待传点也不会替代本次超时结果。迟到事件、缓存位置及关闭后的旧位置不上传。
- 登录不等待上传；聊天、来电/通话、触摸和后台优先。关闭同步立即生效，设置落盘延迟也不能使旧任务复活。网络错误保留 2–15 分钟退避；无效 token 只停止同步，不退出 IM。

## 对照与复用

对照 `reference-99chat/lib/src/services/device_sync_service.dart` 的前台空闲、用户活动让路、后台取消行为。本次按新 OSS 协议实现原件上传，不复制其压缩与旧上传接口。

复用当前 PhotoManager、Geolocator、Dio、crypto、Hive、DataSp 登录 deviceID、主题和设置组件。新增模块负责本项目之前没有的设备同步协议与调度；新增 iOS 小桥是因为普通 `originFile` 路径不能严格保证跳过 iCloud。没有修改 IM 核心消息、草稿或通话传输。

## 已运行验证（2026-10-05，默认启用调整前）

| 验证 | 结果 |
| --- | --- |
| Chat/OSS 协议、地址、签名、分片和认证隔离 | 15 项通过 |
| 实际 isolate 合成文件哈希、取消、句柄释放 | 6 项通过 |
| 平台权限、iCloud 跳过、GPS 新点/超时/迟到/取消 | 9 项通过 |
| 队列、内容冲突、续传、旧写拒绝、账号隔离、超时跳过旧定位 | 11 项通过 |
| 会话、关闭竞态、旧说明、认证封锁与退避 | 7 项通过 |
| 设置页、说明、单弹窗、账号切换、日夜/320px/双倍字号 | 13 项通过 |
| 同步模块及设置页静态分析 | 无 error/warning；最终日志另存 |
| 应用集成文件静态分析 | 无 error/warning，4 项既有 info：super 参数、showBadge 类型、旧 textScaleFactor |
| Android debug 构建 | 成功，独立保存 app-device-sync-debug.apk |

同步专项合计 **61 项通过**。测试使用 mock、临时合成文件和隔离 Hive，没有读取开发机真实相册/GPS，也未调用真实上传接口。

APK：`build/app/outputs/flutter-apk/app-device-sync-debug.apk`，383248239 字节；SHA-256：`53B4C3BDBC47C0073B39BA57FEDD0A46CEEE83DF852BD72AF94F68C89195BCDE`。

扩大登录/会话/聊天回归得到 77 项通过、12 项日期跳转测试失败。失败均在日历弹窗 `pumpAndSettle`：旧 fixture 未完成新增图片预览查询，且仍查找已替换的 CalendarDatePicker。该 fixture 使用空的同步回调，没有运行设备同步；本次未修改日期功能或其测试。不能将这次扩大回归表述为全通过。

验证日志位于 `E:/openim/.temp/device-sync-module-tests.log`、`device-sync-runtime-final.log`、`device-sync-analyze-final.log`、`device-sync-module-analyze.log`、`device-sync-login-chat-regression.log` 和 `device-sync-android-build.log`。

## 默认启用调整验证（2026-10-06）

- 删除首次相册与定位同意弹窗及登录、设置页调用入口；新账号照片与定位默认开启，视频默认关闭，相册默认只用 Wi-Fi。旧版已确认保存的开关选择继续保留。
- `flutter test --no-pub --reporter expanded test/core/device_sync test/pages/mine/settings/device_sync/device_sync_page_test.dart`：最终 **70 项全部通过**，覆盖默认启动、登录与空闲条件、旧偏好迁移、关闭保持、账号切换、系统权限不足，以及原有上传、取消和重试行为。测试未读取真实相册/GPS，未调用真实上传接口。
- 同步模块、设置页、AppController 及专项测试静态分析：无 error/warning；AppController 的 `showBadge` 参数有 1 项既有类型注解 info。使用 `--no-fatal-infos` 时退出码为 0。
- 最终 `flutter build apk --debug --no-pub` 成功；本次安装包为 `build/app/outputs/flutter-apk/app-debug.apk`。上方 `app-device-sync-debug.apk` 是调整前的历史安装包。
- 首轮回归中，旧退避计时测试出现一次 299.681ms 与 300ms 阈值的临界失败；最终全套重跑通过，计时断言保持原样。
- 全部生产与测试引用检索已无首次弹窗、同意回调或等待确认状态。持久化 JSON 中保留旧版 `consentDecided` 标记，仅用于兼容已保存的开关选择，不再作为同步确认门槛。

## 四项默认开启（2026-10-06）

- 当前默认值调整为照片、视频、登录定位、仅 Wi-Fi 相册同步四项开启，适用于未保存偏好的账号及缺少已保存开关选择的旧账号。明确保存的关闭选择逐项保留，不强制恢复开启。
- 默认开启视频不触发确认弹窗；手动重新开启视频仍使用既有确认。系统权限不足时继续跳过，不主动申请权限；账号、服务地址、设备隔离和会话取消规则保持不变。
- 本节只记录当前行为调整，尚未记录本次新增测试、静态分析或构建结果。上方两次已运行验证是历史记录，不代表四项默认开启调整已经完成验证。

## 尚未完成的实际验收

- Windows 环境没有 Xcode，本次没有编译 iOS；需要 Mac 编译并检查本地/仅云端/有限相册授权、导出取消与临时文件释放。
- 未连接真实后端/OSS 验证上传、分片合并、签名过期、重复文件识别及设备身份绑定。Chat 使用项目现有 Config.appAuthUrl；OSS 强制 HTTPS，不代表 Chat 地址已改为 HTTPS。
- 未用 Android/iPhone 真机验证定位服务实际停止耗时、弱网切换和授权撤销。
- 没有进行真机帧率与内存分析，不能宣称零掉帧。建议 profile 模式覆盖大量相册、本地与 iCloud 混合、1/8/30 MiB 图片及大视频，记录帧耗时 p95/p99、RSS、磁盘峰值和取消到资源释放耗时，并检查聊天及通话交互。
- 当前队列在后台暂停，不保证锁屏、离开前台或系统终止进程后继续上传；需要再次进入前台后续传。
