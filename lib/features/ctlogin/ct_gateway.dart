import 'dart:convert';
import 'dart:io';

import 'ct_crypto_util.dart';

class CtCaptchaResult {
  final String key;
  final String image;
  CtCaptchaResult(this.key, this.image);
}

class CtInitiateResult {
  final bool needCaptcha;
  final String key;
  final String image;
  final String smsId;
  CtInitiateResult(this.needCaptcha, this.key, this.image, this.smsId);
}

class CtLoginResponse {
  final bool success;
  final bool duplicate;
  final String message;
  final String? androidId;
  final String? encodedAndroidId;
  CtLoginResponse(this.success,
      {this.duplicate = false,
      this.message = '',
      this.androidId,
      this.encodedAndroidId});
}

/// 电信官方网关直连 — 与原版 CTGateway.java 100% 逻辑一致
class CtGateway {
  static const String businessServer = 'https://appgo.189.cn:9200';
  static const String loginServer = 'https://appgologin.189.cn:9031';

  final String deviceModel;
  final String androidId;
  late final String userAgent;

  HttpClient? _client;

  CtGateway(this.deviceModel, this.androidId) {
    userAgent = CryptoUtil.userAgent(deviceModel);
  }

  HttpClient get client {
    _client ??= HttpClient();
    _client!.badCertificateCallback = (cert, host, port) => true;
    _client!.connectionTimeout = const Duration(seconds: 15);
    return _client!;
  }

  Future<CtInitiateResult> initiate(String phone) async {
    final resp = await _sendSmsRequest(phone, '', '');
    final code = resp['code'] as String? ?? '';
    if (code == '1016') {
      final captcha = await getCaptcha();
      return CtInitiateResult(true, captcha.key, captcha.image, '');
    } else if (code == '0000' &&
        (resp['sms_id'] as String? ?? '').isNotEmpty) {
      return CtInitiateResult(false, '', '', resp['sms_id'] as String);
    }
    throw Exception(resp['message'] ?? '无法创建登录流程');
  }

  Future<CtCaptchaResult> getCaptcha() async {
    final root = {
      'headerInfos': CryptoUtil.headerInfos('getValidationCode', deviceModel),
      'content': {'attach': 'test', 'fieldData': <String, dynamic>{}},
    };
    final resp = await _post('$businessServer/query/getValidationCode', root);
    final parsed = _parseResponse(resp);
    final dataStr = parsed['data'];
    if (parsed['code'] == '0000' &&
        dataStr != null &&
        dataStr.isNotEmpty &&
        dataStr != '{}') {
      final data = jsonDecode(dataStr) as Map<String, dynamic>;
      return CtCaptchaResult(data['key'] ?? '', data['image'] ?? '');
    }
    throw Exception((parsed['desc']?.isEmpty ?? true)
        ? '图形验证码获取失败'
        : parsed['desc']);
  }

  Future<String> sendSms(
      String phone, String captchaCode, String captchaKey) async {
    final resp = await _sendSmsRequest(phone, captchaCode, captchaKey);
    final code = resp['code'] as String? ?? '';
    final smsId = resp['sms_id'] as String? ?? '';
    if (code == '0000' && smsId.isNotEmpty) return smsId;
    throw Exception(resp['message'] ?? '短信发送失败');
  }

