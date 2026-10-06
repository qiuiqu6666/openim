# 收藏部署契约验证

`favorites_deployed_contract_test.dart` 是显式启用的真实 HTTP 测试，默认跳过。使用专用测试账号，以进程环境提供 `FAVORITES_LIVE_CHAT_TOKEN`、`FAVORITES_LIVE_USER_ID`、`FAVORITES_LIVE_BASE_URL`，不要把凭据写进源码、命令参数或日志。

测试经过正式 FavoriteApi / FavoriteRepository：创建带非空 block ID 的笔记与链接、解析真实空封面、读取详情、编辑、搜索、增量和发送准备。只清理本次创建的记录，不发送 SDK 消息。不能把它当作 Android/iOS 真机双账号收发验收。

也提供纯只读用例，验证现有列表、前三项详情及增量能够解析。可在已提供测试进程凭据后用 `--plain-name read-only` 单独运行；该用例不写入任何收藏。

```powershell
flutter test --no-pub test/integration/favorites/favorites_deployed_contract_test.dart --reporter expanded
```

存储公网地址的上传、下载验证与后端补丁见 `docs/favorites-interface-audit-2026-10-04.md`。当前服务器若仍签发 localhost 地址，图片/文件的客户端上传会被明确拦截，需要先部署服务端公网签名修复。
