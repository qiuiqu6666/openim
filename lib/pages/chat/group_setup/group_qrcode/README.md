# 群二维码

展示参考用户提供的邀请卡截图：群头像、群名、次级群号与复制入口、白底黑码边框、扫码提示、纵向保存/扫码按钮。页面复用 GlassAppBar、AvatarView、AppTokens 与现有 GetX 群状态，不显示额外的邀请说明卡片。

卡片使用 16dp 内边距，头像与文字间隔 12dp，群名、ID 和标签间隔 4dp，头部与二维码间隔 12dp。群名仅显示一行，超出可用宽度时用省略号截断，不换行。复制按钮放在头部独立一列，保留 48dp 点击区域，避免按钮撑大 ID 行造成空隙。

卡片底层使用用户提供的淡蓝色 99CHAT 水印原图（assets/99chat_watermark.png），按比例铺满并随圆角裁切。group_qrcode_background.dart 管理背景绘制；暗色主题仅在绘制时将原图白底变透明并以主题蓝色显示水印，原文件不修改。二维码仍有独立的白底和留白区。水印位于 RepaintBoundary 内，保存前等待背景图片加载和下一帧绘制，保存卡片时一并保留。

二维码载荷继续使用 GroupQrcodeLogic.buildQRContent；显示和复制保留真实群 ID 的前导 @，旧数据没有前缀时补齐 @，与群资料页一致，空 ID 不生成前缀。保存继续截取 RepaintBoundary，扫码继续使用现有群扫码与加入群资料流程。

GroupQrcodeContent 仅负责展示，GroupQrcodeLogic 负责复制/保存/扫码，GroupQrcodeTokens 维护布局。暗色主题仍使用白底黑色二维码以确保可扫描。
