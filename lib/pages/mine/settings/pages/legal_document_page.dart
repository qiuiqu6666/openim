import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

enum LegalDocumentKind { terms, privacy }

enum _LegalLocale { zhHans, zhHant, en, ja, ko }

class LegalDocumentPage extends StatelessWidget {
  const LegalDocumentPage({
    super.key,
    required this.kind,
  });

  final LegalDocumentKind kind;

  _LegalLocale _locale(BuildContext context) {
    final locale = Localizations.localeOf(context);
    switch (locale.languageCode.toLowerCase()) {
      case 'zh':
        final script = locale.scriptCode?.toLowerCase();
        final country = locale.countryCode?.toUpperCase();
        if (script == 'hant' || country == 'TW' || country == 'HK' || country == 'MO') {
          return _LegalLocale.zhHant;
        }
        return _LegalLocale.zhHans;
      case 'ja':
        return _LegalLocale.ja;
      case 'ko':
        return _LegalLocale.ko;
      case 'en':
      default:
        return _LegalLocale.en;
    }
  }

  String _title(_LegalLocale locale) {
    if (kind == LegalDocumentKind.terms) {
      return switch (locale) {
        _LegalLocale.zhHans => '服务条款',
        _LegalLocale.zhHant => '服務條款',
        _LegalLocale.en => 'Terms of Service',
        _LegalLocale.ja => '利用規約',
        _LegalLocale.ko => '서비스 이용약관',
      };
    }
    return switch (locale) {
      _LegalLocale.zhHans => '隐私政策',
      _LegalLocale.zhHant => '隱私政策',
      _LegalLocale.en => 'Privacy Policy',
      _LegalLocale.ja => 'プライバシーポリシー',
      _LegalLocale.ko => '개인정보 처리방침',
    };
  }

  String _body(_LegalLocale locale) {
    if (kind == LegalDocumentKind.terms) {
      return switch (locale) {
        _LegalLocale.zhHans => _termsZhHans,
        _LegalLocale.zhHant => _termsZhHant,
        _LegalLocale.en => _termsEn,
        _LegalLocale.ja => _termsJa,
        _LegalLocale.ko => _termsKo,
      };
    }
    return switch (locale) {
      _LegalLocale.zhHans => _privacyZhHans,
      _LegalLocale.zhHant => _privacyZhHant,
      _LegalLocale.en => _privacyEn,
      _LegalLocale.ja => _privacyJa,
      _LegalLocale.ko => _privacyKo,
    };
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final locale = _locale(context);
    final pageColor = AppTokens.background(dark: dark);
    final appBarColor = AppTokens.surface(dark: dark);
    return Scaffold(
      backgroundColor: pageColor,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        backgroundColor: appBarColor,
        surfaceTintColor: Colors.transparent,
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                color: AppTokens.accent,
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        title: Text(
          _title(locale),
          style: TextStyle(
            color: AppTokens.textPrimary(dark: dark),
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: SelectableText(
            _body(locale).trim(),
            key: const ValueKey('settings-legal-document-body'),
            style: TextStyle(
              color: AppTokens.textPrimary(dark: dark),
              fontSize: 16,
              height: 1.85,
            ),
          ),
        ),
      ),
    );
  }
}

