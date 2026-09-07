import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 顺丰登录助手 — 历史记录存储
/// 字段结构: [{mobile, sessionId, userId, ck, remark, at}]
class SfHistoryItem {
  final String mobile;
  final String sessionId;
  final String userId;
  final String ck;
  final String remark;
  final int at;

  SfHistoryItem({
    required this.mobile,
    required this.sessionId,
    required this.userId,
    required this.ck,
    required this.remark,
    required this.at,
  });

  factory SfHistoryItem.fromJson(Map<String, dynamic> j) => SfHistoryItem(
        mobile: j['mobile'] ?? '',
        sessionId: j['sessionId'] ?? '',
        userId: j['userId'] ?? '',
        ck: j['ck'] ?? '',
        remark: j['remark'] ?? '顺丰',
        at: j['at'] ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'mobile': mobile,
        'sessionId': sessionId,
        'userId': userId,
        'ck': ck,
        'remark': remark,
        'at': at,
      };

  /// 掩码手机号
  String get maskedMobile {
    if (mobile.length != 11) return mobile;
    return '${mobile.substring(0, 3)}****${mobile.substring(7)}';
  }
}

class SfHistoryStore {
  static const _key = 'sf_history';

  static Future<List<SfHistoryItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key) ?? '[]';
    try {
      final arr = jsonDecode(raw) as List;
      return arr
          .map((e) => SfHistoryItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 去重保存（新的在前，最多 30 条）；按手机号去重
  static Future<void> save({
    required String mobile,
    required String sessionId,
    required String userId,
    required String ck,
    String remark = '顺丰',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await load();
    final filtered = list.where((i) => i.mobile != mobile).toList();
    final next = [
      SfHistoryItem(
        mobile: mobile,
        sessionId: sessionId,
        userId: userId,
        ck: ck,
        remark: remark,
        at: DateTime.now().millisecondsSinceEpoch,
      ),
      ...filtered,
    ].take(30).map((e) => e.toJson()).toList();
    await prefs.setString(_key, jsonEncode(next));
  }

  static Future<void> delete(String mobile) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await load();
    final filtered = list.where((i) => i.mobile != mobile).toList();
    await prefs.setString(
        _key, jsonEncode(filtered.map((e) => e.toJson()).toList()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, '[]');
  }
}

/// 剪贴板快捷写入
Future<void> sfCopy(String text, [String toast = '已复制']) async {
  await Clipboard.setData(ClipboardData(text: text));
}
