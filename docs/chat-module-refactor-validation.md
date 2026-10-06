# 聊天功能拆分验证记录

日期：2026-10-03。维护入口：[聊天模块](../lib/pages/chat/README.md)。

## 实际改动

- 聊天根目录只保留 binding、logic 和 view；13 个功能目录分别维护历史、回执、输入、消息、媒体、语音、表情、收藏适配、资金卡片、群状态、导航、通话和外观。
- 功能控制器实际持有自己的状态、队列和资源；主控制器约 800 行，保留页面协调、SDK 回调所有权和已有公开接口。
- 主页面从 581 行缩到 173 行，消息行及内容渲染归 `messages/widgets/`；保留消息 key、反向列表索引、语音监听、异步媒体浏览和现有资金展示参数。
- 功能测试归档至 `test/pages/chat/`，跨模块入口测试归档至 `test/integration/chat/`。
- 保留 OpenIM SDK、GetX、导航、公共组件和共享消息缓存。时间格式化使用的现有 `intl` 被显式声明为直接依赖，锁定版本没有升级。
- 拆分同时补充关闭、账号/token 切换后的草稿、媒体、表情、发送和排队已读保护。退出时当前账号的最终草稿仍能保存。

## 验证结果

| 检查 | 结果 |
| --- | --- |
| 聊天功能、入口、共享聊天组件与相关性能回归 | 267 项通过 |
| 新消息行实际挂载、菜单委托及语音转写监听 | 2 项通过 |
| 全量测试最终复跑 | 818 项通过、18 项失败 |
| 修改范围静态检查 | 无错误或警告；保留既有 SDK 弃用及风格提示 |
| Android debug APK | 构建成功 |
| 应用内部导入检查 | 无缺失路径 |
| 修改范围差异空白检查 | 通过 |

本轮没有提供实机帧率数据，iOS 构建和实机操作尚未验证。

## 全量剩余失败

剩余失败位于下列测试，不应将全量结果报告为全部通过。17 个失败标题与之前的性能检查快照相同；朋友圈的一个失败标题出现在当前工作区的新测试中。

| 测试文件 | 数量 | 范围 |
| --- | ---: | --- |
| `glass_navigation_test.dart` | 5 | 底栏安全区、玻璃样式和质量选项 |
| `mine_page_99chat_test.dart` | 1 | 我的页面尺寸与颜色 |
| `moments_feed_detail_test.dart` | 1 | 朋友圈菜单与举报入口 |
| `nickname_edit_entry_test.dart` | 1 | 昵称编辑入口 |
| `sdk_feature_completion_test.dart` | 2 | 群管理角色与禁言在 SDK 缓存滞后时的更新 |
| `security_devices_page_test.dart` | 2 | 登录设备加载、错误与重试 |
| `settings_99chat_flow_test.dart` | 3 | 账号安全、已绑定手机号及字体预览 |
| `settings_package1_99chat_test.dart` | 3 | 安全信息结构、关于页面和支付密码页面 |

本地日志保存在 `.dart_tool/`，不纳入 Git：

- [聊天相关回归](../.dart_tool/chat-modules-final-targeted-tests.txt)
- [新消息行回归](../.dart_tool/chat-message-tile-final-tests.txt)
- [全量测试最终结果](../.dart_tool/chat-modules-final-full-tests.txt)
- [功能控制器静态检查](../.dart_tool/chat-module-controllers-final-analyze.txt)
- [Android 构建](../.dart_tool/chat-modules-android-build.txt)