const String _termsZhHans = '''
99Chat 服务条款

生效日期：2026 年 5 月 24 日

欢迎您使用 99Chat（“99Chat”、“我们”）应用、网站及相关服务（统称“服务”）。当您访问或使用本服务时，即表示您同意接受本《服务条款》（以下简称“条款”）的约束。

1. 资格要求

您必须年满 18 周岁，或达到您所在司法辖区规定的法定成年年龄，方可使用本服务。

2. 账号注册

您有责任妥善保管您的账号凭证，并对您账号下发生的全部活动承担责任。

3. 合理使用

您同意不会：

- 违反任何适用法律法规
- 骚扰、辱骂、威胁或冒充他人
- 上传恶意软件或有害内容
- 从事欺诈、垃圾信息传播或其他非法活动
- 未经授权分发受版权保护的内容

4. 用户内容

用户对其提交的内容保留所有权。通过本服务发布内容时，您授予 99Chat 一项全球范围内、非独占、免版税的许可，以便仅为运营和改进服务之目的使用、展示和分发相关内容。

5. 隐私

您对本服务的使用还受到《隐私政策》的约束。

6. 知识产权

所有商标、标识、品牌、软件和平台内容均归 99Chat 或其许可方所有。

7. 订阅与支付

部分功能可能需要付费或订阅。除法律另有规定外，所有付款均不予退款。

8. 终止

如果您违反本条款，99Chat 有权随时暂停或终止您对服务的访问权限。

9. 免责声明

本服务按“现状”和“可用”状态提供，不附带任何形式的保证。

10. 责任限制

对于因您使用本服务而产生的任何间接、附带、特殊或后果性损害，99Chat 不承担责任。

11. 条款变更

我们可能会不时更新本条款。在条款更新后继续使用服务，即视为您接受修订后的内容。

12. 联系方式

如对本条款有任何疑问，请联系：

support@99chat.app
''';

const String _termsZhHant = '''
99Chat 服務條款

生效日期：2026 年 5 月 24 日

歡迎您使用 99Chat（「99Chat」、「我們」）應用、網站及相關服務（統稱「服務」）。當您存取或使用本服務時，即表示您同意接受本《服務條款》（以下簡稱「條款」）的約束。

1. 資格要求

您必須年滿 18 歲，或達到您所在司法轄區規定的法定成年年齡，方可使用本服務。

2. 帳號註冊

您有責任妥善保管您的帳號憑證，並對您帳號下發生的全部活動承擔責任。

3. 合理使用

您同意不會：

- 違反任何適用法律法規
- 騷擾、辱罵、威脅或冒充他人
- 上傳惡意軟體或有害內容
- 從事詐欺、垃圾訊息傳播或其他非法活動
- 未經授權分發受版權保護的內容

4. 用戶內容

用戶對其提交的內容保留所有權。通過本服務發布內容時，您授予 99Chat 一項全球範圍內、非獨占、免版稅的授權，以便僅為營運和改進服務之目的使用、展示和分發相關內容。

5. 隱私

您對本服務的使用還受到《隱私政策》的約束。

6. 知識產權

所有商標、標誌、品牌、軟體和平台內容均歸 99Chat 或其授權方所有。

7. 訂閱與支付

部分功能可能需要付費或訂閱。除法律另有規定外，所有付款均不予退款。

8. 終止

如果您違反本條款，99Chat 有權隨時暫停或終止您對服務的使用權限。

9. 免責聲明

本服務按「現狀」和「可用」狀態提供，不附帶任何形式的保證。

10. 責任限制

對於因您使用本服務而產生的任何間接、附帶、特殊或後果性損害，99Chat 不承擔責任。

11. 條款變更

我們可能會不時更新本條款。在條款更新後繼續使用服務，即視為您接受修訂後的內容。

12. 聯絡方式

如對本條款有任何疑問，請聯絡：

support@99chat.app
''';

const String _termsEn = '''
99Chat Terms of Service

Effective Date: May 24, 2026

Welcome to 99Chat (“99Chat”, “we”, “our”, or “us”). By accessing or using the 99Chat application, website, or related services (collectively, the “Service”), you agree to be bound by these Terms of Service (“Terms”).

1. Eligibility

You must be at least 18 years old or the legal age of majority in your jurisdiction to use the Service.

2. Account Registration

You are responsible for maintaining the confidentiality of your account credentials and for all activities under your account.

3. Acceptable Use

You agree not to:

- Violate any applicable laws or regulations
- Harass, abuse, threaten, or impersonate others
- Upload malicious software or harmful content
- Engage in fraud, spam, or illegal activities
- Use the Service to distribute copyrighted material without authorization

4. User Content

Users retain ownership of content they submit. By posting content through the Service, you grant 99Chat a worldwide, non-exclusive, royalty-free license to use, display, and distribute such content solely for operating and improving the Service.

5. Privacy

Your use of the Service is also governed by our Privacy Policy.

6. Intellectual Property

All trademarks, logos, branding, software, and platform content are owned by 99Chat or its licensors.

7. Subscription and Payments

Certain features may require payment or subscription. All payments are non-refundable unless required by law.

8. Termination

We may suspend or terminate your access to the Service at any time if you violate these Terms.

9. Disclaimer

The Service is provided “AS IS” and “AS AVAILABLE” without warranties of any kind.

10. Limitation of Liability

99Chat shall not be liable for indirect, incidental, special, or consequential damages arising from your use of the Service.

11. Changes to Terms

We may update these Terms periodically. Continued use of the Service after updates constitutes acceptance of the revised Terms.

12. Contact

For questions regarding these Terms, contact:

support@99chat.app
''';

