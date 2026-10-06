# 通知设置

对照 `reference-99chat/lib/src/pages/settings/notification_settings_page.dart` 的两组通知设置与独立提示音选择页，继续复用 `SettingsScaffold`、`SettingsGroup`、`SettingsCell`、`SettingsSwitchCell` 和共享 action sheet。旧 `settings/pages` 路径只保留导出，已有 Mine 入口继续传入真实 `SettingsDraftStore` / `SettingsService`。

- `notification_settings_page.dart`：页面与设置交互。通知显示内容、前台横幅、声音、振动、通话铃声、快捷接听和快捷回复保存到当前账户设置。只有服务声明 `supportsRemoteNotificationSettings` 时，关闭状态的开关和显示内容才等待服务确认；失败保留原值并显示可重试提示。当前 OpenIM 服务使用本地通知能力，不伪造远程同步。
- `notification_permission_gateway.dart` / `widgets/notification_permission_banner.dart`：系统权限访问、提示、请求和返回应用后的检查。组件持有生命周期监听；销毁和替换网关时作废旧异步结果，按钮执行期间禁止重复请求。
- `message_notification_sound_picker_page.dart`：提示音选择、选中语义、错误提示与试听编排。最新选择覆盖旧加载任务；离开页面、进入后台或切换账户后禁止旧任务继续播放。通话中可保存选择，但延后试听，避免抢占通话音频。
- `message_notification_sound_preview.dart`：该路由专用的播放器访问与资源释放，复用 `core/notifications/message_notification_sound.dart` 的声音目录。页面不改变全局音频会话配置。

持久化由 `SettingsDraftStore` 负责；账户归属在构造时冻结，并拒绝已退出账户或已销毁实例写入。实际前台/后台收到消息后的提示由 `core/notifications` 负责，来电行为由现有通话模块负责。应用进程被杀死后的远程推送仍取决于服务端及推送提供商链路，页面本地选项不会代替该链路。

测试：

```text
flutter test test/settings/notifications
flutter test test/settings/notifications/notification_settings_preview_test.dart --dart-define=NOTIFICATION_PREVIEW_DIR=docs/previews/notifications
```

预览导出使用真实 Flutter 页面和测试账户、权限、错误夹具，包含两套主题的正常、权限、禁用、内容选择、保存失败和声音页状态，不触发真实消息、远程请求或系统权限。
