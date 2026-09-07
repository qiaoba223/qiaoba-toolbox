// 央视频 JACC 动态协议客户端 — 从 exe 逆向还原
// 完全动态构建 JCE/JACC 二进制包，不依赖抓包模板替换
// 对齐 ysp_sms_login.exe 的 App 通道：24680(发码) → 59986(登录) → 59987(续期)

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ──────────────────────────────────────────────
// 常量（从 exe ysp.py 逆向还原）
// ──────────────────────────────────────────────

const _jaccHost = 'jacc.ysp.cctv.cn';
const _jaccUa = 'okhttp/4.11.0';
const _mobileAppId = '1400227916';
const _jaccDevid = 'e62d0096c4cd523e';
const _jaccDevua = 'Xiaomi,31,12';
const _vplatformAndroid = '3';
const _etokenMobile = 104;

const _cmdGetCode = 24680;
const _cmdNewLogin = 59986;
const _cmdNewRefresh = 59987;

// JCE 类型常量 (range(14) → 0..13)
const _jceByte = 0;
const _jceShort = 1;
const _jceInt = 2;
const _jceLong = 3;
const _jceFloat = 4;
const _jceDouble = 5;
const _jceStr1 = 6;
const _jceStr4 = 7;
const _jceMap = 8;
const _jceList = 9;
const _jceSbegin = 10;
const _jceSend = 11;
const _jceZero = 12;
const _jceBytes = 13;

// JACC 请求模板（base64）—— 解包后动态替换 guid/rqid/cmd/session/body
const _jaccTemplateB64 =
    'EwAAAgEAAv8BYdgAAAAAAAAAAABHAAACEwAAJxwAAAAAAAAAAGZhZTZkMzYwODY2ZjEwNWMyM2Q3Y2U4ZGJmZWY3MDVkAQAEp3IAAAAAAAAAAAAAAAAAAcMfiwgAAAAAAAAAPZHNaxNRFMXvUJuSzkBTrfGrhS5KEU3CfV933oCLQlGJRIrERuumvpn3XpqSZgISpEs3rrruquuuXIv7Qv8E8S/ouqtZlCycKHoWF85ZXH73nk2A4CKA/1qEl8vm15NKKFqqxVqcYq7rFYEKGTaebc31ovcDkx8NGoI1GP8YjOe+BD9O5xki0jl8h0v42TKpNGSdMElCqZGoUqOF9DLxWhrkaJPYYLmPs1QzdQU3S9HqJoRFbYkrxjhyLQRpRlgsQ3Ebbu5EKzO0jdlQ/0DDYqXmiFvEhDKZWcWFK+5WX3PE+JXobl/Xg+m96f3pg+nD4hEUq1CsbZD0qL1VNuVGlofp1ApHsZzRM8tYQqhDWigRSi9erHvjyIoyJPIMVcaFjTOnbeqdj1HZPQgWK1CrNgGe2rd5p72zO2l3uruTdyJ7g+2DgRymz0Xebfb6kw+jTto7bG/vND9TlWumOVEit4LwsFIbm77bH+b9wWh/fJCPXH3hT3J0vD5Ptz65oe/0wMPXv18+hXMIj6OTs2/hWlle9Pg3+dtNXMMBAAAD';

// ──────────────────────────────────────────────
// ByteData 辅助
// ──────────────────────────────────────────────

int _unpackFromB(BytesData d, int offset, int size, bool signed) {
  final bd = d.bd;
  switch (size) {
    case 1:
      return signed ? bd.getInt8(offset) : bd.getUint8(offset);
    case 2:
      return signed ? bd.getInt16(offset, Endian.big) : bd.getUint16(offset, Endian.big);
    case 4:
      return signed ? bd.getInt32(offset, Endian.big) : bd.getUint32(offset, Endian.big);
    case 8:
      return signed ? bd.getInt64(offset, Endian.big) : bd.getUint64(offset, Endian.big);
    default:
      throw Exception('bad size $size');
  }
}

class BytesData {
  final Uint8List buf;
  final ByteData bd;
  BytesData(this.buf) : bd = ByteData.sublistView(buf);
  int len() => buf.length;
  int operator [](int i) => buf[i];
  Uint8List slice(int start, int end) =>
      Uint8List.sublistView(buf, start, end < 0 ? buf.length : end);
}

// ──────────────────────────────────────────────
// JCE 协议：读
// ──────────────────────────────────────────────

class JceNode {
  int type;
  final int tag;
  dynamic val; // int/double/String/[pad,n,raw]/List<JceNode>
  int end; // exe 里 end 默认 0

  JceNode(this.type, this.tag, this.val, [this.end = 0]);
}