const String _termsJa = '''
99Chat 利用規約

施行日：2026年5月24日

99Chat（以下「99Chat」または「当社」）のアプリ、ウェブサイト、および関連サービス（以下総称して「本サービス」）をご利用いただきありがとうございます。本サービスにアクセスまたは利用することにより、お客様は本利用規約（以下「本規約」）に拘束されることに同意したものとみなされます。

1. 利用資格

本サービスを利用するには、18歳以上であるか、またはお住まいの地域で法的に成人と認められる年齢に達している必要があります。

2. アカウント登録

お客様は、ご自身のアカウント認証情報を適切に管理し、当該アカウントの下で行われるすべての行為について責任を負うものとします。

3. 適正な利用

お客様は、以下の行為を行わないことに同意します。

- 適用される法令または規制に違反すること
- 他者への嫌がらせ、侮辱、脅迫、またはなりすまし
- 悪意のあるソフトウェアや有害なコンテンツのアップロード
- 詐欺、スパム送信、その他の違法行為
- 著作権で保護されたコンテンツを無断で配布すること

4. ユーザーコンテンツ

ユーザーは、自ら投稿したコンテンツの権利を保持します。本サービスを通じてコンテンツを投稿することにより、お客様は、サービスの運営および改善に必要な範囲で、当該コンテンツを使用、表示、配布するための、全世界対象、非独占的、無償のライセンスを 99Chat に付与するものとします。

5. プライバシー

本サービスの利用には、当社のプライバシーポリシーも適用されます。

6. 知的財産権

すべての商標、ロゴ、ブランド、ソフトウェア、およびプラットフォーム上のコンテンツは、99Chat またはそのライセンサーに帰属します。

7. サブスクリプションおよび支払い

一部の機能は、有料またはサブスクリプション契約が必要となる場合があります。法令で別段の定めがある場合を除き、支払い済みの料金は返金されません。

8. 利用停止および終了

お客様が本規約に違反した場合、99Chat はいつでも本サービスへのアクセスを停止または終了することができます。

9. 免責事項

本サービスは「現状有姿」かつ「提供可能な範囲」で提供され、いかなる種類の保証も伴いません。

10. 責任の制限

お客様による本サービスの利用に起因して発生する間接損害、付随的損害、特別損害、または結果的損害について、99Chat は責任を負いません。

11. 規約の変更

当社は、本規約を随時更新する場合があります。更新後も本サービスを継続して利用することにより、改定後の規約に同意したものとみなされます。

12. お問い合わせ

本規約に関するご質問は、以下までお問い合わせください。

support@99chat.app
''';

