import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';

/// 央视频 JACC 原生二进制协议客户端
/// 与原版 JaccClient.java 100% 字节级严格对齐
class JaccLoginResult {
  String err = '';
  String nickname = '';
  String vuserid = '';
  String vusession = '';
  String accessToken = '';
  String refreshToken = '';
  String yspopenid = '';

  JaccLoginResult({
    this.err = '',
    this.nickname = '',
    this.vuserid = '',
    this.vusession = '',
    this.accessToken = '',
    this.refreshToken = '',
    this.yspopenid = '',
  });

  bool get success => err.isEmpty && vusession.isNotEmpty;
}

class JaccSendResult {
  final bool success;
  final String msg;
  JaccSendResult(this.success, this.msg);
}

class _JaccReplacement {
  final List<int> from;
  final List<int> to;
  const _JaccReplacement(this.from, this.to);
}

class JaccClient {
  static const String host = 'https://jacc.ysp.cctv.cn/';

  // ── 原始抓包数据模板（号码位置已完全脱敏替换为公共虚拟号 +8613800000000，长 14 字节，不含任何真实个人隐私） ──
  static const String _template460Outer =
      '13000001dc0002ff01606800000000000000000066000002130000271c00000000000000003935326234633661646262343631306431336631656464386638373730303963010004a77f0000000000000000000000000001af';
  static const String _template460Inner =
      '26000001af01000000000000000000000a00661160682a060b332e352e322e323638323816063330353032332c3c4003560d4f6e65506c75732c33362c3136600170048101e096053130303037a600b600c600d62e66336466303233663666326134353438333162396234326432623165326133343366323530303130323161373132e600fa0f0c1c26000bf6100f333430333332343933313139353437f61100f61200fa130c140000000024000000003500000000000000000bf6141061343739383731396438393362363334f61506504b52313130f01601fc17fc18fc19fc1af61b00f61c00f61d243735323461366235303334626332313736656131363362313130303031613331393531620b36073132303030313346203935326234633661646262343631306431336631656464386638373730303963590c6a0610706167655f6c6f67696e5f70686f6e651610706167655f6c6f67696e5f70686f6e652006360473656c664c560066007600860531303030379600a6000b790c8c9cac0b1d000027060a31343030323237393136160e2b38363133383030303030303030260036034f4e456602383628';
  static const String _template466Outer =
      '13000001ee0002ff01ea5200000000000000000067000002130000271c00000000000000003935326234633661646262343631306431336631656464386638373730303963010004a77f0000000000000000000000000001fb';
  static const String _template466Inner =
      '26000001fb01000000000000000000000a0067120000ea522a060b332e352e322e323638323816063330353032332c3c4003560d4f6e65506c75732c33362c3136600170048101e096053130303037a600b600c600d62e66336466303233663666326134353438333162396234326432623165326133343366323530303130323161373132e600fa0f0c1c26000bf6100f333430333339333536323632393832f61100f61200fa130c140000000024000000003500000000000000000bf6141061343739383731396438393362363334f61506504b52313130f01601fc17fc18fc19fc1af61b00f61c00f61d243735323461366235303334626332313736656131363362313130303031613331393531620b36073132303030313346203935326234633661646262343631306431336631656464386638373730303963590c6a0610706167655f6c6f67696e5f70686f6e651610706167655f6c6f67696e5f70686f6e652006360473656c664c560066007600860531303030379600a6000b790c8c9cac0b1d0000710900010a00681a0600160e2b383631333830303030303030302600360046063930333432345c0b0b1a0008160026203935326234633661646262343631306431336631656464386638373730303963361061343739383731396438393362363334460d4f6e65506c75732c33362c31360b28';

  // 占位常量（严格保持 14 字节，与上面的模板 100% 对应）
  static const String _origPhonePlaceholder = '+8613800000000';
  static const String _origReqId460 = '340332493119547';
  static const String _origCode466 = '903424';
  static const String _origReqId466 = '340339356262982';

  // 固定的 32 位设备唯一指纹 GUID（与原版保持一致）
  final String guid = '952b4c6adbb4610d13f1edd8f877009c';

  Random? _rng;
  Random get rng => _rng ??= Random.secure();

  /// 随机 requestId（原版公式: Math.abs(random.nextLong()) % 0x3328b944c4000 + 0x5af3107a4000）
  String _randomReqId() {
    final v = rng.nextInt(1 << 32).abs();
    final base = BigInt.from(0x3328b944c4000);
    final offset = BigInt.from(0x5af3107a4000);
    final val = (BigInt.from(v) % base) + offset;
    return val.toString();
  }

