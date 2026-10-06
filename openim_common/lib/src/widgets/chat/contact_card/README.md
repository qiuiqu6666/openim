# 个人名片消息

`ContactCardIdentityView` 负责把名片的显示账号与 SDK 目标分开，视觉继续复用公共 `ContactCardView`、`AvatarView` 和现有消息状态组件。蓝色主体与底栏来自已迁移的 99chat `ContactCardMessageItem`；将回执放进底栏是本次用户要求，参考实现本身仅在底栏显示时间。

## 账号与目标

- `CardElem.userID` 始终是原始 OpenIM 目标，点击资料、分享及好友凭证继续使用它。
- 卡片第二行显示 `UserFullInfo.account`，与当前资料页的 `displayedUserID` 相同；不截取或解码 `im_...`，不使用消息发送人或当前登录用户冒充目标。
- 新发送的卡片由 `ChatForwardingController` 获取目标资料，在现有 `cardElem.ex` 中增加 `contactCard: {userID, account}`。原来的 `inviteCode` 和服务端名片邀请流程保持兼容。
- 显示快照只有绑定的 `userID` 与卡片目标相同才读取，快照不参与鉴权或路由。历史卡片通过 `Apis.getUserFullInfo` 的安静模式查询真实账号；仅原始纯数字旧 ID 可在缺少资料时直接显示。

协议实现位于 `models/contact_card/contact_card_identity.dart`，查询位于 `services/contact_card/contact_card_profile_resolver.dart`。查询按登录用户和 token 隔离，合并同一目标的并发请求，并限制为 256 项 LRU 缓存。正常缺少公开账号的结果可缓存；网络失败不缓存。迟到响应、换账号、变更卡片目标和组件关闭均不会写入过期显示状态。安静查询不弹错误提示；鉴权失效必须仍属于发出请求的会话才能触发退出。

发送与推荐名片在打开选择器前固定会话，查询、获取邀请、SDK 建卡和发送的每次等待之后都检查关闭及会话变化。取消时静默结束，当前会话的真实错误使用原有发送失败提示。`selectCardContacts` 与 `createCardExtension` 的可选注入仅用于控制回归场景；默认仍走原联系人导航、真实资料查询、邀请接口和原生 SDK。

## 状态与布局

`ChatItemContainer.childWithStatusBuilder` 将同一个消息状态组件交给卡片底栏，个人名片不会在卡片外再渲染一份。时间只由底栏显示一次。已发送单勾、已读双勾、隐藏已读状态、群消息、失败重发和发送延迟仍使用现有 OpenIM 消息字段、隐私设置及回调。其他消息保持原来的状态位置。

`ContactCardTokens` 维护回执间距和账号行高。账号未知时保留同样的文字行高，补齐时不会使消息变高。亮暗主题均使用既有卡片配色；长昵称和账号省略，小屏大字体仍能保留时间和回执。

共享 `ChatDelayedStatusView` 拥有可取消的发送计时器：一秒延迟不会因账号或颜色刷新重启，发送完成立即隐藏，组件关闭取消计时器。名片的点击包装、私密消息过期保护、菜单、消息内容锚点和失败重发继续由既有聊天组件维护。

## 验证与预览

协议、查询和组件测试在应用的 `test/pages/chat/messages/contact_card/`。生成测试预览时使用 `--dart-define=CONTACT_CARD_MESSAGE_PREVIEW=true`；图片位于应用 `.dart_tool/contact-card-message-*.png`，只用于验收。正式数据不会来自测试夹具。

检查范围及四张亮暗主题预览见应用根目录的 [验证记录](../../../../../../docs/contact-card-message-validation.md)。真实设备与线上好友申请仍需部署后验收。