/// 读 JCE 头：返回 (type, tag, newOffset)
List<int> _jceReadHead(BytesData d, int i) {
  int h = d[i];
  i += 1;
  int tag = (h >> 4) & 15;
  int t = h & 15;
  if (tag == 15) {
    tag = d[i] & 255;
    i += 1;
    if (tag == 255) {
      tag = _unpackFromB(d, i, 2, false);
      i += 2;
    }
  }
  return [t, tag, i];
}

/// 读 JCE 值
JceNode _jceReadValue(BytesData d, int i, int t, int tag) {
  dynamic v;
  switch (t) {
    case _jceByte:
      v = _unpackFromB(d, i, 1, true); i += 1; break;
    case _jceShort:
      v = _unpackFromB(d, i, 2, true); i += 2; break;
    case _jceInt:
      v = _unpackFromB(d, i, 4, true); i += 4; break;
    case _jceLong:
      v = _unpackFromB(d, i, 8, true); i += 8; break;
    case _jceFloat:
      v = ByteData.sublistView(d.buf, i, i + 4).getFloat32(0, Endian.big);
      i += 4; break;
    case _jceDouble:
      v = ByteData.sublistView(d.buf, i, i + 8).getFloat64(0, Endian.big);
      i += 8; break;
    case _jceStr1:
    case _jceStr4:
      int n;
      if (t == _jceStr1) {
        n = d[i]; i += 1;
      } else {
        n = _unpackFromB(d, i, 4, false); i += 4;
      }
      v = utf8.decode(d.slice(i, i + n), allowMalformed: true);
      i += n; break;
    case _jceBytes:
      // exe: v = (pad, n, raw)
      int pad = d[i]; i += 1;
      final res = _jceReadCompact(d, i);
      int n = res[0] as int; i = res[1] as int;
      v = [pad, n, Uint8List.sublistView(d.buf, i, i + n)];
      i += n; break;
    case _jceList:
      // exe: jceReadHead(buf, i) -> t2, _tg, j; if t2==ZERO: empty;
      // else jceReadCompact(buf, i) -> cn, i (注意用原始 i，不是 j！)
      final lhead = _jceReadHead(d, i);
      int lt = lhead[0]; int lj = lhead[2];
      if (lt == _jceZero) {
        i = lj;
        v = <JceNode>[]; break;
      }
      // 读 count：用原始 i（head byte 同时充当 compact 整数头）
      final cnRes = _jceReadCompact(d, i);
      int cn = cnRes[0] as int; i = cnRes[1] as int;
      final list = <JceNode>[];
      for (int k = 0; k < cn; k++) {
        final h2 = _jceReadHead(d, i);
        int tt = h2[0], tg = h2[1]; i = h2[2];
        if (tt == _jceZero) {
          list.add(JceNode(_jceZero, tg, null, i));
        } else {
          final e = _jceReadValue(d, i, tt, tg);
          i = e.end;
          list.add(e);
        }
      }
      v = list; break;
    case _jceMap:
      final head = _jceReadHead(d, i);
      int t2 = head[0]; int mj = head[2];
      if (t2 == _jceZero) {
        i = mj;
        v = <JceNode>[]; break;
      }
      // 读 count：用原始 i（与 exe 一致）
      final cnRes = _jceReadCompact(d, i);
      int cn = cnRes[0] as int; i = cnRes[1] as int;
      final list = <JceNode>[];
      for (int k = 0; k < cn; k++) {
        final kh = _jceReadHead(d, i);
        int kt = kh[0], ktg = kh[1]; i = kh[2];
        final key = _jceReadValue(d, i, kt, ktg); i = key.end;
        final vh = _jceReadHead(d, i);
        int vt = vh[0], vtg = vh[1]; i = vh[2];
        final val2 = _jceReadValue(d, i, vt, vtg); i = val2.end;
        list.add(JceNode(_jceMap, key.tag, [key, val2], i));
      }
      v = list; break;
    case _jceSbegin:
      final list = <JceNode>[];
      while (true) {
        final head = _jceReadHead(d, i);
        int tt = head[0], tg = head[1]; int j = head[2];
        if (tt == _jceSend) { i = j; break; }
        if (tt == _jceZero) {
          list.add(JceNode(_jceZero, tg, null, j));
          i = j;
        } else {
          final nd = _jceReadValue(d, j, tt, tg);
          list.add(nd);
          i = nd.end;
        }
      }
      v = list; break;
    case _jceZero:
      v = null; break;
    default:
      throw Exception('bad JCE type $t @$i');
  }
  return JceNode(t, tag, v, i);
}