  /// 字节数组模式替换（与 Java replaceAll 逻辑 100% 一致）
  List<int> _replaceAll(List<int> src, List<int> from, List<int> to) {
    if (from.isEmpty) return List<int>.from(src);
    final out = <int>[];
    var i = 0;
    while (i < src.length) {
      var matched = true;
      if (i + from.length > src.length) {
        matched = false;
      } else {
        for (var j = 0; j < from.length; j++) {
          if (src[i + j] != from[j]) {
            matched = false;
            break;
          }
        }
      }
      if (matched) {
        out.addAll(to);
        i += from.length;
      } else {
        out.add(src[i]);
        i++;
      }
    }
    return out;
  }

  List<int> _hexToBytes(String hex) {
    final out = List<int>.filled(hex.length ~/ 2, 0);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  List<int> _strToBytes(String s) => utf8.encode(s);

  /// GZIP 压缩
  List<int> _gzip(List<int> data) {
    final enc = GZipEncoder();
    return List<int>.from(enc.encode(data)!);
  }

  /// GZIP 解压（严格按照原版 Java decompressJaccResponse: 寻找 0x1f 0x8b，截取至 length - 1，去除 0x03 尾字节）
  List<int>? _decompressJaccResponse(List<int> raw) {
    const magic = [0x1f, 0x8b];
    final idx = _indexOf(raw, magic);
    if (idx < 0) {
      return null;
    }
    // 原版 Java (Line 193): sub_len = len - idx - 1
    final subLen = raw.length - idx - 1;
    if (subLen <= 0) return null;
    final gzData = raw.sublist(idx, idx + subLen);

    try {
      final dec = GZipDecoder();
      return dec.decodeBytes(gzData) as List<int>;
    } catch (_) {
      // 容错：如果尾部不包含 0x03，尝试全量解压
      try {
        return GZipDecoder().decodeBytes(raw.sublist(idx)) as List<int>;
      } catch (_) {
        return null;
      }
    }
  }

  int _indexOf(List<int> haystack, List<int> needle, [int start = 0]) {
    if (needle.isEmpty) return 0;
    for (var i = start; i <= haystack.length - needle.length; i++) {
      var ok = true;
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          ok = false;
          break;
        }
      }
      if (ok) return i;
    }
    return -1;
  }

  int _lastIndexOf(List<int> haystack, int byte, [int? from]) {
    final upper = from ?? haystack.length - 1;
    for (var i = upper; i >= 0; i--) {
      if (haystack[i] == byte) return i;
    }
    return -1;
  }

  /// 构造完整 JACC 数据包（严格对齐原版 Smali Line 103-114 & Line 199-234）
  List<int> _buildPacket({
    required List<int> innerTemplate,
    required List<int> outerTemplate,
    required List<_JaccReplacement> innerReplacements,
  }) {
    var inner = List<int>.from(innerTemplate);
    for (final r in innerReplacements) {
      inner = _replaceAll(inner, r.from, r.to);
    }

    // inner[1..4] = BE32(inner.length)
    final innerLen = inner.length;
    inner[1] = (innerLen >> 24) & 0xff;
    inner[2] = (innerLen >> 16) & 0xff;
    inner[3] = (innerLen >> 8) & 0xff;
    inner[4] = innerLen & 0xff;

    final gz = _gzip(inner);

    final outer = List<int>.from(outerTemplate);
    // outer 总长 = outer.length + gz.length + 1（结尾 0x03 字节）
    final totalLen = outer.length + gz.length + 1;
    outer[1] = (totalLen >> 24) & 0xff;
    outer[2] = (totalLen >> 16) & 0xff;
    outer[3] = (totalLen >> 8) & 0xff;
    outer[4] = totalLen & 0xff;

    // 原版 Smali Line 199-220: outer[0x57] 和 outer[0x58] 写入的是 inner 的原始明文长度！
    outer[0x57] = (inner.length >> 8) & 0xff;
    outer[0x58] = inner.length & 0xff;

    // 原版 Smali Line 234: 尾部写入 0x03
    return <int>[...outer, ...gz, 3];
  }

  /// HTTP POST JACC（原版：POST + octet-stream + jcegodid 头 + request-id）
  Future<List<int>> _httpPost(List<int> body, String reqId, int godid) async {
    final client = HttpClient();
    client.badCertificateCallback = (cert, host, port) => true;
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.postUrl(Uri.parse(host));
      req.headers.set(HttpHeaders.contentTypeHeader, 'application/octet-stream');
      req.headers.set(HttpHeaders.userAgentHeader, 'okhttp/4.11.0');
      req.headers.set('Accept-Encoding', 'gzip');
      req.headers.set('request-id', reqId);
      req.headers.set('jcegodid', '$godid');
      req.add(body);
      final resp = await req.close();
      final data = await resp.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      return data;
    } finally {
      client.close();
    }
  }

  /// 下发短信验证码 (godid 24680)
  Future<JaccSendResult> sendSms(String phone) async {
    final reqId = _randomReqId();
    final phoneBytes = _strToBytes('+86$phone');
    final reqIdBytes = _strToBytes(reqId);

    final packet = _buildPacket(
      innerTemplate: _hexToBytes(_template460Inner),
      outerTemplate: _hexToBytes(_template460Outer),
      innerReplacements: [
        _JaccReplacement(_strToBytes(_origPhonePlaceholder), phoneBytes),
        _JaccReplacement(_strToBytes(_origReqId460), reqIdBytes),
      ],
    );

    final resp = await _httpPost(packet, reqId, 24680);
    return _parseSendResponse(resp);
  }

  /// 提交验证码登录 (godid 59986)
  Future<JaccLoginResult> verifySms(String phone, String smsCode) async {
    final reqId = _randomReqId();
    final phoneBytes = _strToBytes('+86$phone');
    final codeBytes = _strToBytes(smsCode);
    final reqIdBytes = _strToBytes(reqId);

    final packet = _buildPacket(
      innerTemplate: _hexToBytes(_template466Inner),
      outerTemplate: _hexToBytes(_template466Outer),
      innerReplacements: [
        _JaccReplacement(_strToBytes(_origPhonePlaceholder), phoneBytes),
        _JaccReplacement(_strToBytes(_origCode466), codeBytes),
        _JaccReplacement(_strToBytes(_origReqId466), reqIdBytes),
      ],
    );

    final resp = await _httpPost(packet, reqId, 59986);
    return _parseLoginResponse(resp);
  }

  /// 解析发送验证码响应（原版 Smali Line 208-237 严格 1:1 对齐）
  JaccSendResult _parseSendResponse(List<int> raw) {
    final decomp = _decompressJaccResponse(raw);
    if (decomp == null) {
      return JaccSendResult(false, '网络响应解析异常');
    }

    String text;
    try {
      text = utf8.decode(decomp);
    } catch (_) {
      text = String.fromCharCodes(decomp);
    }

    if (text.contains('ok')) {
      return JaccSendResult(true, '验证码已成功下发');
    }

    final match = RegExp(r'[\u4e00-\u9fa5，。！]+').firstMatch(text);
    if (match != null) {
      return JaccSendResult(false, match.group(0)!);
    }
    return JaccSendResult(false, '发送失败，请稍后重试');
  }

  /// 解析登录凭证响应（原版 Smali Line 241-452 严格 1:1 对齐）
  JaccLoginResult _parseLoginResponse(List<int> raw) {
    final result = JaccLoginResult();
    final p1 = _decompressJaccResponse(raw);
    if (p1 == null) {
      result.err = '登录响应数据解压失败';
      return result;
    }

    try {
      // 1. 提取昵称 (Smali Line 250-280)
      const picMark = 'pic.yangshipin.cn';
      final picBytes = utf8.encode(picMark);
      var idxPic = _indexOf(p1, picBytes);
      if (idxPic != -1) {
        var last06 = _lastIndexOf(p1, 0x16, idxPic);
        if (last06 != -1) {
          last06 = _lastIndexOf(p1, 0x06, last06);
          if (last06 != -1 && last06 + 1 < p1.length) {
            final nickLen = p1[last06 + 1] & 0xff;
            final start = last06 + 2;
            if (nickLen > 0 && start + nickLen <= p1.length) {
              result.nickname =
                  utf8.decode(p1.sublist(start, start + nickLen), allowMalformed: true).trim();
            }
          }
        }
      }

      // 兜底“手机用户” (Smali Line 267-280)
      if (result.nickname.isEmpty) {
        final userMark = utf8.encode('手机用户');
        final userIdx = _indexOf(p1, userMark);
        if (userIdx != -1) {
          final prefixLen = p1[userIdx - 1] & 0xff;
          if (prefixLen >= 12 && prefixLen <= 60 && userIdx + prefixLen <= p1.length) {
            result.nickname =
                utf8.decode(p1.sublist(userIdx, userIdx + prefixLen), allowMalformed: true).trim();
          } else {
            var end = userIdx;
            while (end < p1.length && (p1[end] >= 0x20 && p1[end] <= 0x7e || (p1[end] & 0x80) != 0)) {
              if (p1[end] < 0x20) break;
              end++;
            }
            result.nickname =
                utf8.decode(p1.sublist(userIdx, end), allowMalformed: true).trim();
          }
        }
      }

      // 2. array_0: [0x16, 0x20] -> yspopenid (32 字节, Smali Line 285-288)
      final tagOpenId = [0x16, 0x20];
      final idxOpenId = _indexOf(p1, tagOpenId);
      if (idxOpenId != -1 && idxOpenId + 2 + 32 <= p1.length) {
        result.yspopenid = ascii.decode(p1.sublist(idxOpenId + 2, idxOpenId + 2 + 32), allowInvalid: true);
      }

      // 3. array_1: [0x26, 0x2b] -> accessToken (43 字节, Smali Line 291-294)
      final tagAccessToken = [0x26, 0x2b];
      final idxAccessToken = _indexOf(p1, tagAccessToken);
      if (idxAccessToken != -1 && idxAccessToken + 2 + 43 <= p1.length) {
        result.accessToken = ascii.decode(p1.sublist(idxAccessToken + 2, idxAccessToken + 2 + 43), allowInvalid: true);
      }

      // 4. array_2: [0x36, 0x2b] -> refreshToken (43 字节, Smali Line 297-300)
      final tagRefreshToken = [0x36, 0x2b];
      final idxRefreshToken = _indexOf(p1, tagRefreshToken);
      if (idxRefreshToken != -1 && idxRefreshToken + 2 + 43 <= p1.length) {
        result.refreshToken = ascii.decode(p1.sublist(idxRefreshToken + 2, idxRefreshToken + 2 + 43), allowInvalid: true);
      }

      // 5. array_3: [0x16, 0x2b] -> vusession (43 字节, Smali Line 303-306) & vuserid (Smali Line 308-314)
      final tagVuSession = [0x16, 0x2b];
      final idxVuSession = _indexOf(p1, tagVuSession);
      if (idxVuSession != -1 && idxVuSession + 2 + 43 <= p1.length) {
        result.vusession = ascii.decode(p1.sublist(idxVuSession + 2, idxVuSession + 2 + 43), allowInvalid: true);

        // vuserid 是在 idxVuSession (也就是 0x16 0x2b) 前面的 4 字节无符号大端整数！
        if (idxVuSession >= 4) {
          final b0 = p1[idxVuSession - 4] & 0xff;
          final b1 = p1[idxVuSession - 3] & 0xff;
          final b2 = p1[idxVuSession - 2] & 0xff;
          final b3 = p1[idxVuSession - 1] & 0xff;
          final vuid = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;
          if (vuid > 0) {
            result.vuserid = vuid.toString();
          }
        }
      }

      // 6. 验证 session，如为空提取错误提示
      if (result.vusession.isEmpty) {
        final text = utf8.decode(p1, allowMalformed: true);
        final match = RegExp(r'[\u4e00-\u9fa5，。！]+').firstMatch(text);
        result.err = match != null ? match.group(0)! : '登录失败，未解析到会话凭证';
      }
    } catch (e) {
      result.err = '解析异常: $e';
    }

    return result;
  }

  /// 组装完整 Cookie（与原版 buildFinalCookie 100% 一致）
  static String buildFinalCookie({
    required JaccLoginResult login,
    required String guid,
  }) {
    final sb = StringBuffer();
    sb.write('video_omgid=f3df023f6f2a454831b9b42d2b1e2a343f25001021a712; ');
    sb.write('guid=$guid; ');
    sb.write('main_login=none; ');
    sb.write('vuserid=${login.vuserid}; ');
    sb.write('vusession=${login.vusession}; ');
    sb.write('access_token=${login.accessToken}; ');
    sb.write('refresh_token=${login.refreshToken}; ');
    sb.write('logintype=5; ');
    sb.write('_video_qq_version=1.0; ');
    sb.write('vplatform=3; ');
    sb.write('yspExtentAccountList=%5B%5D; ');
    sb.write('ysptokenappid=1200013');
    if (login.yspopenid.isNotEmpty) {
      sb.write('; yspopenid=${login.yspopenid}');
    }
    return sb.toString();
  }
}
