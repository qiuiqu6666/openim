# 联系人搜索数据源

`ContactSearchSource` 保留现有 Chat 用户查询、好友搜索接口和 SDK 群 ID 查询。新增好友页面与联系人选择搜索共用此数据源；好友/用户 HTTP 请求捕获 token，但不自行清凭据、导航或显示错误。

控制器负责关键词与请求代次、页码提交、账号/token 变化和关闭保护。当前 owner 的认证失效通过 `core/session/session_request_errors.dart` 补充现有 HttpUtil 机制；过期结果与过期异常均丢弃。群选择仍调用 SDK 名称/ID 搜索，显示好友与群两部分结果。

对应测试位于 `test/pages/contacts/add_by_search` 和 `test/pages/contacts/select_contacts/search_contacts`。