/// 读一个 compact 值（head+value）：返回 [value, newOffset]
List<dynamic> _jceReadCompact(BytesData d, int i) {
  final head = _jceReadHead(d, i);
  int t = head[0], tag = head[1]; int j = head[2];
  if (t == _jceZero) return [0, j];
  final nd = _jceReadValue(d, j, t, tag);
  return [nd.val, nd.end];
}

/// 解析 JCE 结构：返回 List<JceNode>
List<JceNode> _jceParseStruct(Uint8List buf) {
  final d = BytesData(buf);
  final out = <JceNode>[];
  int i = 0;
  while (i < d.len()) {
    final head = _jceReadHead(d, i);
    int t = head[0], tag = head[1]; int j = head[2];
    if (t == _jceSend) break;
    if (t == _jceZero) {
      out.add(JceNode(_jceZero, tag, null, j));
      i = j;
    } else {
      final nd = _jceReadValue(d, j, t, tag);
      out.add(nd);
      i = nd.end;
    }
  }
  return out;
}

// ──────────────────────────────────────────────
// JCE 协议：写
// ──────────────────────────────────────────────

Uint8List _jceWriteHead(int t, int tag) {
  if (tag < 15) {
    return Uint8List.fromList([(tag << 4) | t]);
  }
  if (tag < 256) {
    return Uint8List.fromList([0xf0 | t, tag & 255]);
  }
  final b = BytesBuilder()
    ..add([0xf0 | t, 255])
    ..add(_packU16(tag));
  return b.toBytes();
}

Uint8List _packU8(int v) => Uint8List(1)..[0] = v & 0xFF;
Uint8List _packU16(int v) {
  final b = ByteData(2)..setUint16(0, v & 0xFFFF, Endian.big);
  return b.buffer.asUint8List();
}
Uint8List _packI8(int v) => _packU8(v & 0xFF);
Uint8List _packI16(int v) {
  final b = ByteData(2)..setInt16(0, v, Endian.big);
  return b.buffer.asUint8List();
}
Uint8List _packI32(int v) {
  final b = ByteData(4)..setInt32(0, v, Endian.big);
  return b.buffer.asUint8List();
}
Uint8List _packI64(int v) {
  final b = ByteData(8)..setInt64(0, v, Endian.big);
  return b.buffer.asUint8List();
}

Uint8List _jceEncCompact(int v) {
  if (v == 0) {
    return _jceWriteHead(_jceZero, 0);
  }
  if (v >= -128 && v <= 127) {
    final b = BytesBuilder()
      ..add(_jceWriteHead(_jceByte, 0))
      ..add(_packI8(v));
    return b.toBytes();
  }
  if (v >= -32768 && v <= 32767) {
    final b = BytesBuilder()
      ..add(_jceWriteHead(_jceShort, 0))
      ..add(_packI16(v));
    return b.toBytes();
  }
  if (v >= -2147483648 && v < 2147483648) {
    final b = BytesBuilder()
      ..add(_jceWriteHead(_jceInt, 0))
      ..add(_packI32(v));
    return b.toBytes();
  }
  final b = BytesBuilder()
    ..add(_jceWriteHead(_jceLong, 0))
    ..add(_packI64(v));
  return b.toBytes();
}

JceNode _jceField(dynamic val, int tag) {
  // exe 顺序: bool → int → str → TypeError
  if (val is bool) {
    return JceNode(_jceByte, tag, val ? 1 : 0, 0);
  }
  if (val is int) {
    if (val == 0) {
      return JceNode(_jceZero, tag, null, 0);
    } else if (val >= -128 && val <= 127) {
      return JceNode(_jceByte, tag, val, 0);
    } else if (val >= -32768 && val <= 32767) {
      return JceNode(_jceShort, tag, val, 0);
    } else if (val >= -2147483648 && val < 2147483648) {
      return JceNode(_jceInt, tag, val, 0);
    } else {
      return JceNode(_jceLong, tag, val, 0);
    }
  }
  if (val is String) {
    // exe: len(v.encode('utf-8')) <= 255 → STR1, else STR4
    final encoded = utf8.encode(val);
    if (encoded.length <= 255) {
      return JceNode(_jceStr1, tag, val, 0);
    } else {
      return JceNode(_jceStr4, tag, val, 0);
    }
  }
  throw Exception('unsupported jceField type ${val.runtimeType}');
}

JceNode _jceBytesField(Uint8List data, int tag) {
  // val = [pad, n, raw] —— 与 exe 的 (pad, n, raw) 对齐
  return JceNode(_jceBytes, tag, [0, data.length, data], 0);
}

