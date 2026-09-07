/// 电信官方加密工具集 — 与原版 CryptoUtil.java 100% 逻辑一致
/// RSA/PKCS1 实现与 Java Cipher "RSA/ECB/PKCS1Padding" 语义一致
import 'dart:convert';
import 'dart:math';

class CryptoUtil {
  static const String rsaPubkeyPem =
      'MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDBkLT15ThVgz6/NOl6s8GNPofdWzWbCkWnkaAm7O2LjkM1H7dMvzkiqdxU02jamGRHLX/ZNMCXHnPcW/sDhiFCBN18qFvy8g6VYb9QtroI09e176s+ZCtiv7hbin2cCTj99iUpnEloZm19lwHyo69u5UMiPMpq0/XKBO8lYhN/gwIDAQAB';

  static const List<String> deviceModels = [
    'Xiaomi M2012K11AC', 'Xiaomi M2011K2C', 'Xiaomi 23013RK75C', 'Xiaomi 24031PN0DC',
    'HUAWEI NOH-AN00', 'HUAWEI LIO-AN00', 'HUAWEI BRA-AL00', 'HUAWEI ALN-AL00',
    'HONOR PGT-AN00', 'HONOR BVL-AN00', 'HONOR FRI-AN00', 'HONOR LLY-AN00',
    'OPPO PFTM20', 'OPPO PHZ110', 'OPPO PJH110', 'OPPO PKB110',
    'vivo V2241A', 'vivo V2307A', 'vivo V2324A', 'vivo V2405A',
    'samsung SM-S9180', 'samsung SM-S9280', 'samsung SM-F9460', 'samsung SM-A5560',
    'OnePlus PHB110', 'OnePlus PJD110', 'realme RMX3706', 'realme RMX3851',
    'Meizu 20', 'Meizu 21', 'Motorola XT2301-5', 'Google Pixel 8',
  ];

  /// +2 位移混淆编码
  static String encodeString(String str) {
    final sb = StringBuffer();
    for (final code in str.codeUnits) {
      sb.writeCharCode(code + 2);
    }
    return sb.toString();
  }

  /// yyyyMMddHHmmss 时间戳
  static String timestamp() {
    final now = DateTime.now();
    String p(int n) => n.toString().padLeft(2, '0');
    return '${now.year}${p(now.month)}${p(now.day)}'
        '${p(now.hour)}${p(now.minute)}${p(now.second)}';
  }

  static String randomAndroidId() {
    final rng = Random.secure();
    return List.generate(16, (_) => rng.nextInt(16).toRadixString(16)).join();
  }

  static String randomDeviceModel() {
    final rng = Random();
    return deviceModels[rng.nextInt(deviceModels.length)];
  }

  static String clientType(String deviceModel) =>
      '#11.0.0#channel35#$deviceModel#';

  static String userAgent(String deviceModel) => '$deviceModel/11.0.0';

  static Map<String, String> headerInfos(String code, String deviceModel,
      [String? ts, String userLoginName = '']) {
    return {
      'code': code,
      'timestamp': ts ?? timestamp(),
      'clientType': clientType(deviceModel),
      'shopId': '20002',
      'source': '110003',
      'sourcePassword': 'Sid98s',
      'token': '',
      'userLoginName': userLoginName,
    };
  }

  /// 64 位特殊填充明文（RSA 加密前）
  static String loginPlaintext(String phone, String ts, String smsCode) {
    String padRight(String s, int n, String c) =>
        s.length >= n ? s.substring(0, n) : s + c * (n - s.length);
    String repeat(String c, int n) => c * n;

    const model = 'Xiaomi M2013';
    final sb = StringBuffer();
    sb.write(padRight(model.substring(0, min(12, model.length)), 12, r'$'));
    sb.write(repeat(r'$', 15));
    sb.write(padRight(phone.substring(0, min(11, phone.length)), 11, r'$'));
    sb.write(ts.substring(0, min(14, ts.length)));
    sb.write(padRight(smsCode.substring(0, min(6, smsCode.length)), 6, r'$'));
    sb.write(repeat(r'$', 6));

    var res = sb.toString();
    if (res.length != 64) {
      if (res.length < 64) {
        res = res + repeat(r'$', 64 - res.length);
      } else {
        res = res.substring(0, 64);
      }
    }
    return res;
  }

  /// RSA PKCS1 加密后 base64
  /// DER 结构: SEQUENCE { SEQ{OID, NULL}, BIT STRING { SEQ{ INTEGER n, INTEGER e } } }
  static String loginCipher(String phone, String ts, String smsCode) {
    final plain = utf8.encode(loginPlaintext(phone, ts, smsCode));
    final keyBytes = base64.decode(rsaPubkeyPem);

    final parser = _Asn1Parser(keyBytes);
    parser.readTag(); // SEQUENCE (outer)
    parser.readLength();
    parser.readTag(); // SEQUENCE (AlgorithmIdentifier)
    final algLen = parser.readLength();
    parser.skip(algLen);
    parser.readTag(); // BIT STRING
    parser.readLength();
    parser.skip(1); // unused-bits byte
    parser.readTag(); // SEQUENCE (PublicKey)
    parser.readLength();
    parser.readTag(); // INTEGER n
    final nBytes = parser.readIntegerBytes();
    parser.readTag(); // INTEGER e
    final eBytes = parser.readIntegerBytes();

    final n = BigInt.parse(_bytesToHex(nBytes), radix: 16);
    final e = BigInt.parse(_bytesToHex(eBytes), radix: 16);

    // PKCS#1 v1.5 填充: 0x00 || 0x02 || PS(≥8非零随机) || 0x00 || D
    const k = 128;
    final rng = Random.secure();
    final psLen = k - 3 - plain.length;
    if (psLen < 8) throw Exception('RSA plaintext too long');
    final ps = List<int>.generate(psLen, (_) {
      while (true) {
        final b = rng.nextInt(256);
        if (b != 0) return b;
      }
    }).toList();

    final em = <int>[0x00, 0x02, ...ps, 0x00, ...plain];
    final m = BigInt.parse(_bytesToHex(em), radix: 16);
    final c = m.modPow(e, n);

    String hex = c.toRadixString(16);
    if (hex.length % 2 != 0) hex = '0$hex';
    final out = List<int>.filled(k, 0);
    final cipherBytes = _hexToBytes(hex);
    final offset = k - cipherBytes.length;
    out.setRange(offset, k, cipherBytes);
    return base64.encode(out);
  }

  static String _bytesToHex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static List<int> _hexToBytes(String hex) {
    final out = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      out.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return out;
  }
}

/// 极简 DER 解析器
class _Asn1Parser {
  final List<int> bytes;
  int pos = 0;

  _Asn1Parser(this.bytes);

  int readTag() => bytes[pos++];

  int readLength() {
    var len = bytes[pos++];
    if (len & 0x80 != 0) {
      final numBytes = len & 0x7f;
      len = 0;
      for (var i = 0; i < numBytes; i++) {
        len = (len << 8) | bytes[pos++];
      }
    }
    return len;
  }

  void skip(int n) => pos += n;

  List<int> readIntegerBytes() {
    final len = readLength();
    var start = pos;
    var realLen = len;
    while (realLen > 0 && bytes[start] == 0) {
      start++;
      realLen--;
    }
    final out = bytes.sublist(start, start + realLen);
    pos += len;
    return out;
  }
}