const String _termsKo = '''
99Chat 서비스 이용약관

시행일: 2026년 5월 24일

99Chat(이하 “99Chat” 또는 “당사”)의 애플리케이션, 웹사이트 및 관련 서비스(총칭하여 “서비스”)를 이용해 주셔서 감사합니다. 이용자가 본 서비스에 접속하거나 이를 이용하는 경우, 본 서비스 이용약관(이하 “약관”)에 동의한 것으로 간주됩니다.

1. 이용 자격

본 서비스를 이용하려면 만 18세 이상이거나, 이용자의 거주 지역에서 법적으로 성인으로 인정되는 연령에 도달해야 합니다.

2. 계정 등록

이용자는 자신의 계정 인증 정보를 안전하게 관리할 책임이 있으며, 해당 계정으로 이루어지는 모든 활동에 대해 책임을 집니다.

3. 적정 이용

이용자는 다음 행위를 해서는 안 됩니다.

- 적용되는 법률 또는 규정을 위반하는 행위
- 타인에 대한 괴롭힘, 모욕, 협박 또는 사칭
- 악성 소프트웨어 또는 유해한 콘텐츠 업로드
- 사기, 스팸 발송 또는 기타 불법 행위
- 저작권으로 보호되는 콘텐츠를 무단으로 배포하는 행위

4. 사용자 콘텐츠

이용자는 자신이 제출한 콘텐츠에 대한 권리를 보유합니다. 이용자가 서비스를 통해 콘텐츠를 게시하는 경우, 99Chat은 서비스 운영 및 개선을 위해 필요한 범위 내에서 해당 콘텐츠를 사용, 표시 및 배포할 수 있는 전 세계적이고 비독점적이며 무상인 라이선스를 부여받습니다.

5. 개인정보

본 서비스 이용에는 당사의 개인정보 처리방침도 함께 적용됩니다.

6. 지식재산권

모든 상표, 로고, 브랜드, 소프트웨어 및 플랫폼 내 콘텐츠의 권리는 99Chat 또는 그 라이선스 제공자에게 귀속됩니다.

7. 구독 및 결제

일부 기능은 유료 결제 또는 구독이 필요할 수 있습니다. 법령상 요구되는 경우를 제외하고, 결제된 금액은 환불되지 않습니다.

8. 이용 제한 및 종료

이용자가 본 약관을 위반하는 경우, 99Chat은 언제든지 서비스 이용을 제한하거나 종료할 수 있습니다.

9. 면책조항

본 서비스는 “있는 그대로” 그리고 “제공 가능한 범위 내에서” 제공되며, 어떠한 형태의 보증도 제공하지 않습니다.

10. 책임의 제한

99Chat은 이용자의 서비스 이용으로 인해 발생하는 간접손해, 부수적 손해, 특별손해 또는 결과적 손해에 대해 책임을 지지 않습니다.

11. 약관 변경

당사는 필요에 따라 본 약관을 수시로 변경할 수 있습니다. 변경 후에도 서비스를 계속 이용하는 경우, 개정된 약관에 동의한 것으로 간주됩니다.

12. 문의처

본 약관과 관련하여 문의가 있는 경우 아래로 연락해 주세요.

support@99chat.app
''';

const String _privacyZhHans = '''
99Chat 隐私政策

生效日期：2026 年 5 月 24 日

99Chat（“我们”）尊重您的隐私，并致力于保护您的个人信息安全。

1. 我们收集的信息

我们可能会收集以下信息：

- 姓名与个人资料信息
- 邮箱地址和手机号码
- 设备信息与 IP 地址
- 使用数据与应用分析数据
- 消息内容与您上传的资料
- 支付信息（由第三方支付服务商安全处理）

2. 信息的使用方式

我们收集信息用于：

- 提供和维护服务
- 提升用户体验
- 防止欺诈和滥用
- 处理支付事务
- 发送更新和通知
- 履行法律义务

3. 信息共享

我们不会出售您的个人信息。我们可能会与以下主体共享信息：

- 服务提供商和基础设施合作伙伴
- 支付处理机构
- 法律法规要求的有关机关

4. 数据保存期限

我们仅在业务、法律和安全目的所必需的期限内保留用户信息。

5. 安全措施

我们采取行业通行的安全措施保护用户信息，但任何系统都无法保证绝对安全。

6. 跨境传输

您的信息可能会在您所在司法辖区之外的国家或地区被处理和存储。

7. 未成年人隐私

99Chat 不面向 18 周岁以下用户提供服务。

8. 您的权利

依据您所在地区的法律，您可能享有以下权利：

- 访问您的数据
- 更正不准确的数据
- 请求删除数据
- 撤回授权同意

9. Cookies 与分析工具

我们可能会使用 Cookies、分析工具及类似技术来改进服务体验。

10. 政策更新

我们可能会不定期更新本隐私政策。

11. 联系我们

如您有与隐私相关的问题，请联系：

privacy@99chat.app
''';

