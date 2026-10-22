# COS 广州桶切换（2026-10-21）

正式服务已切换新上传到 `gz99chat-1416337673`，地域 `ap-guangzhou`。
新文件地址为 `https://gz99chat-1416337673.cos.accelerate.myqcloud.com`。
2026-10-21 已切换 COS 全球加速域名，存储桶、`ap-guangzhou` 地域和对象路径不变。
聊天媒体上传端点和返回地址、收藏/表情公开地址、三公存储地址、客服广州服务端点及公开地址同步更新；服务端收藏/表情内部源站读取继续使用广州源站。
媒体允许列表同时保留广州原域名并加入加速域名，旧 URL 不批量改写。
加速状态为 Enabled；已验证加速域名写入后新旧域名读取内容一致，以及客服服务上传、读取、生成加速 URL 和清理。
本次配置备份及切换清单位于服务器 `/srv/99chat-production/backups/cos-acceleration-20261021`，其中含敏感配置，不复制到仓库。

## 三公与业务直传补齐

三公运行中的 `SANGONG_REPORT_PUBLIC_STORAGE_URL` 使用加速域名，图片/报表上传复用 OpenIM 对象服务。真实小图、大图上传、下载内容一致性与重复上传验证均通过；测试不发送聊天消息或运行游戏。

`cos-acceleration-copy.patch` 修复 COS 加速端点不能作为内部复制源的问题：`object.upload.cosCopyOrigin` 配置为同桶广州源站 `https://gz99chat-1416337673.cos.ap-guangzhou.myqcloud.com`，仅内部复制走源站；签名上传和公开下载仍走加速域名。未配置时保持原行为，禁止复制源跨桶。

`cos-acceleration-media.patch` 让收藏/表情 COS 直传签名使用配置的 `externalAddress`，新值为 `https://cos.accelerate.myqcloud.com`；内部读取仍沿用 `internalAddress`，保留旧源站识别与历史文件读取。已验证加速签名 PUT、下载内容一致性和清理。

本轮已部署 `chat-owner` 与 `openim-rpc-third`，并重载相关服务；存储桶、地域、引擎标记及历史 URL 保持不变。备份目录：`/srv/99chat-production/backups/cos-business-acceleration-20261021`；完整构建源码和日志：`/home/ubuntu/cos-business-acceleration-20261021`。未执行手机端完整业务流程。
旧香港桶 `99chat-1416337673`、`oss.99chat.vip`、旧 OSS/MinIO 均保留读取，不批量改写旧文件地址。

## 服务端改动

`open-im-server.patch` 针对 OpenIM 服务源码：COS 配置增加可选 `engineName` 和 `legacy`。
广州桶新对象使用 `tencent-cos-guangzhou` 标记；原 `tencent-cos` 记录继续使用香港桶读取。
仅当当前存储记录不存在时回退，不掩盖网络、权限错误；新上传和清理仍使用当前桶。

聊天媒体/三公复用第三方上传服务；三公发布文件允许的地址更新为广州桶。
收藏、表情、反馈、朋友圈相关配置以广州桶为主存储，原香港配置放入 `legacy`，继续保留更早的 MinIO/OSS。
新域名加入媒体来源允许列表，旧域名保留。
客服新增 `tencent_cos_guangzhou` 服务供新附件使用，旧附件的 `tencent_cos` 服务配置不变。
原 CDN 源站和旧桶访问权限没有修改；广州桶复制原有跨域规则。

## 验证

- 存储和第三方服务定向单元测试通过；新旧引擎标记隔离。
- 广州桶单片、分片上传（107385 / 1500000 字节）、并发完成和内容一致性通过。
- 正式上传接口签名目标为广州桶。
- 收藏/表情实际验证新桶写入、旧香港桶读取、旧 URL 保留。
- 正式服务抽查 5 条原 COS 逻辑链接均成功访问，另验证旧 OSS 文件访问成功。
- 客服实际新文件上传/读取/清理通过，旧服务保留。
- 相关服务 active，IM/Chat 健康检查正常。未执行手机端完整业务流程。

正式服务器配置及程序备份：`/srv/99chat-production/backups/cos-guangzhou-20261021`。
切换清单及配置前后副本：`/home/ubuntu/cos-guangzhou-config-20261021`（含敏感配置，仅留服务器）。
服务源码：`/srv/99chat-production/app/source/open-im-server`；本目录只保存无密钥补丁。
