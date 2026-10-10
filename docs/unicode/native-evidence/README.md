# Android 原生 Unicode 验证证据

执行日期：2026-10-08。设备为 `emulator-5554`，Android 9 / API 28；Flutter 3.41.6。
独立测试包 `dev.codex.unicode_native_probe` 使用当前公共输入与显示组件。
没有初始化 OpenIM、登录、发送消息或读取产品数据库，也没有安装覆盖主应用。

21 类结构样本各运行日间和夜间主题，共 42 组。
[样本清单](batch-cases.json) 与 [逐组原文检查](batch-sequence-checks.jsonl) 保存实际结果。
每组的 8 项检查及 `seedUnchanged` 均为 true：实际输入渲染文本、系统 Text、
TextView、MatchTextView、匹配回调、Markdown 显示、Markdown 原文和 JSON 往返。
批次完成，并生成 42 张探针自身的截图；这里保留已人工检查的 6 张代表截图。

| 截图 | 人工观察 |
| --- | --- |
| [VS16 箭头](light-1.png) | 输入、系统参考与项目显示组件均显示完整箭头。 |
| [家庭 ZWJ](dark-5.png) | 多码点家庭显示为连接的家庭图案，没有分离的 ZWJ。 |
| [肤色职业](light-8.png) | 肤色和职业组合显示为连接图案。 |
| [Tag 旗帜](dark-12.png) | 旗帜组合显示完整。 |
| [中文/Latin/结合符/ZWJ 混排](light-17.png) | 原文、结合符和组合图案完整，高亮未拆开字符。 |
| [系统尚不支持的补充平面值](dark-20.png) | 系统 Text 和全部项目控件均出现缺字框，原文检查仍通过。 |

截图来自探针自身 RepaintBoundary；透明区域不代表产品的主题背景。
Markdown 刻意加 A/Z 包装与粗体，以区分 Markdown 语法和用户原始内容。
没有逐张人工确认全部 42 张截图的字形，自动检查也不识别字形图案。

这证明上述原生渲染树保留原文及代表性样本的系统字体显示；不证明系统包含所有
Unicode 字形，不证明实际 Gboard/其他软键盘、系统剪贴板、原生 SDK SQLite、
远端服务或物理设备已验证。Android **尚未真机验证**，iOS **尚未真机验证**。
未来新增字符的原文无需 Emoji 白名单；新的字形与分词规则可能需要更新系统、
Flutter/engine 和 Unicode 基础库。