const String _privacyZhHant = '''
99Chat 隱私政策

生效日期：2026 年 5 月 24 日

99Chat（「我們」）尊重您的隱私，並致力於保護您的個人資訊安全。

1. 我們收集的資訊

我們可能會收集以下資訊：

- 姓名與個人資料資訊
- 電子郵件地址和手機號碼
- 裝置資訊與 IP 位址
- 使用資料與應用分析資料
- 訊息內容與您上傳的資料
- 支付資訊（由第三方支付服務商安全處理）

2. 資訊的使用方式

我們收集資訊用於：

- 提供和維護服務
- 提升用戶體驗
- 防止詐騙和濫用
- 處理支付事務
- 發送更新和通知
- 履行法律義務

3. 資訊共享

我們不會出售您的個人資訊。我們可能會與以下主體共享資訊：

- 服務提供商和基礎設施合作夥伴
- 支付處理機構
- 法律法規要求的有關機關

4. 資料保存期限

我們僅在業務、法律和安全目的所必需的期限內保留用戶資訊。

5. 安全措施

我們採取業界通行的安全措施保護用戶資訊，但任何系統都無法保證絕對安全。

6. 跨境傳輸

您的資訊可能會在您所在司法轄區之外的國家或地區被處理和儲存。

7. 未成年人隱私

99Chat 不面向 18 歲以下用戶提供服務。

8. 您的權利

依據您所在地區的法律，您可能享有以下權利：

- 存取您的資料
- 更正不準確的資料
- 請求刪除資料
- 撤回授權同意

9. Cookies 與分析工具

我們可能會使用 Cookies、分析工具及類似技術來改進服務體驗。

10. 政策更新

我們可能會不定期更新本隱私政策。

11. 聯絡我們

如您有與隱私相關的問題，請聯絡：

privacy@99chat.app
''';

const String _privacyEn = '''
99Chat Privacy Policy

Effective Date: May 24, 2026

99Chat (“we”, “our”, or “us”) respects your privacy and is committed to protecting your personal information.

1. Information We Collect

We may collect:

- Name and profile information
- Email address and phone number
- Device information and IP address
- Usage data and app analytics
- Messages and uploaded content
- Payment information (processed securely by third-party providers)

2. How We Use Information

We use collected information to:

- Provide and maintain the Service
- Improve user experience
- Prevent fraud and abuse
- Process payments
- Communicate updates and notifications
- Comply with legal obligations

3. Data Sharing

We do not sell your personal information. We may share information with:

- Service providers and infrastructure partners
- Payment processors
- Legal authorities when required by law

4. Data Retention

We retain user information only as long as necessary for business, legal, and security purposes.

5. Security

We implement industry-standard security measures to protect user information, but no system can guarantee absolute security.

6. International Transfers

Your information may be processed and stored in countries outside your jurisdiction.

7. Children’s Privacy

99Chat is not intended for users under 18 years of age.

8. Your Rights

Depending on your jurisdiction, you may have rights to:

- Access your data
- Correct inaccurate data
- Request deletion
- Withdraw consent

9. Cookies and Analytics

We may use cookies, analytics tools, and similar technologies to improve the Service.

10. Changes to This Policy

We may update this Privacy Policy periodically.

11. Contact Us

For privacy-related inquiries:

privacy@99chat.app
''';

