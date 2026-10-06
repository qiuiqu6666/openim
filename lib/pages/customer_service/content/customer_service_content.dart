// Adapted from 99chat's customer_service_static_page.dart (Apache-2.0).
// Answers are updated for this OpenIM client's supported product behavior.
import 'package:flutter/widgets.dart';

String customerServiceText(BuildContext context,
        {required String zh, required String en}) =>
    Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

/// Static product help, separate from live-agent messages and server state.
class CustomerServiceQuestion {
  const CustomerServiceQuestion({
    required this.id,
    required this.zhLabel,
    required this.enLabel,
    required this.zhAnswer,
    required this.enAnswer,
  });

  final String id;
  final String zhLabel;
  final String enLabel;
  final String zhAnswer;
  final String enAnswer;

  bool get isOfficialWebsite => id == 'faq_official';

  String label(BuildContext context) =>
      customerServiceText(context, zh: zhLabel, en: enLabel);

  String answer(BuildContext context, {String officialURL = ''}) {
    if (isOfficialWebsite && officialURL.trim().isEmpty) {
      return customerServiceText(context,
          zh: '官方网站也可在「我的」-「设置」-「关于我们」中查看。当前尚未获取到链接，请稍后再试，或在下方咨询人工客服。',
          en: 'The official website is also in Me > Settings > About Us. The link is not available yet. Try again later or ask the agent below.');
    }
    return customerServiceText(context, zh: zhAnswer, en: enAnswer);
  }
}

class CustomerServiceCategory {
  const CustomerServiceCategory({
    required this.id,
    required this.zhTitle,
    required this.enTitle,
    required this.questions,
  });

  final String id;
  final String zhTitle;
  final String enTitle;
  final List<CustomerServiceQuestion> questions;

  String title(BuildContext context) =>
      customerServiceText(context, zh: zhTitle, en: enTitle);
}

