# 手机日志诊断

入口：我的 → 设置 → 日志诊断（使用嵌入式设置时，位于我的页面的设置列表）。

- 平时采用精简日志，保留关键状态、错误、同步汇总及耗时达到 1 秒的成功调用。
- 开启临时详细诊断，原生 SDK 接受 600 秒窗口；关闭立即生效。SDK 上限 900 秒。
- 页面读取原生剩余时间，不持久化“已开启”状态，不更改全局 Debug/SQL 日志级别。
- 仅在开启且页面前台时，每 5 秒查询一次；后台停止，回到前台重新确认。
- 开启不会自动上传。需要反馈时，仍使用原来的意见反馈上传入口。
- 原生接口不可用、超时或返回异常时显示无法确认和重试，不显示虚假的开启成功。

实现按独立模块放在 `lib/pages/mine/settings/diagnostics/`，复用 SettingsScaffold、SettingsGroup、SettingsSwitchCell、SettingsSectionText 和 SettingsPrimaryButton。对照了本地 99chat 的 settings_page.dart/settings_widgets.dart，诊断入口为本项目新增能力，不声称来自参考产品。

Android/iOS 共用 `DiagnosticLoggingManager`；Android 桥接在 IMManager，iOS 注册在 IMManager、实现位于 IMDiagnosticLogging.swift。源码版本 recovery.45-branded-diagnostics。iOS 必须在 macOS 执行 native_sdk/patch15/build-ios.sh 重建 Framework 后再打包，当前 Windows 未生成 IPA。

验证包含：开关、原生到期、重复点击、失败重试、后台暂停/前台恢复、亮暗主题、1.8 倍文字、触摸区域和语义标签。移动端静态审查的“空状态/离线状态”提示不适用：该页面是本机配置开关，默认关闭即有效状态，无网络依赖。

## 日志显示名称

新日志使用 ChatSDK / ChatCore 标签和 chat-sdk-core 日期文件名。Go 日志在编码输出时统一替换上游名称，包括 caller、错误堆栈及结构化字段；原生桥接与 Dart 诊断日志同样处理。错误码、操作编号、文件行号与耗时保留。只处理日志展示，不改通信协议、数据库内容、包名或第三方版权声明。历史日志不删除，收集器兼容旧文件名。

third_party/tools 固定复制现有 v0.0.50-alpha.80 依赖，保留原许可证，改动仅在日志 encoder 与其测试；随共享源码锁定，Android/iOS 使用同一份输出策略。正常桥接成功日志只在详细诊断窗口内记录，不输出完整回调数据。

Android 3.0.1+2044 已安装到 2506BPN68G，原生库与 AAR 校验一致。真机验证默认关闭、开启、返回页面保持开启、手动关闭、开启后重启恢复精简。自动到期由单元测试验证，未在真机等待完整 10 分钟。采样 116 条应用诊断输出未发现旧品牌标识；不包含系统显示的包名/Activity 元数据。未执行温升或耗电对比测试。
