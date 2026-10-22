# 朋友圈固定媒体接口

2026-10-22 已部署服务端修复。客户端继续访问 `/moments/media/:mediaId/content`，由业务 API 完成权限检查并流式返回图片，不再跳转存储/CDN 域名。后续更换存储地址只调整服务端配置；已安装客户端无需为图片域名迁移更新。

原图、`variant=thumb`、Range 响应和 `private, no-store` 继续使用现有实现，存储继续复用 `MinioStore` 的当前配置与历史存储回退。读取不缓冲整张图片，媒体流量经过业务 API，部署容量需按访问量管理。

## 源码与发布

- `media-proxy.patch`：删除朋友圈读取接口的 CDN 跳转分支；上传及其他业务媒体接口保持原实现。
- `moment_media_proxy_test.go`：复制到服务端 `internal/api/chat/`，验证原图、缩略图、Range、拒绝权限与文件缺失。
- `moment_media_proxy_live_test.go`：同目录的可选只读校验，使用服务端存储配置和独立鉴权测试替身，不创建用户登录令牌、不改变生产数据。设置 `MOMENT_PROXY_LIVE_CONFIG` 为实际 `chat-rpc-chat.yml` 路径后运行 `go test ./internal/api/chat -run TestMomentMediaProxyLiveStorage -count=1 -v`。配置含密钥，只在服务器读取。
- `deploy.sh`：本次精确版本发布记录，包含原二进制校验、配置校验、备份、失败回滚和鉴权探测。后续发布重新核对基线，不直接重复执行。

构建基于与线上二进制 SHA256 相符的 `/home/ubuntu/device-login-api-fix-20261021/source`，保留此前安全与业务修复。完整发布源码、日志和二进制：`/home/ubuntu/moments-media-proxy-20261022`。

已于 2026-10-22 15:18:48 +08:00 发布 `99chat-sec-chat-api`。备份及回滚脚本：`/srv/99chat-production/backups/moments-media-proxy-20261022-151847/rollback.sh`。

## 验证

- API、命令入口、RPC TLS、媒体存储、朋友圈相关包测试通过，正式 API 构建通过。
- 真实存储原图 90935 字节、缩略图 21571 字节，经接口返回的 SHA256 与直接读取结果一致；修复前同一校验因 302 跳转失败，修复后成功。
- 客户端保留修复前代码，相关 28 项测试通过，包括同源图片读取；此前临时加入新域名的客户端修改已撤回。
- 服务 active、重启计数 0；未登录媒体访问被拒绝，配置校验未发生变化。
- 尚未进行手机端实际打开朋友圈的验收。真实存储校验使用隔离的鉴权替身，不等于真实账号端到端验收。
