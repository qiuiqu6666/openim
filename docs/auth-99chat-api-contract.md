# 99chat 认证页面与 OpenIM 接口对照

本次移植参考 `E:/openim/reference-99chat` 的登录、注册和找回密码页面。界面沿用参考布局，认证请求仍使用当前 OpenIM 后端。两套接口路径、手机号格式、密码提交方式和登录凭证结构不同，不能直接互换。

## 当前服务地址

| 服务 | 地址 |
| --- | --- |
| Chat API | `http://129.226.192.93:10008` |
| OpenIM API | `http://129.226.192.93:10002` |
| OpenIM WebSocket | `ws://129.226.192.93:10001` |

这些是默认配置；已有用户保存的服务器配置仍由现有配置流程读取。

## 已有参数可以支持的流程

| 行为 | 99chat 参考请求 | 当前 OpenIM 请求与适配 |
| --- | --- | --- |
| 密码登录 | `POST /auth/login/password`：`account`、原始 `password`、`phoneCountry`、`deviceId`、`deviceModel` | `POST /account/login`：前导 `@` 标记用户 ID，去除前导 `@` 后使用 `account`；其余符合手机号格式的数字使用 `phoneNumber + areaCode`，中间含 `@` 的输入先校验邮箱格式并使用 `email`，其他输入使用 `account`。密码仍按现协议提交 MD5。已有 `deviceID`、`deviceName`、`version`、`platform`。 |
| 短信登录 | `POST /auth/login/sms`：`phone`、`smsCode`、`phoneCountry`、设备字段 | `POST /account/login`：`phoneNumber`、`areaCode`、`verifyCode`、设备字段、`platform`。页面为手机号短信登录。 |
| 发送验证码 | `POST /sms/send`：国际格式 `phone`、`scene`、可选 `phoneCountry` / `challengeId` | `POST /account/code/send`：拆分的 `phoneNumber + areaCode`，`usedFor` 为注册 `1`、重置密码 `2`、登录 `3`；按当前流程提交 `invitationCode`、`captchaVerifyParam`。 |
| 注册 | `POST /auth/register`：`phone`、`smsCode`、`nickname`、原始 `password`、`phoneCountry`、设备字段、可选 `avatarUrl` | `POST /account/register`：`verifyCode`、设备字段、`platform`、`autoLogin`、可选 `invitationCode`；`user` 中提供 `phoneNumber`、`areaCode`、`nickname`、MD5 `password` 等现有字段。第一步填写账号、验证码、密码及确认密码，验证码校验成功后进入第二步填写昵称并选择头像，点击完成注册后创建账号。头像选填，选图时显示真实本地预览。 |
| 验证验证码 | 参考流程在登录、注册或重置接口内验证 | 当前注册和找回密码先调用 `POST /account/code/verify`：`phoneNumber`、`areaCode`、`verifyCode`、`usedFor`、可选 `invitationCode`，再提交对应认证请求；短信登录直接提交 `/account/login`。 |
| 找回密码 | `POST /auth/password/reset`：`phone`、`smsCode`、原始 `password`、可选 `phoneCountry`；返回 `TokenResult` | `POST /account/password/reset`：`phoneNumber`、`areaCode`、`verifyCode`、MD5 `password`、`platform`。当前完成后返回登录页；单次重置是否返回可直接登录的 OpenIM 凭证，仍需服务端确认。 |

`phoneCountry` 是参考客户端的国家 ISO 代码；当前协议已有拨号区号 `areaCode`，没有已确认需要额外提交 ISO 代码的依据。当前登录需要 `userID`、`chatToken`、`imToken`；参考的 `token / userId / expiresIn` 不能直接用于 OpenIM SDK。

HTTP 200 仍须检查响应 JSON 的 `errCode`。发送验证码还须检查 `captchaVerifyResult == true` 且 `bizResult == true`；`errCode == 0` 本身不表示短信已成功发送。现有错误提示沿用应用当前语言映射。

## 客户端能力与服务端待确认项

