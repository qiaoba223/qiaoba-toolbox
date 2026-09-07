import 'dart:convert';

import 'package:http/http.dart' as http;

/// 顺丰登录助手 — 网关与加密常量
///
/// 协议来源：顺丰官方 App v9.95.2 抓包 + ccas-h5.sf-express.com 官方 H5 改密流程
/// 说明：登录/改密的风控参数（riskStr / riskInfo）由顺丰原生 App 桥生成，
///       纯客户端无法计算，因此本模块仅承载 H5 官方页面的接口常量与辅助能力，
///       真实登录与改密在 App 内 WebView 中由官方页面完成（真实风控环境）。
class SfGateway {
  /// H5 Passport 页面（改密 / 账号安全）
  static const String h5Base = 'https://ccas-h5.sf-express.com';

  /// 忘记密码入口页（官方 H5，含极验与风控桥）
  static const String forgotEntry = '$h5Base/help';

  /// 登录入口页
  static const String loginEntry = '$h5Base/login';

  /// 账号安全页
  static const String securityEntry = '$h5Base/security-guard';

  /// 接口网关
  static const String apiBase = '$h5Base/ccas-app-apis/m3-pp-gw';

  /// App 端会员网关
  static const String memberBase =
      'https://ccsp-egmas.sf-express.com/cx-app-member/member/app';

  /// AppId（抓包取得）
  static const String prodAppId = '202606171442282067';
  static const String sitAppId = '202606051810133637';

  /// 生产环境 RSA-2048 公钥（PKCS#1 v1.5）
  /// 来源：ccas-h5.sf-express.com/assets/rsa-BV9001fU.js
  /// 已用抓包密文校验：密文恒为 256 字节
  static const String prodPublicKey = 'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8A'
      'MIIBCgKCAQEAsb7vM3BRtRBKkhDzA9l3nQToFEIo8gLr6GwDwYrmCQBGmMSFoAhb'
      'EHhUqgHRIBdW7O8zy12P2QABmdExILMDdPXNhCsObwq9xtxFfl/zKTONv6AWrEhi'
      'X+Ptsofv8EgdWdY7DYzwT28V89RqKrT2Sh93GC5aHvcqCVQswc8EQ31HpYMXPkVX'
      'zpklgzm9atHKHenDaMTOY7y9JyS53Pb8F0URUESnz9CE3lSS78u4VyqKf3dHWxGo'
      'gS/Wu+gZNveLAOKbAFBNMDb/ytsvKUZsMZ2OMPUp/cc5QRbClAS7nu7fOfi80TnJ'
      'Dy9EaeqspgqeVcphzNKsOQP13C5k9WJZeQIDAQAB';

  /// 官方 App 移动端 UA（H5 页面识别）
  static const String mobileUA =
      'Mozilla/5.0 (Linux; Android 16; wv) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Version/4.0 Chrome/130.0.0.0 Mobile Safari/537.36';

  final http.Client _client = http.Client();

  Future<void> close() {
    _client.close();
    return Future.value();
  }

  Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
        'Accept': 'application/json, text/plain, */*',
        'Origin': h5Base,
        'Referer': forgotEntry,
        'User-Agent': mobileUA,
      };

  /// 通用 POST（H5 网关）
  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body,
      {Map<String, String>? extra}) async {
    final headers = _jsonHeaders;
    if (extra != null) headers.addAll(extra);
    final resp = await _client
        .post(Uri.parse('$apiBase$path'),
            headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 20));
    try {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      return {
        'success': false,
        'errorMessage': '非JSON响应 (${resp.statusCode})',
      };
    }
  }

  /// 下发忘记密码短信验证码（需 riskInfo + 极验，正常由 H5 页面内部调用）
  Future<Map<String, dynamic>> sendResetCode(String mobile) async {
    return _post('/passport/v1/security/nologin/sms/send_code', {
      'mobile': mobile,
      'countryCode': '86',
      'bizRegion': 'CN',
      'channel': 'sf_app_h5',
      'scenario': 'reset_password',
    });
  }

  /// 校验忘记密码短信验证码 → resetToken（需前台 riskInfo）
  Future<Map<String, dynamic>> verifyResetCode(
      String mobile, String code) async {
    return _post('/passport/v1/security/nologin/password/reset/verify', {
      'mobile': mobile,
      'countryCode': '86',
      'verifyCode': code,
    });
  }

  /// 提交新密码（newPassword 为 RSA 密文，需 resetToken）
  Future<Map<String, dynamic>> executeReset(
      String resetToken, String encryptedNewPwd) async {
    return _post('/passport/v1/security/nologin/password/reset/execute', {
      'resetToken': resetToken,
      'newPassword': encryptedNewPwd,
    });
  }

  /// 校验登录态（H5 内部使用）
  Future<Map<String, dynamic>> checkToken() async {
    final resp = await _client
        .get(Uri.parse('$apiBase/token/check'), headers: _jsonHeaders)
        .timeout(const Duration(seconds: 15));
    try {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      return {'success': false};
    }
  }

  /// 是否是顺丰相关域（用于拦截 CK 提取）
  static bool isSfHost(String url) {
    final u = url.toLowerCase();
    return u.contains('sf-express.com') || u.contains('sf-express');
  }

  /// 从 Cookie 字符串中解析出关键字段
  static SfCookieInfo parseCookie(String raw) {
    String pick(String key) {
      final m = RegExp('(?:^|;\\s*)${RegExp.escape(key)}=([^;]*)')
          .firstMatch(raw);
      return m?.group(1)?.trim() ?? '';
    }

    return SfCookieInfo(
      sessionId: pick('sessionId'),
      loginMobile: pick('_login_mobile_'),
      loginUserId: pick('_login_user_id_'),
      raw: raw.trim(),
    );
  }
}

/// 从 WebView Cookie / 网络响应中提取的顺丰登录凭证
class SfCookieInfo {
  final String sessionId;
  final String loginMobile;
  final String loginUserId;
  final String raw;

  SfCookieInfo({
    required this.sessionId,
    required this.loginMobile,
    required this.loginUserId,
    required this.raw,
  });

  bool get isComplete =>
      sessionId.isNotEmpty && loginUserId.isNotEmpty && loginMobile.isNotEmpty;

  /// 掩码手机号，如 131****0086
  String get maskedMobile {
    if (loginMobile.length != 11) return loginMobile;
    return '${loginMobile.substring(0, 3)}****'
        '${loginMobile.substring(7)}';
  }

  /// 精简 CK（仅关键三项）
  String get ck {
    final parts = <String>[];
    if (sessionId.isNotEmpty) parts.add('sessionId=$sessionId');
    if (loginMobile.isNotEmpty) parts.add('_login_mobile_=$loginMobile');
    if (loginUserId.isNotEmpty) parts.add('_login_user_id_=$loginUserId');
    return parts.join(';');
  }

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'loginMobile': loginMobile,
        'loginUserId': loginUserId,
        'raw': raw,
      };

  factory SfCookieInfo.fromJson(Map<String, dynamic> j) => SfCookieInfo(
        sessionId: j['sessionId'] ?? '',
        loginMobile: j['loginMobile'] ?? '',
        loginUserId: j['loginUserId'] ?? '',
        raw: j['raw'] ?? '',
      );
}
