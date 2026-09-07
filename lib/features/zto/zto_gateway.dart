import 'dart:convert';

import 'package:http/http.dart' as http;

/// 中通官方网关直连 — 与原版中通 MainActivity（本地 Java 网关）100% 逻辑一致
class ZtoGateway {
  static const String serviceBase = 'https://hdgateway.zto.com';
  static const String mapiBase = 'https://mapi.zto.com';
  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  final http.Client _client = http.Client();

  Future<void> close() async {
    _client.close();
  }

  Map<String, String> get _baseHeaders => {
        'User-Agent': _ua,
        'Origin': 'https://auth.zto.com',
        'Referer': 'https://auth.zto.com/',
        'Content-Type': 'application/json;charset=UTF-8',
        'x-clientCode': 'pc',
        'x-token': '',
      };

  /// 通用 POST（自动透传额外头）
  Future<Map<String, dynamic>> _post(String url, Map<String, dynamic> body,
      {Map<String, String>? extraHeaders}) async {
    final headers = _baseHeaders;
    if (extraHeaders != null) headers.addAll(extraHeaders);
    final resp = await _client
        .post(Uri.parse(url), headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 20));
    try {
      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      return {'status': false, 'message': '非JSON响应: ${resp.statusCode}'};
    }
  }

  /// 获取验证码（返回 channel / id / image）
  Future<Map<String, dynamic>> getCaptcha() async {
    final root = await _post('$mapiBase/captcha/image2', {});
    if (root['status'] == true) {
      final res = root['result'] as Map<String, dynamic>? ?? {};
      return {
        'status': 'success',
        'type': res['channel'] ?? 'original',
        'id': res['id'] ?? '',
        'image': res['image'] ?? '',
      };
    }
    return {'status': 'fail', 'message': root['message'] ?? '获取失败'};
  }

  /// 密码登录 → token
  Future<Map<String, dynamic>> login(String userName, String password) async {
    final root = await _post('$serviceBase/auth_account_loginByPassword', {
      'userName': userName,
      'password': password,
      'isAgainBind': false,
    });
    if (root['status'] == true) {
      final res = root['result'] as Map<String, dynamic>? ?? {};
      return {'status': 'success', 'token': res['token'] ?? ''};
    }
    return {'status': 'fail', 'message': root['message'] ?? '登录失败'};
  }

  /// 注册 — 发短信
  Future<Map<String, dynamic>> sendRegisterCode(
      String mobile, String captchaId, String captchaCode) async {
    final root = await _post(
      '$serviceBase/auth_account_sendRegisterSmsVerifyCode',
      {'mobile': mobile},
      extraHeaders: {'x-captcha-id': captchaId, 'x-captcha-code': captchaCode},
    );
    return root['status'] == true
        ? {'status': 'success'}
        : {'status': 'fail', 'message': root['message'] ?? '发送失败'};
  }

  /// 注册 — 提交
  Future<Map<String, dynamic>> register(
      String mobile, String code, String newPwd) async {
    final root = await _post(
        '$serviceBase/auth_account_registerBySmsVerifyCode',
        {'mobile': mobile, 'verifyCode': code, 'password': newPwd});
    return root['status'] == true
        ? {'status': 'success'}
        : {'status': 'fail', 'message': root['message'] ?? '注册失败'};
  }

  /// 忘记密码 — 发短信
  Future<Map<String, dynamic>> sendForgotCode(
      String mobile, String captchaId, String captchaCode) async {
    final root = await _post(
      '$serviceBase/auth_account_sendForgotPasswordVerifyCode',
      {'twoFactorVerifyType': 'sms', 'userName': mobile},
      extraHeaders: {'x-captcha-id': captchaId, 'x-captcha-code': captchaCode},
    );
    return root['status'] == true
        ? {'status': 'success'}
        : {'status': 'fail', 'message': root['message'] ?? '发送失败'};
  }

  /// 忘记密码 — 校验验证码
  Future<Map<String, dynamic>> verifyForgotCode(
      String mobile, String code) async {
    final root = await _post(
        '$serviceBase/auth_account_checkForgotPasswordVerifyCode',
        {'twoFactorVerifyType': 'sms', 'twoFactorVerifyCode': code, 'userName': mobile});
    return root['status'] == true
        ? {'status': 'success'}
        : {'status': 'fail', 'message': root['message'] ?? '验证失败'};
  }

  /// 忘记密码 — 重置
  Future<Map<String, dynamic>> resetPassword(
      String mobile, String code, String newPwd) async {
    final root = await _post(
        '$serviceBase/auth_account_forgotPasswordByVerifyCode',
        {
          'twoFactorVerifyType': 'sms',
          'twoFactorVerifyCode': code,
          'userName': mobile,
          'newPassword': newPwd,
        });
    return root['status'] == true
        ? {'status': 'success'}
        : {'status': 'fail', 'message': root['message'] ?? '重置失败'};
  }
}