| 参考行为 | 当前状态 | 如需完全一致，需确认的契约 |
| --- | --- | --- |
| 注册前检查昵称是否可用 | 参考调用未登录的 `GET /nicknames/available?nickname=...`。当前已有 `POST /user/nickname/check`，使用现有 Chat token 配置；注册前可用性尚未确认，页面现只检查昵称长度并提交注册。 | 未登录昵称检查的路径、方法、权限与响应，例如 `available` 或 `occupied`、`reason`。不能把已登录昵称修改接口直接视为注册检查接口。 |
| 自定义拼图滑块验证 | 参考使用 `/auth/slider/init` 和 `/auth/slider/verify`；当前使用阿里云人机验证，并将 `captchaVerifyParam` 交给发送验证码接口。当前客户端没有参考滑块协议适配。 | 初始化的图像、`token`、宽高、缺口坐标等字段；验证请求 `token/x/y`、通过结果与验证码发送关联方式。服务端是否支持这些接口尚未确认。 |
| 密码登录后的短信二次验证 | 参考使用 `NEED_SMS/challengeId`。当前服务端新协议为 `/account/login` 返回业务错误 `20081`，无票据或手机号；客户端进入设备验证页，以登录用途 `3` 发送手机号验证码，再提交原密码请求加 `verifyCode`。完整 OpenIM 凭据才进入既有登录流程。账号／邮箱入口补填绑定手机号。 | 已按用户提供的新协议接入，维护说明见 [设备二次验证模块](../lib/pages/login/device_verification/README.md)。服务端源码已实现、尚未部署；新错误码和真实短信须部署后联调。 |
| 重置密码后自动进入首页 | 参考重置返回 token 并完成 IM 初始化。当前重置返回类型尚无已确认 OpenIM 凭证契约。 | 重置是否返回 `userID/chatToken/imToken`，或是否允许重置后额外进行密码登录。当前保留成功后返回登录页。 |
| 多个节点与故障切换 | 参考目录包含其业务 API 与 TCP 服务。当前指定了一个 Chat/OpenIM 节点组合。 | 若增加节点，每个节点都需要可用的 Chat API、OpenIM HTTP、OpenIM WebSocket 三个地址；不能用参考仓库的 TCP 地址替代 OpenIM WebSocket。 |
| 参考的五种语言 | 参考提供简体中文、繁体中文、英文、日文、韩文。当前认证文案与业务错误映射使用应用已有中文/英文语言资源。 | 这是客户端语言资源差异，不需要新增认证请求参数。 |

第二步支持选填头像。选择后，在注册并完成 SDK 登录后使用现有 OpenIM 文件上传和资料更新接口提交头像；注册响应缺少 Chat/IM token 时，用刚注册的账号及首次密码请求现有 `/account/login`，确认返回同一用户的完整凭据后继续 SDK 登录和头像上传。上传失败会保留第二步、显示“重试上传头像”，可以重新选图后继续；重试不会重复创建账号或再次完成 SDK 登录。账号创建后锁定昵称、密码及上一步入口，避免修改已提交资料或回到第一步再次注册。未选头像时使用后端默认头像。

“记住密码”、确认密码、密码可见状态与协议勾选属于客户端状态，参考请求也没有相应服务端字段。本次记住密码使用 `flutter_secure_storage`；只在 SDK 登录成功后保存，关闭时删除已保存密码，异步恢复不覆盖用户输入。回填期间仅账号、密码、验证码文本、区号或登录方式的实际变化视为编辑；光标选择和输入法组合状态通知不会取消回填。同一手机号的短信登录保留已记住密码，切换账号会清理；重置成功仅更新同一已记住手机号的密码。密码不会写入 `DataSp` 明文配置。

## 核对来源

- 当前接口：[Apis](../openim_common/lib/src/apis.dart)、[Urls](../openim_common/lib/src/urls.dart)、[LoginLogic](../lib/pages/login/login_logic.dart)、[安全凭据存储](../lib/services/auth_credentials/auth_credentials_store.dart)。
- 参考仓库：`lib/src/api/auth_api.dart`、`lib/src/api/user_api.dart`、`lib/src/pages/login.dart`、`lib/src/pages/forgot_password.dart`、`lib/src/security/slider_captcha.dart`、`lib/src/services/login_coordinator.dart`、`lib/src/services/login_credential_store.dart`、`lib/src/services/api_node_service.dart`、`lib/src/i18n/auth_localizations.dart`。

以上是客户端源码对照；没有发送真实注册、短信或密码重置请求，也没有据此认定待确认接口在服务端不存在。
