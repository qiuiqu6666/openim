# 群个性化

群管理中的群主可选择群名颜色、通过现有相册裁剪上传流程设置小图标，并预览、移除图标或恢复默认。只修改群名称表现，不修改成员昵称、群头像或权限。

共享资料位于 GroupInfo.ex.groupPersonalization，version=1，color 为不透明 ARGB 整数，iconUrl 为 HTTPS 图片地址。保存时重新读取群资料并合并，只替换本字段。非法旧 ex 拒绝覆盖。恢复默认写入空颜色与图标；未设置时使用默认主题文字颜色，游戏类型不再参与着色。

保存检查当前账号、群、权限代次、成员状态，并重新读取当前用户角色；写入仍由 SDK/服务端群资料权限校验。成功后通过既有群资料事件更新缓存。GroupNameLabel 监听共享缓存，聊天标题通过通用 titleWidget 插槽复用，不改变 SDK 生命周期。

设置只对使用此版本的客户端生效，旧客户端忽略新增字段。SDK ex 更新没有原子字段合并接口，多个管理操作同时写入 ex 时仍遵循现有 SDK 最后写入规则。

界面采用渐变预览卡、网格颜色选项、横向图标选择和固定底部保存按钮。仅提供默认颜色和预设颜色；内置图标以 iconKey 保存（robot/heart/crown/game/beer/football），并复用共享群名组件显示，未知标识忽略。上传图标与内置图标互斥。

Reference layout uses a 938px baseline with six color columns and seven icon columns (fewer on narrow screens). All thirteen icons reuse source windows from the supplied artwork, including shared group-name rendering. The preview retains real group data. Layout values live in group_personalization_style.dart. CAPTURE_REFERENCE enables local rendered comparison using Windows system fonts.