Uint8List _jceEncValue(JceNode nd) {
  final h = _jceWriteHead(nd.type, nd.tag);
  final b = BytesBuilder()..add(h);
  switch (nd.type) {
    case _jceByte:
      b.add(_packI8(nd.val as int)); break;
    case _jceShort:
      b.add(_packI16(nd.val as int)); break;
    case _jceInt:
      b.add(_packI32(nd.val as int)); break;
    case _jceLong:
      b.add(_packI64(nd.val as int)); break;
    case _jceFloat:
      final bd = ByteData(4)..setFloat32(0, (nd.val as num).toDouble(), Endian.big);
      b.add(bd.buffer.asUint8List()); break;
    case _jceDouble:
      final bd = ByteData(8)..setFloat64(0, (nd.val as num).toDouble(), Endian.big);
      b.add(bd.buffer.asUint8List()); break;
    case _jceZero:
      break;
    case _jceStr1:
      final bytes = utf8.encode(nd.val as String);
      b.add(_packU8(bytes.length));
      b.add(bytes);
      break;
    case _jceStr4:
      final bytes = utf8.encode(nd.val as String);
      b.add(_packI32(bytes.length));
      b.add(bytes);
      break;
    case _jceBytes:
      // exe: v = (pad, n, raw); head + bytes([pad]) + compact(n) + raw
      // Dart 里 val 是 [pad, n, raw]
      final bytesVal = nd.val as List;
      final pad = bytesVal[0] as int;
      final raw = bytesVal[2] as Uint8List;
      b.add(_packU8(pad));
      b.add(_jceEncCompact(raw.length));
      b.add(raw);
      break;
    case _jceList:
      // exe: head + compact(len(v)) + b''.join(jceEncValue(e) for e in v)
      b.add(_jceEncCompact((nd.val as List).length));
      for (final e in nd.val as List) {
        if (e is JceNode) {
          b.add(_jceEncValue(e));
        }
      }
      break;
    case _jceSbegin:
      // 结构体开始标记 + 元素们 + SEND
      for (final e in nd.val as List) {
        if (e is JceNode) {
          b.add(_jceEncValue(e));
        }
      }
      b.add(_jceWriteHead(_jceSend, 0));
      break;
    default:
      throw Exception('enc unsupported type ${nd.type}');
  }
  return b.toBytes();
}

Uint8List _jceEncStruct(List<JceNode> fields) {
  final b = BytesBuilder();
  for (final f in fields) {
    b.add(_jceEncValue(f));
  }
  return b.toBytes();
}

// ──────────────────────────────────────────────
// JACC 封包：gzip/ungzip + unwrap/rewrap
// ──────────────────────────────────────────────

/// gzip 压缩（OS 字节置 0，与原包一致）
Uint8List _jaccGzip(Uint8List data) {
  final out = Uint8List.fromList(gzip.encode(data));
  if (out.length >= 10) {
    out[9] = 0;
  }
  return out;
}

/// gzip 解压
Uint8List _jaccGunzip(Uint8List data) {
  return Uint8List.fromList(gzip.decode(data));
}

/// 解包 JACC 响应头：返回字段 Map
Map<String, dynamic> _jaccUnwrap(Uint8List body) {
  final d = BytesData(body);
  final m = <String, dynamic>{};
  m['hdr2'] = _unpackFromB(d, 5, 2, false);
  m['magic2'] = _unpackFromB(d, 7, 2, false);
  m['cmd'] = _unpackFromB(d, 9, 2, false);
  m['z0'] = _unpackFromB(d, 11, 2, false);
  m['rqid'] = _unpackFromB(d, 13, 8, true);
  m['c531'] = _unpackFromB(d, 21, 4, true);
  m['app_int'] = _unpackFromB(d, 25, 4, true);
  m['uin'] = _unpackFromB(d, 29, 8, true);
  m['guid'] = d.slice(37, 69);
  m['b69'] = body[69];
  m['int70'] = _unpackFromB(d, 70, 4, true);
  m['gap'] = d.slice(74, 80);
  m['b80'] = body[80];
  m['s81'] = _unpackFromB(d, 81, 2, false);
  m['s83'] = _unpackFromB(d, 83, 2, false);
  m['gz'] = d.slice(89, -1);
  return m;
}

/// 解包 JACC 响应 → 内层 JCE 业务体 bytes
Uint8List _jaccUnwrapJce(Uint8List body) {
  final info = _jaccUnwrap(body);
  final gz = info['gz'] as Uint8List;
  final inner = _jaccGunzip(gz);
  // exe: inner[16:-1] —— 跳过前 16 字节信封头，去掉末尾 b'(' 标记
  if (inner.length <= 17) return inner;
  return Uint8List.sublistView(inner, 16, inner.length - 1);
}

