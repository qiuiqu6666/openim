# 三公用户展示资料

公开账号通过现有 Chat 用户资料接口读取；真实头像只通过 OpenIM SDK 的 getUsersInfo 读取。内部 userID 仅用于请求匹配、导航和业务操作，不作为可见账号或姓名的兜底值。头像复用公共 AvatarView，沿用应用主题。

- data：合并同一批可见用户的请求，每批最多 50 人；缓存最多 512 人、有效期 1 分钟。
- models：展示资料与安全姓名兜底。
- widgets：公开账号、用户姓名与 IM 头像；通过 SangongIdentityScope 注入测试数据源。

缓存绑定当前登录用户、Chat token 和服务地址。登录变化清空缓存，迟到结果丢弃；页面组件同时核对当前群、权限和会话作用域。资料失败显示“账号：未获取”，头像缺失沿用默认头像，不使用游戏资料中的旧头像。

新增用户行应复用 SangongPublicAccount、SangongUserName 和 SangongIMAvatar；不要将内部 ID 拼接到标题、确认提示或搜索提示。业务提交继续传原有内部 ID，公开账号搜索仍通过现有 account_identity 解析。
