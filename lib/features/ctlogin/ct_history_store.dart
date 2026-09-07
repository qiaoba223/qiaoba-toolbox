import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 电信登录助手 — 历史记录存储
/// 字段结构与原版一致: [{phone, androidId, remark, at}]
class CtHistoryItem {
  final String phone;
  final String androidId;
  final String remark;
  final int at;

  CtHistoryItem({
    required this.phone,
    required this.androidId,
    required this.remark,
    required this.at,
  });

  factory CtHistoryItem.fromJson(Map<String, dynamic> j) => CtHistoryItem(
        phone: j['phone'] ?? '',
        androidId: j['androidId'] ?? '',
        remark: j['remark'] ?? '密码',
        at: j['at'] ?? 0,
      );

  Map<String, dynamic> toJson() =>
      {'phone': phone, 'androidId': androidId, 'remark': remark, 'at': at};
}

class CtHistoryStore {
  static const _key = 'ct_history';

  static Future<List<CtHistoryItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key) ?? '[]';
    try {
      final arr = jsonDecode(raw) as List;
      return arr
          .map((e) => CtHistoryItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<bool> contains(String phone) async {
    final list = await load();
    return list.any((i) => i.phone == phone);
  }

  /// 去重保存（新的在前，最多 30 条）
  static Future<void> save(
      String phone, String androidId, String remark) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await load();
    final filtered = list.where((i) => i.phone != phone).toList();
    final next = [
      CtHistoryItem(
        phone: phone,
        androidId: androidId,
        remark: remark,
        at: DateTime.now().millisecondsSinceEpoch,
      ),
      ...filtered,
    ].take(30).map((e) => e.toJson()).toList();
    await prefs.setString(_key, jsonEncode(next));
  }

  static Future<void> delete(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await load();
    final filtered = list.where((i) => i.phone != phone).toList();
    await prefs.setString(
        _key, jsonEncode(filtered.map((e) => e.toJson()).toList()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, '[]');
  }
}

/// 剪贴板快捷写入
Future<void> copyText(String text, [String toast = '已复制']) async {
  await Clipboard.setData(ClipboardData(text: text));
}