/// 重新封包 JACC 请求：用模板 + 动态替换
Uint8List _jaccRewrap(Map<String, dynamic> info, int cmd, Uint8List jce, int rqid) {
  // inner = b'&' + pack('>i', len(jce)+17) + b'\x01' + b'\x00'*10 + jce + b'('
  final b = BytesBuilder();
  b.add([0x26]); // b'&'
  b.add(_packI32(jce.length + 17));
  b.add([0x01]);
  b.add(List.filled(10, 0));
  b.add(jce);
  b.add([0x28]); // b'('
  final inner = b.toBytes();

  // out = bytearray
  final out = BytesBuilder();
  out.add([0x13]); // b'\x13'
  out.add(_packI32(0));
  out.add(_packU16(info['hdr2'] as int));
  out.add(_packU16(info['magic2'] as int));
  out.add(_packU16(cmd));
  out.add(_packU16(info['z0'] as int));
  out.add(_packI64(rqid));
  out.add(_packI32(info['c531'] as int));
  out.add(_packI32(info['app_int'] as int));
  out.add(_packI64(info['uin'] as int));
  out.add(info['guid'] as Uint8List);
  out.add([info['b69'] as int]);
  out.add(_packI32(info['int70'] as int));
  out.add(info['gap'] as Uint8List);
  out.add([info['b80'] as int]);
  out.add(_packU16(info['s81'] as int));
  out.add(_packU16(info['s83'] as int));
  // exe: struct.pack('>i', len(inner)) + jaccGzip(inner) + b'\x03'
  out.add(_packI32(inner.length));
  out.add(_jaccGzip(inner));
  out.add([0x03]);
  // exe: struct.pack_into('>i', out, 1, len(out)) — 回填总长度到偏移 1
  final result = out.toBytes();
  final bd = ByteData.sublistView(result);
  bd.setInt32(1, result.length, Endian.big);
  return result;
}

/// 用模板构建完整的 JACC 请求包
Uint8List _jaccBuildBody(String guid, String? session, String? uid, int cmd, Uint8List bodyJce, int rqid) {
  final tpl = base64Decode(_jaccTemplateB64);
  final info = _jaccUnwrap(tpl);

  // 解析模板 JCE 获取 head members
  final jceBuf = _jaccUnwrapJce(tpl);
  final members = _jceParseStruct(jceBuf);
  final head = members[0]; // 第一个 struct 是 ResponseHead（SBEGIN）

  // 构建头成员映射 tag -> node（引用同一对象）
  final me = <int, JceNode>{};
  for (final m in head.val as List) {
    if (m is JceNode) me[m.tag] = m;
  }

  // setInt: 原地修改 node.val 并根据值范围调整 node.type
  void setInt(JceNode node, int v) {
    node.val = v;
    if (v >= -128 && v <= 127) {
      node.type = _jceByte;
    } else if (v >= -32768 && v <= 32767) {
      node.type = _jceShort;
    } else {
      node.type = _jceInt;
    }
  }

  // 替换 rqid (tag 0) 和 cmd (tag 1) —— 原地修改
  setInt(me[0]!, rqid);
  setInt(me[1]!, cmd);

  // 替换 guid (tag 4) —— 原地修改 val
  me[4]!.val = guid;

  // 处理 LoginToken (tag 5)
  JceNode loginTok;
  if (session != null && session.isNotEmpty) {
    // 构建带 session 的 LoginToken
    final oauthList = <JceNode>[
      _jceField('', 0),
      _jceField(9, 1),
      _jceBytesField(Uint8List.fromList(utf8.encode(session)), 2),
      _jceField(uid ?? '', 3),
      _jceField(1, 4),
    ];
    loginTok = JceNode(_jceList, 5,
      [JceNode(_jceSbegin, 0, oauthList, 0)], 0);
  } else {
    loginTok = JceNode(_jceZero, 5, null, 0);
  }

  // 找到 tag 5 并替换，或追加
  bool replaced = false;
  final headList = head.val as List;
  for (int i = 0; i < headList.length; i++) {
    final n = headList[i] as JceNode;
    if (n.tag == 5) {
      headList[i] = loginTok;
      replaced = true;
      break;
    }
  }
  if (!replaced) {
    headList.add(loginTok);
  }

  // 替换 body (members[1])
  members[1] = _jceBytesField(bodyJce, 1);

  // 重新编码
  final newJce = _jceEncStruct(members);
  return _jaccRewrap(info, cmd, newJce, rqid);
}

