enum LegalDocumentType { terms, privacy }

class LegalSection {
  const LegalSection({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;
}

class LegalDocument {
  const LegalDocument({
    required this.title,
    required this.effectiveDate,
    required this.introduction,
    required this.sections,
  });

  final String title;
  final String effectiveDate;
  final String introduction;
  final List<LegalSection> sections;
}

const legalConsentVersion = '2026-09-01';

LegalDocument legalDocumentFor(LegalDocumentType type, {required bool english}) {
  return switch ((type, english)) {
    (LegalDocumentType.terms, false) => _termsZh,
    (LegalDocumentType.terms, true) => _termsEn,
    (LegalDocumentType.privacy, false) => _privacyZh,
    (LegalDocumentType.privacy, true) => _privacyEn,
  };
}

const _termsZh = LegalDocument(
  title: '用户协议',
  effectiveDate: '生效日期：2026年9月1日',
  introduction:
      '欢迎使用哨兵VPN（SentinelVPN）。本协议是您与哨兵VPN运营团队之间关于下载、安装、注册、登录和使用本客户端及相关服务的约定。请在使用前完整阅读并理解本协议，尤其是责任限制、服务中止和争议处理条款。点击“同意并继续”、注册、登录或实际使用服务，即表示您已阅读并同意本协议。',
  sections: [
    LegalSection(
      title: '一、服务内容',
      body:
          '哨兵VPN提供网络连接管理、代理配置、订阅管理、账户管理、套餐购买、设备管理、通知及相关技术服务。具体功能、可用地区、速度、节点和服务期限以客户端及服务端实际提供为准。我们可根据运营、安全、合规或技术需要调整服务，并将在合理范围内提示重要变化。',
    ),
    LegalSection(
      title: '二、账户与安全',
      body:
          '您应提供真实、准确、有效的注册信息，并妥善保管账户、密码、验证码和订阅信息。您对账户下发生的活动负责。发现账户被盗用或存在安全风险时，请立即通过客户端内客服联系我们。未经允许，不得出售、出租、转让、共享账户或规避设备数量等限制。',
    ),
    LegalSection(
      title: '三、使用规则',
      body:
          '您应遵守所在地适用的法律法规，不得利用本服务侵害他人权益、攻击网络系统、传播恶意程序、实施欺诈、干扰服务、绕过安全限制，或从事任何违法违规活动。您应自行确认使用网络代理或相关功能在所在地是否合法。对于涉嫌违法、滥用或危害服务安全的行为，我们可采取限制功能、暂停或终止账户等措施。',
    ),
    LegalSection(
      title: '四、付费、续费与退款',
      body:
          '套餐价格、期限、流量、设备限制及优惠以购买页面为准。支付由所选第三方支付渠道处理，其规则亦适用。除法律另有规定、购买页面另有说明或服务存在经确认的重大缺陷外，数字化网络服务在开通或使用后通常不支持退款。请在付款前核对账户、套餐和金额。',
    ),
    LegalSection(
      title: '五、知识产权',
      body:
          '客户端中的商标、界面、文本、图形和自有代码归相应权利人所有。客户端包含的开源软件分别受其开源许可证约束。未经授权，您不得复制、出售、出租、反向利用自有服务，或删除权利声明；适用法律或开源许可证明确允许的情形除外。',
    ),
    LegalSection(
      title: '六、服务变更与中止',
      body:
          '因维护、升级、网络故障、第三方服务异常、不可抗力、安全事件或合规要求，服务可能暂时中断。我们将尽合理努力恢复服务，但不保证服务始终连续、无错误或满足所有特定用途。对于重大永久性变更，我们会通过客户端公告或其他合理方式通知。',
    ),
    LegalSection(
      title: '七、责任限制',
      body:
          '在法律允许的最大范围内，我们不对因网络波动、第三方服务、设备环境、用户配置、不可抗力或用户违法违规使用造成的间接损失、数据丢失或预期利益损失负责。任何条款均不排除法律规定不得排除或限制的责任。您应自行备份重要配置并采取合理的账户与设备安全措施。',
    ),
    LegalSection(
      title: '八、未成年人',
      body:
          '本服务主要面向成年人。未满十八周岁的用户应在监护人阅读并同意本协议后使用；未满十四周岁的儿童请勿自行注册或使用服务。若监护人发现儿童未经同意提供了个人信息，请联系我们处理。',
    ),
    LegalSection(
      title: '九、协议更新与终止',
      body:
          '我们可能因法律、业务或功能变化更新本协议。发生重大变化时，客户端会再次征求您的同意。您可停止使用并卸载客户端以终止本协议；账户注销、余额和已购服务的处理依适用法律及服务规则执行。',
    ),
    LegalSection(
      title: '十、法律适用与联系',
      body:
          '本协议适用服务运营者所在地的法律，但不影响您依据所在地强制性消费者保护规则享有的权利。发生争议时，双方应先友好协商。您可通过客户端内“在线客服”或“关于”页面提供的联系渠道联系我们。',
    ),
  ],
);

const _termsEn = LegalDocument(
  title: 'Terms of Service',
  effectiveDate: 'Effective date: September 1, 2026',
  introduction:
      'Welcome to SentinelVPN. These Terms form an agreement between you and the SentinelVPN operating team regarding your download, installation, registration, sign-in, and use of this client and related services. Please read them carefully, especially the sections on limitations of liability, suspension, and disputes. By selecting “Agree and Continue,” registering, signing in, or using the service, you acknowledge and accept these Terms.',
  sections: [
    LegalSection(
      title: '1. Services',
      body:
          'SentinelVPN provides network connection management, proxy configuration, subscription management, account management, plan purchases, device management, notices, and related technical services. Features, availability, speed, nodes, and service periods are subject to what is actually provided in the client and by the service. We may adjust the service for operational, security, compliance, or technical reasons and will provide reasonable notice of material changes.',
    ),
    LegalSection(
      title: '2. Accounts and security',
      body:
          'You must provide accurate and valid registration information and protect your account, password, verification codes, and subscription details. You are responsible for activity under your account. Contact in-app support promptly if you suspect unauthorized use. You may not sell, rent, transfer, or share an account, or evade device limits, without permission.',
    ),
    LegalSection(
      title: '3. Acceptable use',
      body:
          'You must comply with applicable laws where you use the service. You may not use it to violate rights, attack systems, distribute malware, commit fraud, disrupt the service, bypass security controls, or engage in unlawful activity. You are responsible for confirming whether proxy-related functions are lawful in your location. We may restrict, suspend, or terminate use associated with illegality, abuse, or security threats.',
    ),
    LegalSection(
      title: '4. Payments and refunds',
      body:
          'Plan prices, periods, traffic allowances, device limits, and promotions are shown at purchase. Payments are processed by the selected third-party payment provider and its terms also apply. Unless required by law, stated otherwise at purchase, or a confirmed material service defect exists, digital network services are generally non-refundable after activation or use. Verify the account, plan, and amount before paying.',
    ),
    LegalSection(
      title: '5. Intellectual property',
      body:
          'Trademarks, interfaces, text, graphics, and proprietary code belong to their respective owners. Open-source components remain governed by their licenses. Except where applicable law or an open-source license permits, you may not copy, sell, rent, commercially exploit proprietary services, or remove rights notices without authorization.',
    ),
    LegalSection(
      title: '6. Changes and interruptions',
      body:
          'Maintenance, upgrades, network failures, third-party outages, force majeure, security incidents, or compliance requirements may interrupt the service. We will make reasonable efforts to restore it, but do not guarantee uninterrupted, error-free operation or fitness for every particular purpose. We will give reasonable notice of material permanent changes.',
    ),
    LegalSection(
      title: '7. Limitation of liability',
      body:
          'To the maximum extent permitted by law, we are not liable for indirect loss, data loss, or lost expectations caused by network conditions, third parties, device environments, user configuration, force majeure, or unlawful use. Nothing excludes liability that cannot legally be excluded. You should back up important configurations and maintain reasonable account and device security.',
    ),
    LegalSection(
      title: '8. Minors',
      body:
          'The service is primarily intended for adults. Users under 18 should use it only after a guardian has reviewed and accepted these Terms. Children under 14 must not register or use the service on their own. Guardians may contact us if a child has supplied personal information without consent.',
    ),
    LegalSection(
      title: '9. Updates and termination',
      body:
          'We may update these Terms to reflect legal, business, or functional changes. We will request consent again for material updates. You may terminate by stopping use and uninstalling the client. Account closure, balances, and purchased services are handled under applicable law and service rules.',
    ),
    LegalSection(
      title: '10. Governing law and contact',
      body:
          'These Terms are governed by the law where the service operator is established, without limiting mandatory consumer rights in your location. The parties should first attempt to resolve disputes amicably. Contact us through in-app support or the channels listed on the About page.',
    ),
  ],
);

const _privacyZh = LegalDocument(
  title: '隐私政策',
  effectiveDate: '生效日期：2026年9月1日',
  introduction:
      '哨兵VPN重视您的个人信息和隐私。本政策说明我们在您使用客户端、账户、订阅、支付和网络连接服务时如何收集、使用、存储、共享和保护信息，以及您如何行使相关权利。协议正文直接内置于客户端，您可随时在“关于”页面查看。',
  sections: [
    LegalSection(
      title: '一、我们收集的信息',
      body:
          '1. 账户信息：邮箱、验证码、邀请码、账户标识和登录状态。密码用于身份验证；当您启用记住密码时，凭据可能保存在设备本地安全或应用存储中。\n2. 订阅与交易信息：套餐、订单号、金额、支付状态、余额、流量和有效期。完整银行卡或支付账户凭据通常由第三方支付机构处理。\n3. 设备与诊断信息：设备型号、操作系统、应用版本、设备标识、语言、时区、IP地址、网络状态、崩溃及运行日志。\n4. 服务使用信息：登录时间、节点或配置选择、连接状态、上传和下载流量统计、设备在线状态及必要的安全事件。\n5. 客服信息：您主动提交的文字、截图、联系方式和问题记录。',
    ),
    LegalSection(
      title: '二、网络流量说明',
      body:
          '客户端需要创建本地 VPN 或代理连接以实现您选择的网络功能，因此设备网络流量可能经过您所选节点或服务提供方。我们不以出售广告画像为目的检查您的通信内容。为提供连接、排障和防止滥用，服务端可能处理连接所必需的源 IP、时间、节点、流量用量及错误信息。第三方节点和您访问的网站可能依据其各自政策处理数据。',
    ),
    LegalSection(
      title: '三、使用目的与依据',
      body:
          '我们为创建和管理账户、提供连接与订阅、完成交易、同步设备、发送服务通知、提供客服、诊断故障、防止欺诈和攻击、遵守法律义务而处理信息。处理依据包括履行您请求的服务、取得您的同意、履行法律义务，以及在不损害您合法权益前提下保障服务安全和改进产品的合理需要。',
    ),
    LegalSection(
      title: '四、设备权限',
      body:
          '根据平台和您使用的功能，客户端可能请求 VPN 配置、网络状态、通知、相机或相册、文件存储、开机启动等权限。相机仅在您主动扫码时使用；文件权限用于导入、导出或备份配置；通知用于显示连接和服务状态。您可在系统设置中管理权限，但关闭必要权限可能导致相关功能不可用。',
    ),
    LegalSection(
      title: '五、本地存储',
      body:
          '客户端会在设备本地保存应用设置、配置文件、缓存、登录状态、协议同意版本和您选择保存的账户凭据。卸载应用通常会删除应用私有目录中的数据，但导出的文件、系统备份或平台同步的数据可能继续存在。请妥善保护设备和导出的配置文件。',
    ),
    LegalSection(
      title: '六、共享与第三方服务',
      body:
          '我们不会出售您的个人信息。仅在提供服务所必要、获得您的授权或法律要求时，信息可能提供给云基础设施、节点、支付、消息推送、客服、邮件、统计或安全服务商。这些服务商只能按约定目的处理必要信息。您主动打开的外部网站、支付页面或第三方服务适用其自身隐私政策。',
    ),
    LegalSection(
      title: '七、跨境处理',
      body:
          '由于网络节点、云服务或技术提供方可能位于不同国家或地区，信息可能在您所在地区以外处理。我们会依据适用法律采取合同、访问控制、加密或其他合理保护措施。若适用法律要求单独同意或其他手续，我们将另行履行。',
    ),
    LegalSection(
      title: '八、保存期限与安全',
      body:
          '我们仅在实现本政策目的、履行合同、解决争议和满足法律要求所需期间保留信息，之后删除或匿名化。我们采用传输加密、访问控制、最小权限和日志审计等合理措施，但互联网和电子存储不存在绝对安全。发生可能影响您权益的安全事件时，我们将依法律要求通知并采取补救措施。',
    ),
    LegalSection(
      title: '九、您的权利',
      body:
          '在适用法律范围内，您可请求访问、更正、复制、删除个人信息，撤回同意、限制或反对处理，并申请注销账户。撤回同意不影响此前处理的合法性；删除必要信息后部分服务可能无法继续。您可通过客户端内客服提出请求，我们可能为保护账户安全而验证您的身份。',
    ),
    LegalSection(
      title: '十、未成年人信息',
      body:
          '我们不会故意收集未满十四周岁儿童的个人信息。未成年人应在监护人指导下使用服务。若发现儿童未经监护人同意提交了个人信息，请通过客户端内客服联系我们，我们会依法核实并处理。',
    ),
    LegalSection(
      title: '十一、政策更新与联系',
      body:
          '我们可能因法律或服务变化更新本政策。重大更新会在客户端显著提示并重新征求同意。对本政策或个人信息处理有疑问、投诉或权利请求，请通过客户端内“在线客服”或“关于”页面列出的联系渠道联系我们。',
    ),
  ],
);

const _privacyEn = LegalDocument(
  title: 'Privacy Policy',
  effectiveDate: 'Effective date: September 1, 2026',
  introduction:
      'SentinelVPN respects your personal information and privacy. This Policy explains how information is collected, used, stored, shared, and protected when you use the client, account, subscription, payment, and network connection services, and how you can exercise your rights. The complete text is built into the client and remains available from the About page.',
  sections: [
    LegalSection(
      title: '1. Information we collect',
      body:
          '1. Account data: email address, verification code, invitation code, account identifier, and sign-in state. Passwords are used for authentication; if you enable password remembering, credentials may be stored in secure or application storage on your device.\n2. Subscription and transaction data: plan, order number, amount, payment status, balance, traffic usage, and expiry. Full card or payment-account credentials are generally handled by the payment provider.\n3. Device and diagnostics: device model, operating system, app version, device identifier, language, time zone, IP address, network state, crashes, and operational logs.\n4. Service usage: sign-in time, node or configuration selections, connection status, upload and download totals, device online state, and necessary security events.\n5. Support data: text, screenshots, contact details, and issue records you choose to submit.',
    ),
    LegalSection(
      title: '2. Network traffic',
      body:
          'The client creates a local VPN or proxy connection to provide the network function you select, so device traffic may pass through your chosen node or service provider. We do not inspect communication content to sell advertising profiles. To provide connectivity, troubleshoot, and prevent abuse, servers may process the source IP, time, node, traffic volume, and errors necessary for the connection. Third-party nodes and websites you visit may process data under their own policies.',
    ),
    LegalSection(
      title: '3. Purposes and legal bases',
      body:
          'We process information to create and manage accounts, provide connections and subscriptions, complete transactions, synchronize devices, send service notices, provide support, diagnose faults, prevent fraud and attacks, and meet legal obligations. Legal bases may include performing the requested service, your consent, legal obligations, and legitimate needs to secure and improve the service where your rights are not overridden.',
    ),
    LegalSection(
      title: '4. Device permissions',
      body:
          'Depending on platform and feature, the client may request VPN configuration, network state, notifications, camera or photo access, file storage, or startup permissions. Camera access is used only when you scan a code; file access supports configuration import, export, or backup; notifications show connection and service status. You can manage permissions in system settings, but disabling necessary permissions may prevent related features.',
    ),
    LegalSection(
      title: '5. Local storage',
      body:
          'The client stores settings, configuration files, caches, sign-in state, the accepted legal version, and credentials you elect to save on the device. Uninstalling normally removes data in private application storage, but exported files, system backups, or platform-synchronized data may remain. Protect your device and exported configurations.',
    ),
    LegalSection(
      title: '6. Sharing and third parties',
      body:
          'We do not sell personal information. Information may be provided to cloud infrastructure, network nodes, payment, push notification, support, email, analytics, or security providers only where needed to provide the service, with your authorization, or as required by law. Providers may process only information necessary for the agreed purpose. External websites, payment pages, and third-party services you open apply their own privacy policies.',
    ),
    LegalSection(
      title: '7. International processing',
      body:
          'Network nodes, cloud services, or technology providers may operate in other countries or regions, so information may be processed outside your location. We use reasonable contractual, access-control, encryption, or other safeguards under applicable law. Where separate consent or other formalities are required, we will complete them separately.',
    ),
    LegalSection(
      title: '8. Retention and security',
      body:
          'We retain information only as long as needed for the purposes in this Policy, contract performance, disputes, and legal requirements, then delete or anonymize it. We use reasonable measures such as encryption in transit, access controls, least privilege, and audit logs, but no internet or electronic storage system is absolutely secure. We will provide legally required notice and remediation for security incidents that may affect your rights.',
    ),
    LegalSection(
      title: '9. Your rights',
      body:
          'Subject to applicable law, you may request access, correction, a copy, or deletion of personal information; withdraw consent; restrict or object to processing; and request account closure. Withdrawal does not affect prior lawful processing, and deleting necessary data may make some services unavailable. Submit requests through in-app support; we may verify identity to protect the account.',
    ),
    LegalSection(
      title: '10. Children',
      body:
          'We do not knowingly collect personal information from children under 14. Minors should use the service with guardian guidance. If you believe a child submitted information without guardian consent, contact in-app support and we will verify and handle it as required by law.',
    ),
    LegalSection(
      title: '11. Updates and contact',
      body:
          'We may update this Policy for legal or service changes. Material updates will be prominently presented in the client and consent requested again. For questions, complaints, or privacy-rights requests, contact us through in-app support or the channels listed on the About page.',
    ),
  ],
);