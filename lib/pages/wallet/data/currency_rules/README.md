# 钱包币种规则

`WalletFundApi.fetchDepositAddress()` 保持已有 Chat token、operationID 和 GET 路径，从响应 `data.currencyRules` 解析实际生效配置。规则按 USDT/TRX 分币种，充值地址仍取 `data.address`；不持久化规则配置，也不使用示例值补数据。

`wallet_currency_rule.dart` 验证八项规则字段。金额为非负十进制字符串，按币种精度解析；秒数和确认门槛为非负整数，Memo/Tag 要求为布尔值。缺失或 null 保留未知，明确零有效。已提供的非法字段或不匹配的手续费币种拒绝解析，规则集合不可变。

`wallet_withdrawal_policy.dart` 使用 BigInt 最小单位计算最低提现、本金加手续费及余额减手续费，手续费必须和提现币种一致。仅新提交使用当前规则；原交易查询和冻结参数不因配置更新而改变。确认页最终费用以提现收据为准。

语言及展示组件独立放在 `../../widgets/currency_rules/`；纯数据模型不依赖 Flutter 页面。针对解析、真实传输返回、精度及配置刷新场景的测试位于 `test/pages/wallet/data/currency_rules/`。