const String _privacyJa = '''
99Chat プライバシーポリシー

施行日：2026年5月24日

99Chat（以下「当社」）は、お客様のプライバシーを尊重し、個人情報の保護に努めます。

1. 収集する情報

当社は、以下の情報を収集する場合があります。

- 氏名およびプロフィール情報
- メールアドレスおよび電話番号
- 端末情報および IP アドレス
- 利用状況データおよびアプリ分析データ
- メッセージ内容およびアップロードされたコンテンツ
- 決済情報（第三者決済事業者により安全に処理されます）

2. 情報の利用目的

収集した情報は、以下の目的で利用します。

- サービスの提供および維持
- ユーザー体験の向上
- 不正行為および不適切な利用の防止
- 決済処理
- 更新情報および通知の送信
- 法令上の義務への対応

3. 情報の共有

当社は、お客様の個人情報を販売しません。以下の場合に限り、情報を共有することがあります。

- サービス提供事業者およびインフラパートナー
- 決済処理事業者
- 法令に基づき開示が必要な公的機関

4. 保存期間

当社は、業務、法令遵守、および安全管理の目的で必要な期間に限り、ユーザー情報を保持します。

5. 安全管理

当社は、業界標準の安全対策を講じてユーザー情報を保護します。ただし、いかなるシステムも完全な安全性を保証するものではありません。

6. 国際的なデータ移転

お客様の情報は、お客様の居住国または地域以外の国で処理・保存される場合があります。

7. 未成年者のプライバシー

99Chat は、18歳未満の方を対象としたサービスではありません。

8. お客様の権利

お住まいの地域の法令に基づき、お客様は以下の権利を有する場合があります。

- ご自身のデータへのアクセス
- 不正確なデータの訂正
- データ削除の請求
- 同意の撤回

9. Cookie および分析ツール

当社は、サービス品質向上のために、Cookie、分析ツール、その他これに類する技術を利用する場合があります。

10. ポリシーの更新

当社は、本ポリシーを随時更新する場合があります。

11. お問い合わせ

プライバシーに関するお問い合わせは、以下までご連絡ください。

privacy@99chat.app
''';

const String _privacyKo = '''
99Chat 개인정보 처리방침

시행일: 2026년 5월 24일

99Chat(이하 “당사”)는 이용자의 개인정보를 존중하며, 개인정보 보호를 위해 최선을 다합니다.

1. 수집하는 정보

당사는 다음과 같은 정보를 수집할 수 있습니다.

- 이름 및 프로필 정보
- 이메일 주소 및 휴대전화 번호
- 기기 정보 및 IP 주소
- 이용 기록 및 앱 분석 데이터
- 메시지 내용 및 업로드한 콘텐츠
- 결제 정보(제3자 결제 서비스 제공업체가 안전하게 처리함)

2. 정보 이용 목적

수집한 정보는 다음 목적을 위해 사용됩니다.

- 서비스 제공 및 운영 유지
- 사용자 경험 개선
- 사기 및 부정 이용 방지
- 결제 처리
- 업데이트 및 알림 제공
- 법적 의무 이행

3. 정보 공유

당사는 이용자의 개인정보를 판매하지 않습니다. 다만, 다음 경우에 한하여 정보를 공유할 수 있습니다.

- 서비스 제공업체 및 인프라 파트너
- 결제 처리업체
- 법령에 따라 제공이 요구되는 관계 기관

4. 보관 기간

당사는 업무상 필요, 법적 의무, 보안 목적을 위해 필요한 기간 동안에만 이용자 정보를 보관합니다.

5. 보안

당사는 업계 표준 수준의 보안 조치를 적용하여 이용자 정보를 보호합니다. 다만, 어떠한 시스템도 절대적인 안전을 보장할 수는 없습니다.

6. 국외 이전

이용자의 정보는 이용자가 거주하는 국가 또는 지역 외부에서 처리되거나 저장될 수 있습니다.

7. 아동의 개인정보

99Chat은 만 18세 미만 이용자를 대상으로 하는 서비스가 아닙니다.

8. 이용자의 권리

이용자가 거주하는 지역의 법령에 따라 다음과 같은 권리를 가질 수 있습니다.

- 본인 데이터 열람
- 부정확한 데이터 정정
- 데이터 삭제 요청
- 동의 철회

9. 쿠키 및 분석 도구

당사는 서비스 개선을 위해 쿠키, 분석 도구 및 유사한 기술을 사용할 수 있습니다.

10. 정책 변경

당사는 본 개인정보 처리방침을 수시로 업데이트할 수 있습니다.

11. 문의하기

개인정보와 관련한 문의는 아래로 연락해 주세요.

privacy@99chat.app
''';