// Category/question IDs and their order follow 99chat's native support page.
// Answers describe this client's current entry points instead of promising
// unsupported wallet tabs, IM-ID search, or video Moments.
const customerServiceCategories = <CustomerServiceCategory>[
  CustomerServiceCategory(
    id: 'faq',
    zhTitle: '常见问题',
    enTitle: 'FAQ',
    questions: [
      CustomerServiceQuestion(
        id: 'faq_official',
        zhLabel: '官方网站',
        enLabel: 'Official website',
        zhAnswer: '以下链接来自平台的官方网站配置，点击即可打开。也可在「我的」-「设置」-「关于我们」中查看官方网站和当前版本。',
        enAnswer:
            'The link below comes from the platform’s official website configuration. Tap it to open. You can also find the website and current version in Me > Settings > About Us.',
      ),
      CustomerServiceQuestion(
        id: 'faq_notify',
        zhLabel: '收不到新消息通知',
        enLabel: 'No new message alerts',
        zhAnswer:
            '先在系统设置中允许 99chat 发送通知，再打开「我的」-「消息通知」检查通知设置。安卓设备还需允许后台运行，并检查电池优化是否限制应用。若只收不到某个聊天的通知，请检查该聊天是否开启了消息免打扰。',
        enAnswer:
            'Allow 99chat notifications in system settings, then check Me > Notifications. On Android, also allow background activity and check battery optimization. If only one chat has no alerts, check whether that chat is muted.',
      ),
      CustomerServiceQuestion(
        id: 'faq_send',
        zhLabel: '消息发不出去',
        enLabel: 'Cannot send messages',
        zhAnswer:
            '确认网络正常且已登录。失败消息旁出现感叹号时，可点击重发。也请检查拉黑状态和群内禁言设置。持续失败时切换网络后重试，并把提示原文和发生时间发给下方人工客服。',
        enAnswer:
            'Check your connection and sign-in status. Tap the exclamation mark next to a failed message to resend. Also check blocking and group mute settings. If it keeps failing, try another network and send the exact error and time to the agent below.',
      ),
      CustomerServiceQuestion(
        id: 'faq_media',
        zhLabel: '图片或视频发送失败',
        enLabel: 'Photo or video failed',
        zhAnswer:
            '检查相册或相机权限，以及网络连接。聊天中可通过加号选择图片或视频；失败时点击感叹号重试。如果文件过大或格式不支持，可尝试较小的文件，并向客服提供提示内容。',
        enAnswer:
            'Check Photos or Camera permission and your connection. Use the plus button in chat to choose media, and tap the exclamation mark to retry. For a large or unsupported file, try a smaller one and share the error text with support.',
      ),
      CustomerServiceQuestion(
        id: 'faq_network',
        zhLabel: '提示网络异常',
        enLabel: 'Network error',
        zhAnswer:
            '尝试切换 Wi-Fi 和移动网络，并检查网络是否能正常访问。若使用代理或 VPN，可检查其连接状态后重试。仍无法连接时，请将当前时间和错误提示发给下方人工客服。',
        enAnswer:
            'Try switching between Wi-Fi and mobile data and check that the connection works. If you use a proxy or VPN, check its connection too. If the problem remains, send the time and exact error to the agent below.',
      ),
    ],
  ),
  CustomerServiceCategory(
    id: 'about',
    zhTitle: 'APP简介',
    enTitle: 'About App',
    questions: [
      CustomerServiceQuestion(
        id: 'about_what',
        zhLabel: '99chat 是什么',
        enLabel: 'What is 99chat',
        zhAnswer:
            '99chat 是即时通讯应用，提供单聊、群聊、通讯录、朋友圈及音视频通话。聊天中的红包和转账等功能以当前账号实际开放的服务为准。',
        enAnswer:
            '99chat is a messenger with direct chats, groups, contacts, Moments, and voice/video calls. Services such as red packets and transfers depend on what is available to your account.',
      ),
      CustomerServiceQuestion(
        id: 'about_features',
        zhLabel: '主要功能有哪些',
        enLabel: 'Main features',
        zhAnswer:
            '底部可进入单聊、群聊、通讯录和我的。聊天支持文字、图片、视频、语音、文件及自定义表情。「我的」提供收藏、通话记录、消息通知和设置。当前版本可在「设置」-「关于我们」中查看。',
        enAnswer:
            'The bottom tabs open direct chats, groups, contacts, and Me. Chat supports text, photos, video, voice, files, and custom stickers. Me includes Favorites, call history, notifications, and settings. See Settings > About Us for the current version.',
      ),
      CustomerServiceQuestion(
        id: 'about_moments',
        zhLabel: '朋友圈怎么用',
        enLabel: 'Moments',
        zhAnswer:
            '可从「我的」或个人资料进入朋友圈，浏览动态或发布图文。发布失败时检查网络和相册权限；可在朋友圈权限中调整可见范围。支持的内容类型以发布页面为准。',
        enAnswer:
            'Open Moments from Me or a profile to browse posts or share text and photos. Check your connection and Photos permission if posting fails. Adjust visibility in Moments privacy settings. The publishing page shows supported content types.',
      ),
      CustomerServiceQuestion(
        id: 'about_call',
        zhLabel: '语音视频通话',
        enLabel: 'Voice & video calls',
        zhAnswer:
            '可从聊天或联系人资料中的通话入口发起语音、视频通话。语音需要麦克风权限，视频还需相机权限。连接失败时检查双方网络和权限，并确认对方当前可以接听。',
        enAnswer:
            'Use the call actions in a chat or contact profile to start a voice or video call. Voice needs microphone permission; video also needs camera access. If a call fails, check both connections, permissions, and the other person’s availability.',
      ),
    ],
  ),
  CustomerServiceCategory(
    id: 'security',
    zhTitle: '安全中心',
    enTitle: 'Security',
    questions: [
      CustomerServiceQuestion(
        id: 'security_pin',
        zhLabel: '忘记支付密码',
        enLabel: 'Forgot payment PIN',
        zhAnswer:
            '到「我的」-「设置」-「账号安全」查看支付密码设置，按页面要求完成验证和重置。支付密码用于资金操作，不要将密码或验证码告诉任何人，客服也不会向你索取。',
        enAnswer:
            'Open Me > Settings > Account Security and check the payment PIN settings. Follow the verification and reset steps shown there. Never share your PIN or verification codes; support will not ask for them.',
      ),
      CustomerServiceQuestion(
        id: 'security_devices',
        zhLabel: '发现陌生登录设备',
        enLabel: 'Unknown login device',
        zhAnswer:
            '在「我的」-「设置」-「账号安全」-「登录设备」查看设备记录。发现陌生设备时，退出该设备并修改登录密码。若无法操作，请把提示信息发给客服，不要提供密码或验证码。',
        enAnswer:
            'Check Me > Settings > Account Security > Login Devices. Remove an unfamiliar device and change your login password. If you cannot do so, share the error with support without sending passwords or verification codes.',
      ),
      CustomerServiceQuestion(
        id: 'security_password',
        zhLabel: '修改登录密码',
        enLabel: 'Change login password',
        zhAnswer:
            '在「我的」-「设置」-「账号安全」中修改登录密码，按页面要求完成验证。修改后使用新密码登录。建议使用独立的登录密码，不要与支付密码相同。',
        enAnswer:
            'Change your login password in Me > Settings > Account Security and complete the verification shown there. Use the new password afterward. Keep your login password separate from your payment PIN.',
      ),
      CustomerServiceQuestion(
        id: 'security_phone',
        zhLabel: '换绑手机号',
        enLabel: 'Change phone number',
        zhAnswer:
            '在「我的」-「设置」-「账号安全」中绑定或更换手机号，按页面流程验证旧号码和新号码。无法收到验证码时，检查号码、区号、信号及短信拦截；旧号码已停用可向客服说明情况。',
        enAnswer:
            'Bind or change your number in Me > Settings > Account Security, following the old/new number verification steps. If codes do not arrive, check the number, country code, signal, and SMS filtering. Contact support if your old number is no longer available.',
      ),
    ],
  ),
  CustomerServiceCategory(
    id: 'cash',
    zhTitle: '充值提现',
    enTitle: 'Deposit & Withdraw',
    questions: [
      CustomerServiceQuestion(
        id: 'cash_deposit_time',
        zhLabel: '充值多久到账',
        enLabel: 'When does a deposit arrive',
        zhAnswer:
            '到账时间和可用渠道以当前充值页面或订单提示为准。若已有付款但状态未更新，请向客服提供订单编号、金额和付款时间。没有显示充值入口时，可先咨询客服当前是否开放。',
        enAnswer:
            'Arrival times and channels depend on the deposit page or order information. If you paid but the status has not updated, send the order ID, amount, and payment time to support. If no deposit entry is shown, ask whether the service is available.',
      ),
      CustomerServiceQuestion(
        id: 'cash_withdraw_missing',
        zhLabel: '提现未到账',
        enLabel: 'Withdrawal not received',
        zhAnswer:
            '先查看提现订单的实际状态和收款信息。若超过订单提示的处理时间仍未到账，请提供订单编号、金额和申请时间给客服核查。不要重复提交相同提现，也不要发送支付密码或验证码。',
        enAnswer:
            'Check the withdrawal order status and receiving details. If the time shown on the order has passed, give support the order ID, amount, and request time. Avoid submitting the same withdrawal again and do not send your PIN or codes.',
      ),
      CustomerServiceQuestion(
        id: 'cash_redpacket',
        zhLabel: '红包发不出或领不了',
        enLabel: 'Red packet failed',
        zhAnswer:
            '检查网络、余额和支付密码，并查看红包页面的提示。领取时确认红包是否已领完、过期或不符合领取条件。持续失败时，向客服提供相关订单编号或提示截图。',
        enAnswer:
            'Check your connection, balance, payment PIN, and the error on the red packet page. When claiming, check whether the packet has expired, been fully claimed, or has eligibility conditions. Share the order ID or error screenshot with support if needed.',
      ),
      CustomerServiceQuestion(
        id: 'cash_transfer',
        zhLabel: '转账失败',
        enLabel: 'Transfer failed',
        zhAnswer:
            '确认收款人、金额、余额和支付密码，并查看转账页面或订单详情的提示。结果不明确时先查询订单，不要重复付款。可向客服提供订单编号和错误信息，请勿发送密码或验证码。',
        enAnswer:
            'Check the recipient, amount, balance, PIN, and order/error details. If the result is unclear, check the order before paying again. Give support the order ID and error without sharing passwords or codes.',
      ),
    ],
  ),
  CustomerServiceCategory(
    id: 'social',
    zhTitle: '好友与群',
    enTitle: 'Friends & Groups',
    questions: [
      CustomerServiceQuestion(
        id: 'social_friend',
        zhLabel: '加好友失败',
        enLabel: 'Cannot add friend',
        zhAnswer:
            '请使用对方的公开账号、手机号、邮箱，或二维码、名片、群成员资料等实际入口添加。搜索不支持按 IM 号或昵称找人。对方关闭某种添加方式、开启群保护或邀请码过期时，申请可能被拒绝；请核对信息或让对方通过允许的方式邀请你。',
        enAnswer:
            'Use the person’s public account, phone, email, or an available QR code, contact card, or group profile. Search does not find people by IM ID or nickname. Disabled add methods, group protection, or an expired invite may block a request. Check the details or ask for an allowed invitation.',
      ),
      CustomerServiceQuestion(
        id: 'social_create',
        zhLabel: '如何创建群聊',
        enLabel: 'Create a group',
        zhAnswer:
            '在会话页点击右上角加号，选择发起群聊并选择联系人，按页面提示创建。群名称、公告和成员管理可在群资料或群设置中调整，操作权限取决于你的群角色。',
        enAnswer:
            'Tap the plus button on the conversations page, choose to start a group, select contacts, and follow the prompts. Group profiles/settings contain the name, announcements, and member actions available to your role.',
      ),
      CustomerServiceQuestion(
        id: 'social_join',
        zhLabel: '进群失败或被踢',
        enLabel: 'Cannot join / kicked',
        zhAnswer:
            '检查群号或邀请入口是否有效，以及该群是否需要管理员审核。被移出后是否能重新加入由群规则决定，可联系群主或管理员核实。向客服反馈时请提供群号和提示原文。',
        enAnswer:
            'Check that the group ID or invitation is valid and whether approval is required. Rejoining after removal depends on the group rules; ask the owner or an administrator. Include the group ID and exact error when contacting support.',
      ),
      CustomerServiceQuestion(
        id: 'social_mute',
        zhLabel: '群消息太多太吵',
        enLabel: 'Too many group alerts',
        zhAnswer:
            '进入群设置开启消息免打扰，或按需调整消息通知。消息免打扰只影响提醒，不会退出群聊。仍可进入会话查看消息，也可根据页面提供的选项整理会话。',
        enAnswer:
            'Enable Do Not Disturb in group settings or adjust notifications. Muting alerts does not leave the group. You can still open the conversation to read messages and organize chats using the available options.',
      ),
    ],
  ),
  CustomerServiceCategory(
    id: 'auth',
    zhTitle: '注册登录',
    enTitle: 'Sign in',
    questions: [
      CustomerServiceQuestion(
        id: 'auth_register',
        zhLabel: '如何注册',
        enLabel: 'How to sign up',
        zhAnswer:
            '在登录页选择注册，按页面流程填写信息并完成验证。使用本人可接收验证码的号码或邮箱，妥善保管登录密码，验证码不要转发给任何人。',
        enAnswer:
            'Choose Register on the sign-in page, enter your details, and complete the verification. Use a phone number or email you control, keep your password safe, and never forward verification codes.',
      ),
      CustomerServiceQuestion(
        id: 'auth_forgot',
        zhLabel: '忘记登录密码',
        enLabel: 'Forgot login password',
        zhAnswer:
            '在登录页选择找回密码，使用已绑定的手机号或邮箱，按页面要求验证后重置。如果已无法使用绑定的号码或邮箱，请在下方说明情况，由客服告知核实流程。',
        enAnswer:
            'Choose password recovery on the sign-in page and verify with the linked phone number or email. If you cannot access it anymore, describe the situation below so support can explain the verification process.',
      ),
      CustomerServiceQuestion(
        id: 'auth_code',
        zhLabel: '收不到验证码',
        enLabel: 'No verification code',
        zhAnswer:
            '核对手机号、区号或邮箱地址，检查信号、短信拦截和垃圾邮件。倒计时结束后再尝试获取，短时间频繁请求可能受到限制。请勿把验证码发给他人，包括客服。',
        enAnswer:
            'Check your number, country code, or email, along with signal, SMS filtering, and spam folders. Wait for the countdown before trying again; frequent requests may be limited. Never send the code to anyone, including support.',
      ),
      CustomerServiceQuestion(
        id: 'auth_disable',
        zhLabel: '账号被限制或无法登录',
        enLabel: 'Account restricted',
        zhAnswer:
            '保存登录时的提示原文和发生时间，并向下方人工客服说明情况。客服会按实际账号状态告知后续处理流程。不要向陌生人转账，也不要提供登录密码、支付密码或验证码。',
        enAnswer:
            'Save the exact sign-in error and time and describe the issue to the agent below. Support will explain the next steps based on the actual account status. Do not transfer money to strangers or share passwords, PINs, or codes.',
      ),
    ],
  ),
  CustomerServiceCategory(
    id: 'life',
    zhTitle: '生活缴费',
    enTitle: 'Utilities',
    questions: [
      CustomerServiceQuestion(
        id: 'life_entry',
        zhLabel: '生活缴费入口在哪',
        enLabel: 'Where is Utilities',
        zhAnswer: '可在「我的」的热门生态区域查看生活缴费入口。可办理项目和是否开放以入口实际显示为准；若提示暂未开放，可向下方客服咨询。',
        enAnswer:
            'Look for Utilities in the featured services on Me. Available services depend on what the entry actually shows. If it is not open yet, ask the agent below.',
      ),
      CustomerServiceQuestion(
        id: 'life_fail',
        zhLabel: '缴费失败',
        enLabel: 'Payment failed',
        zhAnswer:
            '若已进入缴费服务，检查缴费项目、户号、金额及页面提示。扣款后结果不明确时，请先查询订单，不要重复缴费。联系该服务或下方客服时提供订单编号和提示截图。',
        enAnswer:
            'If the payment service is available, check the service, account number, amount, and error. If money was deducted but the result is unclear, check the order before paying again. Send the order ID and error screenshot to the service or agent below.',
      ),
      CustomerServiceQuestion(
        id: 'life_record',
        zhLabel: '缴费记录在哪看',
        enLabel: 'Payment history',
        zhAnswer:
            '缴费记录以实际办理服务中的订单或记录入口为准。如无法找到已完成的订单，请提供办理项目、时间和订单编号，向该服务或下方客服核实。',
        enAnswer:
            'Use the orders/history entry in the service where you made the payment. If a completed order is missing, give the service or agent its type, time, and order ID.',
      ),
      CustomerServiceQuestion(
        id: 'life_balance',
        zhLabel: '余额不足怎么缴',
        enLabel: 'Not enough balance',
        zhAnswer:
            '先检查实际缴费页面支持的付款方式和可用余额，按该服务提示操作。没有可用付款方式或余额状态异常时，请咨询客服；不要通过陌生链接充值或付款。',
        enAnswer:
            'Check the supported payment methods and available balance on the actual payment page, then follow its instructions. Ask support if no method is available or the balance is incorrect. Do not pay through unknown links.',
      ),
    ],
  ),
  CustomerServiceCategory(
    id: 'other',
    zhTitle: '其他',
    enTitle: 'Other',
    questions: [
      CustomerServiceQuestion(
        id: 'other_profile',
        zhLabel: '修改昵称和头像',
        enLabel: 'Change name and avatar',
        zhAnswer:
            '点击「我的」顶部头像或资料区域进入个人资料，可修改头像、昵称和个性签名。上传头像失败时检查相册权限和网络，昵称不符合要求时按页面提示调整。',
        enAnswer:
            'Tap your profile at the top of Me to change your avatar, name, or signature. Check Photos permission and your connection if an avatar upload fails. Follow the on-screen requirements if a name is rejected.',
      ),
      CustomerServiceQuestion(
        id: 'other_report',
        zhLabel: '投诉与举报',
        enLabel: 'Report abuse',
        zhAnswer:
            '在下方说明发生时间、相关公开账号或群号、问题经过，并提供必要截图。涉及账号安全时请先保护账号。不要在投诉内容中发送密码、支付密码或验证码。',
        enAnswer:
            'Describe the time, public account or group ID, and what happened below, with relevant screenshots. Protect your account first if security is involved. Do not include passwords, payment PINs, or verification codes.',
      ),
      CustomerServiceQuestion(
        id: 'other_feedback',
        zhLabel: '意见与建议',
        enLabel: 'Feedback',
        zhAnswer:
            '可在「我的」-「设置」-「意见反馈」提交建议或问题，也可在下方留言。请说明使用场景、预期结果和实际结果，必要时附上截图，方便核查。',
        enAnswer:
            'Use Me > Settings > Feedback or leave a message below. Explain what you were doing, what you expected, and what actually happened. Add screenshots if they help.',
      ),
      CustomerServiceQuestion(
        id: 'other_human',
        zhLabel: '联系人工客服',
        enLabel: 'Talk to an agent',
        zhAnswer:
            '在下方输入问题即可联系人工客服。可发送文字或页面支持的附件；客服连接和发送结果以页面提示为准。请保留有用的提示信息，客服不会索取密码或验证码。',
        enAnswer:
            'Type your question below to contact an agent. You can send text and supported attachments; check the page for connection and sending status. Keep useful error details and never share passwords or verification codes.',
      ),
    ],
  ),
];
