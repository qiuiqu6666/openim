# 当前节点与测速

节点地址复用 core/server_nodes 的 NodeEndpoint：生产环境显示域名节点01和直连节点02，自定义服务器只显示自身。选中标记代表当前连接，页面不公开底层地址。启动检测结果只用于首次手动测速前展示。

用户手动测速时，并行请求每个候选节点 Chat API 的 GET /chat/platform，各自使用独立的无账号凭据客户端。开始后清除旧结果，每行独立显示测速中、成功耗时或异常，所有请求结束后记录完成时间。仅有效成功响应判定正常；该结果仅代表 Chat 服务响应耗时，不代表下载带宽或完整 IM 可用性。手动测速不修改登录或 SDK 配置。

重复点击共用进行中的请求；离开前台或销毁页面取消请求，节点配置变化后忽略旧结果。界面复用设置页组件与亮暗主题颜色。

对照 reference-99chat/lib/src/pages/settings/node_switch_page.dart 的所有节点测速、逐行反馈与节点点击行为，复用设置页组件，没有新增重复页面组件。点击未选中的节点会通过 core/server_nodes/ManualNodeSwitchRuntime 显式立即切换，自动测速仍不改变连接。每次冷启动仍按原策略重新选路。

手动切换先无凭据检查目标节点三项服务，成功后复用 IMController 的退出、初始化、登录链路，同时更新 Chat、IM API、WebSocket 和共享 HTTP 地址；保留账号凭据，不清空消息数据库。等待实际连接成功后才更新勾选标记；失败时尝试恢复旧节点，恢复失败明确提示检查网络并重启。全局协调器防重复切换，通话中拒绝切换，预检期间离开前台或关闭页面取消操作，账号改变后不恢复旧账号。重新初始化不广播启动事件，避免重复触发启动页自动登录。

验证：test/node_probe_controller_test.dart 覆盖双节点请求、独立完成、重复点击、失败覆盖旧结果、配置变化及前后台取消；test/pages/mine/settings/node_switch/node_switch_layout_test.dart 覆盖亮暗主题、窄屏/横屏、大字号与真实点击事件；test/core/server_nodes/manual_node_switch* 覆盖切换成功、预检失败、回退、账号替换和 SDK 调用顺序。SDK 调用使用测试通道，不能代替真机连接验收。