  Future<CtLoginResponse> login(
      String phone, String smsId, String smsCode) async {
    // 轮询短信状态（最多 5 次，每次间隔 1s）
    var status = '0';
    for (var i = 0; i < 5; i++) {
      status = await _smsStatus(smsId);
      if (status == '1') break;
      if (i < 4) await Future.delayed(const Duration(seconds: 1));
    }
    if (status != '1') {
      return CtLoginResponse(false, message: '短信状态尚未就绪');
    }

    final encPhone = CryptoUtil.encodeString(phone);
    final encAndroidId = CryptoUtil.encodeString(androidId);
    final encSmsCode = CryptoUtil.encodeString(smsCode);
    final ts = CryptoUtil.timestamp();

    final root = {
      'headerInfos':
          CryptoUtil.headerInfos('userLoginNormal', deviceModel, ts, encPhone),
      'content': {
        'attach': 'test',
        'fieldData': {
          'loginType': '2',
          'accountType': '',
          'loginAuthCipherAsymmertric':
              CryptoUtil.loginCipher(phone, ts, smsCode),
          'deviceUid': '',
          'phoneNum': encPhone,
          'isChinatelecom': '0',
          'systemVersion': '13',
          'androidId': encAndroidId,
          'loginAuthCipher': '',
          'authentication': encSmsCode,
        },
      },
    };

    try {
      final resp =
          await _post('$loginServer/login/client/userLoginNormal', root);
      final parsed = _parseResponse(resp);
      if (parsed['code'] != '0000') {
        return CtLoginResponse(false,
            message: (parsed['desc']?.isEmpty ?? true)
                ? '登录失败'
                : parsed['desc']!);
      }
      return CtLoginResponse(true,
          androidId: androidId, encodedAndroidId: encAndroidId);
    } catch (err) {
      return CtLoginResponse(false,
          message: err.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<String> _smsStatus(String smsId) async {
    final root = {
      'headerInfos': CryptoUtil.headerInfos('getSmsIdStatus', deviceModel),
      'content': {
        'attach': 'test',
        'fieldData': {'smsId': smsId},
      },
    };
    final resp = await _post('$loginServer/login/client/getSmsIdStatus', root);
    final parsed = _parseResponse(resp);
    if (parsed['code'] != '0000') {
      throw Exception((parsed['desc']?.isEmpty ?? true)
          ? '短信状态查询失败'
          : parsed['desc']);
    }
    final dataStr = parsed['data'];
    final data = (dataStr == null || dataStr.isEmpty || dataStr == '{}')
        ? <String, dynamic>{}
        : (jsonDecode(dataStr) as Map<String, dynamic>);
    return (data['smsIdStatue'] ?? '0').toString();
  }

  Future<Map<String, dynamic>> _sendSmsRequest(
      String phone, String captchaCode, String captchaKey) async {
    final root = {
      'headerInfos': CryptoUtil.headerInfos('getLoginRandomCode', deviceModel),
      'content': {
        'attach': 'test',
        'fieldData': {
          'payType': '',
          'phoneNum': CryptoUtil.encodeString(phone),
          'validationCode': captchaCode,
          'imsi': '',
          'salesProdId': '',
          'key': captchaKey,
          'androidId': CryptoUtil.encodeString(androidId),
          'scene': '55',
        },
      },
    };
    final resp =
        await _post('$loginServer/login/client/getLoginRandomCode', root);
    final parsed = _parseResponse(resp);
    var smsId = '';
    try {
      if (parsed['data'] != null &&
          parsed['data'] != '' &&
          parsed['data'] != '{}') {
        final dataObj = jsonDecode(parsed['data']!) as Map<String, dynamic>;
        smsId = dataObj['smsId'] ?? '';
      }
    } catch (_) {}
    return {
      'code': parsed['code'] ?? '',
      'message': parsed['desc'] ?? '',
      'sms_id': smsId,
    };
  }

    /// 修1：data 保留原始类型（可能是 Map），避免 toString 后 jsonDecode 报 FormatException
  Map<String, dynamic> _parseResponse(Map<String, dynamic> resp) {
    final respData =
        (resp['responseData'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final dataObj = respData['data'];
    String? dataStr;
    if (dataObj == null) {
      dataStr = null;
    } else if (dataObj is Map) {
      // 已经是 Map，直接序列化成标准 JSON（jsonEncode 输出合法 JSON）
      dataStr = jsonEncode(dataObj);
    } else if (dataObj is String) {
      dataStr = dataObj;
    } else {
      dataStr = dataObj.toString();
    }
    return {
      'code': respData['resultCode']?.toString() ?? '',
      'desc': respData['resultDesc']?.toString() ?? '',
      'data': dataStr,
    };
  }

  Future<Map<String, dynamic>> _post(
      String url, Map<String, dynamic> body) async {
    final req = await client.postUrl(Uri.parse(url));
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    req.headers
        .set(HttpHeaders.contentTypeHeader, 'application/json; charset=UTF-8');
    req.headers.set(HttpHeaders.userAgentHeader, userAgent);
    req.add(utf8.encode(jsonEncode(body)));
    final resp = await req.close();
    final text = await resp.transform(utf8.decoder).join();
    try {
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}
