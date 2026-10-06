# 圆角点击效果检查

检查日期：2026-10-04。以当前 OpenIM Flutter 源码为准，复核 99chat 客服分类按钮的触摸行为；代码索引未覆盖本工程，结论来自源码和实际绘制测试。

对 `lib` 和 `openim_common/lib` 的手写 `InkWell` / `InkResponse` 做结构扫描，末次扫描共 121 个入口。逐项核对点击区域、可见背景、圆角、最近的 Material 以及外层裁剪。相同背景和点击范围、内部列表行、带文字的整块操作区不按“小图标的外形”误判。

## 已确认并修复

| 位置 | 原因 | 处理 |
| --- | --- | --- |
| 通讯录搜索框 | 外侧留白也包含在矩形点击高亮中 | 保留完整触摸范围，搜索框自身使用圆角 Material 承载点击效果；组件归属 `contacts/directory/widgets/contacts_search_bar.dart` |
| 公共 `ImageTextButton` | Ink 背景为圆角，InkWell 和 Material 为矩形 | 点击圆角与背景一致，Material 按圆角裁剪 |
| 公共 `BottomSheetView` | 第一行、末行和取消按钮背景有圆角，高亮没有 | 按每项原有的顶部、底部或完整圆角约束点击效果 |
| 旧版账户设置行 | 分组首尾行背景有圆角，高亮没有 | 同步首尾圆角 |
| 语言设置行 | 分组首尾行背景有圆角，高亮没有 | 同步首尾圆角 |
| 好友设置行 | 支持自定义圆角的背景未约束高亮 | 使用相同自定义圆角或默认圆角 |
| 好友申请拒绝按钮 | 背景圆角、高亮矩形 | 同步圆角并裁剪 Material |
| 群申请拒绝按钮 | 背景圆角、高亮矩形 | 同步圆角并裁剪 Material |
| 表情面板添加格子 | 虚线边框有圆角，高亮矩形 | 点击圆角匹配虚线边框 |
| 表情管理添加和内容格子 | Container 裁剪子内容，墨水绘制在外面的 Material 上 | 格子改为自身的圆角 Material，约束添加、预览和整理高亮 |
| 朋友圈查看图片 | 只裁剪图片，InkWell 未指定圆角 | 点击圆角与单图、动态九宫格及详情九宫格的图片圆角一致 |
| 朋友圈发布图片 | 只裁剪本地图片，高亮没有圆角 | 点击圆角与图片一致 |

客服分类胶囊在上一轮已修复，并在本轮重新验证。未改动业务回调，通讯录搜索与客服分类仍保留外侧扩大的触摸范围。

## 核对后无需同类修复

- 会话搜索框、分组胶囊及添加按钮：点击圆角与各自可见背景一致。
- 用户资料账号胶囊和快捷操作按钮：点击与背景使用相同圆角。
- 新版设置分组、群管理分组、收藏卡片、资金详情选项、客服 FAQ：最近的 Material 自身已经裁剪。
- 聊天菜单和新消息提示胶囊：最近的 Material 具有对应圆角和裁剪。
- 红包打开按钮、直播复制按钮和游戏悬浮按钮：使用圆形 Material 和 CircleBorder 点击边界。
- 热门生态卡片和相册格子：点击圆角已与对应背景一致。
- 分享操作整块、群成员格子、朋友圈通知整行：点击范围包括标签或整行内容，内部小图标的边框不代表整个入口的边界。
- 收藏星标的外扩星光、悬浮按钮和卡片的静态阴影：是原有视觉效果，区别于点击时新增的越界高亮。

注意：给 Container 或图片加 ClipRRect，不一定能裁剪 InkWell 的墨水；墨水画在最近的 Material 上，应约束那个 Material，或给点击墨水设置与背景一致的边界。

## 验证

新增 6 项亮暗主题绘制回归，直接比较按下前后的像素，断言圆角外无新增高亮；同时确认内部高亮仍可见、扩大的触摸范围有效、一次点击只触发一次回调。覆盖公共图文按钮、普通胶囊按钮、底部选单首尾行、客服分类、通讯录搜索和表情添加/管理。

以下相关回归合计 49 项通过：

```text
flutter test test/widgets/rounded_ink_bounds_test.dart test/pages/contacts/directory/contacts_search_ink_test.dart test/pages/chat/stickers/personal_sticker_ink_bounds_test.dart test/pages/customer_service/customer_service_page_test.dart test/pages/chat/stickers/personal_sticker_panel_test.dart test/contacts_page_test.dart test/moments_actions_media_test.dart test/moments_compose_page_test.dart --no-pub
```

修改文件静态检查无 error / warning，存在旧文件已有的 info 级提示。未逐页进行 Android/iOS 真机按压截图验证；像素回归使用 Flutter 绘制测试。