// ──────────────────────────────────────────────
// JACC 调用
// ──────────────────────────────────────────────

class _JceCallResult {
  final Uint8List? body;
  final String? err;
  _JceCallResult(this.body, this.err);
}

Future<_JceCallResult> _jceCall(
  http.Client client,
  int cmd,
  Uint8List bodyJce, {
  required String guid,
  String? session,
  String? uid,
}) async {
  final rqid = Random().nextInt(2147483646) + 1;
  final packet = _jaccBuildBody(guid, session, uid, cmd, bodyJce, rqid);

  final headers = {
    'Content-Type': 'application/octet-stream',
    'User-Agent': _jaccUa,
    'Accept': '*/*',
    'JceGodId': cmd.toString(),
    'request-id': rqid.toString(),
  };

  final url = 'https://$_jaccHost/';
  try {
    final response = await client.post(
      Uri.parse(url),
      headers: headers,
      body: packet,
    ).timeout(const Duration(seconds: 30));

    final raw = response.bodyBytes;
    if (response.statusCode != 200 || raw.isEmpty || raw[0] != 0x13) {
      return _JceCallResult(null, 'HTTP ${response.statusCode} / ${raw.length}B');
    }

    final fields = _jceParseStruct(_jaccUnwrapJce(raw));
    final headMap = <int, JceNode>{};
    for (final m in (fields[0].val as List)) {
      if (m is JceNode) headMap[m.tag] = m;
    }

    final errCodeNode = headMap[2];
    int errCode = 0;
    if (errCodeNode != null) {
      if (errCodeNode.type == _jceZero) {
        errCode = 0;
      } else {
        errCode = errCodeNode.val as int;
      }
    }
    if (errCode != 0) {
      return _JceCallResult(null, 'ResponseHead.errCode=$errCode');
    }

    // 找 body (tag 1, type BYTES)
    for (final f in fields) {
      if (f.tag == 1 && f.type == _jceBytes) {
        // val = [pad, n, raw]，取 raw
        final raw = (f.val as List)[2] as Uint8List;
        return _JceCallResult(raw, null);
      }
    }
    return _JceCallResult(null, '响应没有 body');
  } catch (e) {
    if (e.toString().contains('解包')) {
      return _JceCallResult(null, '解包失败：$e');
    }
    return _JceCallResult(null, '请求异常：$e');
  }
}

// ──────────────────────────────────────────────
// 构建 App 登录/续期请求体（59986/59987 共用）
// ──────────────────────────────────────────────

Uint8List _jceBuildAppAuthBody(int etype, String openid, String guid,
    String access, String refresh, String code) {
  // oauth = SBEGIN(1, ['', openid, access, refresh, code, ZERO(5,None)])
  final oauth = JceNode(_jceSbegin, 1, [
    _jceField('', 0),
    _jceField(openid, 1),
    _jceField(access, 2),
    _jceField(refresh, 3),
    _jceField(code, 4),
    JceNode(_jceZero, 5, null, 0),
  ], 0);

  // token = SBEGIN(0, [jceField(etype, 0), oauth])
  final token = JceNode(_jceSbegin, 0, [
    _jceField(etype, 0),
    oauth,
  ], 0);

  // dev = SBEGIN(1, [jceField(8, 0), '', guid, JACC_DEVID, JACC_DEVUA])
  final dev = JceNode(_jceSbegin, 1, [
    _jceField(8, 0),
    _jceField('', 1),
    _jceField(guid, 2),
    _jceField(_jaccDevid, 3),
    _jceField(_jaccDevua, 4),
  ], 0);

  // 最终结构: jceEncStruct([LIST(0, [token]), dev])
  // exe: JceNode(JCE_LIST, 0, [token]) 作为 struct 第一个成员，dev 作为第二个
  return _jceEncStruct([
    JceNode(_jceList, 0, [token], 0),
    dev,
  ]);
}

// ──────────────────────────────────────────────
// 解析 App 登录/续期响应体 → Map
// ──────────────────────────────────────────────

