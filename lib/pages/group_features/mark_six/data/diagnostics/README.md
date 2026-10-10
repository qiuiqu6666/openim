# 六合彩请求诊断

调试构建在控制台搜索 `[六合彩API]`。通过现有 `GroupFeatureApiDiagnostics` 异步作用域记录实际请求、响应摘要和异常，不新增请求、不改认证、缓存或权限。正式发布构建不打印。

- 群入口检查记录当前群和 `gameType`，类型 2 才查询机器人绑定。
- 绑定查询记录跳过、合并、旧响应忽略和最终 `bound/enabled/showFloatingEntry`。
- 开奖、代理、反水及导出记录真实 URL、method、operationID、HTTP status、业务 code 和耗时；缓存命中时说明未发请求。
- `hasBearerToken` 只记录是否携带非空 Bearer 鉴权；不输出令牌。
- 只打印响应类型、条数和绑定布尔值；不打印请求头原值、请求体、查询值、响应正文或原始异常文字。URL 去除凭据、查询及片段，不读取下载或响应流。

测试：`test/pages/group_features/mark_six/data/diagnostics`。