Map<String, dynamic> _jceParseAuthBody(Uint8List? raw) {
  final out = <String, dynamic>{
    'ret': 0, 'msg': '', 'openid': '', 'access_token': '',
    'refresh_token': '', 'access_ttl': 0, 'vuserid': '',
    'vusession': '', 'session_ttl': 0,
  };
  if (raw == null) return out;

  final sub = _jceParseStruct(raw);

  // node(tag): 遍历 sub 找 m.tag == tag；ZERO 返回 null，否则返回 val
  dynamic nodeVal(int tag) {
    for (final m in sub) {
      if (m is JceNode && m.tag == tag) {
        if (m.type == _jceZero) return null;
        return m.val;
      }
    }
    return null;
  }

  // tag 0 = ret, tag 1 = msg
  out['ret'] = nodeVal(0) ?? 0;
  out['msg'] = nodeVal(1) ?? '';

  // 遍历 sub 找 tag 2 SBEGIN（认证信息）
  for (final m in sub) {
    if (m is JceNode && m.tag == 2 && m.type == _jceSbegin && m.val is List) {
      // 在 m.val 中找 tag 1 的内层 SBEGIN
      for (final c in m.val as List) {
        if (c is JceNode && c.tag == 1 && c.type == _jceSbegin && c.val is List) {
          final g = <int, JceNode>{};
          for (final x in c.val as List) {
            if (x is JceNode) g[x.tag] = x;
          }
          dynamic pick(int tag, dynamic def) {
            final n = g[tag];
            if (n == null || n.type == _jceZero) return def;
            return n.val;
          }
          out['openid'] = pick(1, out['openid']);
          out['access_token'] = pick(2, out['access_token']);
          out['refresh_token'] = pick(3, out['refresh_token']);
          out['access_ttl'] = pick(5, out['access_ttl']);
          break;
        }
      }
      break;
    }
  }

  // 遍历 sub 找 tag 3 SBEGIN（会话信息）
  // exe 直接遍历 m.val 建映射，不找内层 SBEGIN
  for (final m in sub) {
    if (m is JceNode && m.tag == 3 && m.type == _jceSbegin && m.val is List) {
      final g = <int, JceNode>{};
      for (final x in m.val as List) {
        if (x is JceNode) g[x.tag] = x;
      }
      dynamic pick(int tag, dynamic def) {
        final n = g[tag];
        if (n == null || n.type == _jceZero) return def;
        return n.val;
      }
      out['vuserid'] = pick(0, out['vuserid'])?.toString() ?? '';
      out['vusession'] = pick(1, out['vusession']) ?? '';
      out['session_ttl'] = pick(2, out['session_ttl']);
      break;
    }
  }

  return out;
}

// ──────────────────────────────────────────────
// GUID 管理
// ──────────────────────────────────────────────

String _buildGuid() {
  final r = Random();
  final hex = List.generate(32, (_) => '0123456789abcdef'[r.nextInt(16)]).join();
  return hex;
}

bool _isAppGuid(String guid) {
  if (guid.length != 32) return false;
  return guid.split('').every((c) => '0123456789abcdef'.contains(c));
}

Future<String> _loadGuid() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final guid = prefs.getString('ysp_app_guid') ?? '';
    if (_isAppGuid(guid)) return guid;
  } catch (_) {}
  return '';
}

Future<void> _saveGuid(String guid) async {
  if (!_isAppGuid(guid)) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ysp_app_guid', guid);
  } catch (_) {}
}

Future<String> _stableGuid(String seed) async {
  var guid = await _loadGuid();
  if (guid.isEmpty) {
    if (_isAppGuid(seed)) {
      guid = seed;
    } else {
      guid = _buildGuid();
    }
    await _saveGuid(guid);
  }
  return guid;
}

// ──────────────────────────────────────────────
// 公开 API
// ──────────────────────────────────────────────

class JaccLoginResult {
  final bool success;
  final String msg;
  final String err;
  final String vuserid;
  final String vusession;
  final String accessToken;
  final String refreshToken;
  final String yspopenid;
  final String nickname;
  final int? endtime;

  JaccLoginResult({
    required this.success,
    this.msg = '',
    this.err = '',
    this.vuserid = '',
    this.vusession = '',
    this.accessToken = '',
    this.refreshToken = '',
    this.yspopenid = '',
    this.nickname = '',
    this.endtime,
  });
}

class JaccClient {
  String _guid = '';
  String get guid => _guid;

  final http.Client _client = http.Client();

  /// 发送短信验证码（App 通道 24680）
  Future<JaccLoginResult> sendSms(String phone) async {
    if (phone.length != 11 || !phone.startsWith('1')) {
      return JaccLoginResult(success: false, err: '请输入正确的 11 位手机号');
    }

    _guid = await _stableGuid('');
    if (!_isAppGuid(_guid)) {
      return JaccLoginResult(success: false, err: '缺少 32 位 guid');
    }

    final phoneStr = phone.startsWith('+') ? phone : '+86$phone';

    // 构建 24680 请求体
    final bodyJce = _jceEncStruct([
      _jceField(_mobileAppId, 0),
      _jceField(phoneStr, 1),
      _jceField('', 2),
      _jceField('ONE', 3),
      _jceField('86', 6),
    ]);

    final res = await _jceCall(_client, _cmdGetCode, bodyJce, guid: _guid);
    if (res.body == null) {
      return JaccLoginResult(success: false, err: res.err ?? '请求失败');
    }

    final fields = _jceParseStruct(res.body!);
    int ret = 0;
    for (final m in fields) {
      if (m.tag == 0 && m.type != _jceZero) {
        ret = m.val as int;
      }
    }

    if (ret == 0) {
      return JaccLoginResult(success: true, msg: '验证码已下发');
    }
    return JaccLoginResult(success: false, err: 'retCode=$ret');
  }

  /// 提交短信验证码登录（App 通道 59986）+ 续期自检（59987）
  Future<JaccLoginResult> verifySms(String phone, String smsCode) async {
    if (smsCode.trim().isEmpty) {
      return JaccLoginResult(success: false, err: '短信验证码不能为空');
    }

    _guid = await _stableGuid('');
    if (!_isAppGuid(_guid)) {
      return JaccLoginResult(success: false, err: '缺少 32 位 guid');
    }

    final phoneStr = phone.startsWith('+') ? phone : '+86$phone';

    // 构建 59986 请求体
    final bodyJce = _jceBuildAppAuthBody(
      _etokenMobile, phoneStr, _guid, '', '', smsCode.trim(),
    );

    final res = await _jceCall(_client, _cmdNewLogin, bodyJce, guid: _guid);
    if (res.body == null) {
      return JaccLoginResult(success: false, err: 'App 登录请求失败：${res.err}');
    }

    final info = _jceParseAuthBody(res.body!);
    if (info['ret'] != 0) {
      return JaccLoginResult(
        success: false,
        err: 'App 登录失败 retCode=${info['ret']} ${info['msg']}',
      );
    }

    final openid = info['openid'] as String;
    final accessToken = info['access_token'] as String;
    final refreshToken = info['refresh_token'] as String;
    final vusession = info['vusession'] as String;
    final vuserid = info['vuserid'] as String;
    final sessionTtl = info['session_ttl'] as int;

    if (vusession.isEmpty && refreshToken.isEmpty) {
      return JaccLoginResult(success: false, err: 'App 登录响应里没拿到 vusession/refresh_token');
    }

    // 续期自检：立即用 59987 验证票据能否续期
    bool renewOk = false;
    String renewErr = '';
    try {
      final renewBody = _jceBuildAppAuthBody(
        _etokenMobile, openid, _guid, accessToken, refreshToken, '',
      );
      final renewRes = await _jceCall(_client, _cmdNewRefresh, renewBody, guid: _guid);
      if (renewRes.body != null) {
        final renewInfo = _jceParseAuthBody(renewRes.body!);
        if (renewInfo['ret'] == 0) {
          renewOk = true;
        } else {
          renewErr = 'retCode=${renewInfo['ret']} ${renewInfo['msg']}';
        }
      } else {
        renewErr = renewRes.err ?? '未知原因';
      }
    } catch (e) {
      renewErr = e.toString();
    }

    final now = (DateTime.now().millisecondsSinceEpoch ~/ 1000);
    final endtime = sessionTtl > 0 ? now + sessionTtl : null;

    return JaccLoginResult(
      success: true,
      msg: renewOk
        ? '登录成功（App 通道；已通过续期自检）'
        : '登录成功（App 通道），但续期自检未通过：$renewErr',
      vuserid: vuserid,
      vusession: vusession,
      accessToken: accessToken,
      refreshToken: refreshToken,
      yspopenid: openid,
      endtime: endtime,
    );
  }

  /// 构建完整 Cookie 字符串
  static String buildFinalCookie({
    required JaccLoginResult login,
    required String guid,
  }) {
    // 完全对齐 exe dumpCookieString() 输出
    // appLogin setCookie 的顺序: openid, access_token, accesstoken, refresh_token,
    //   refreshtoken, vusession, vuserid, expiretime, endtime, vplatform
    // normalizeCookies 补 guid
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final ttl = login.endtime != null ? login.endtime! - now : 0;
    final parts = <String>[
      'openid=${login.yspopenid}',
      'access_token=${login.accessToken}',
      'accesstoken=${login.accessToken}',
      'refresh_token=${login.refreshToken}',
      'refreshtoken=${login.refreshToken}',
      'vusession=${login.vusession}',
      'vuserid=${login.vuserid}',
      'expiretime=$ttl',
      'endtime=${login.endtime ?? now}',
      'vplatform=3',
      'guid=$guid',
    ];
    return parts.join('; ');
  }

  void dispose() {
    _client.close();
  }
}
