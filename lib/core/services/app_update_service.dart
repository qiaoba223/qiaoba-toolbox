import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'proxy_config.dart';

/// 应用内一键更新服务 — 多通道高可用（镜像加速 + 列表兜底）
class AppUpdateService {
  static const String repo = 'qiaoba223/qiaoba-toolbox';

  /// 动态获取当前应用安装的真实语义化版本
  static Future<String> getAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return '3.8.5';
    }
  }

  /// 检查更新：支持多节点智能轮询与代理穿透
  Future<Map<String, String>?> checkUpdate() async {
    final currentVersion = await getAppVersion();
    final mode = await ProxyConfig.getMode();

    Map<String, dynamic>? releaseData;

    // 优先候选 URL 列表（含镜像加速节点与多端点兜底）
    final candidateUrls = <String>[
      'https://gh-proxy.com/https://api.github.com/repos/$repo/releases/latest',
      'https://api.github.com/repos/$repo/releases/latest',
      'https://gh-proxy.com/https://api.github.com/repos/$repo/releases?per_page=3',
      'https://api.github.com/repos/$repo/releases?per_page=3',
    ];

    for (final urlStr in candidateUrls) {
      try {
        if (mode == ProxyMode.http) {
          final val = await ProxyConfig.getValue();
          if (val.isNotEmpty) {
            var p = val;
            if (!p.contains('://')) p = 'http://$p';
            final uri = Uri.parse(p);
            final hc = HttpClient();
            hc.badCertificateCallback = (c, h, pt) => true;
            hc.connectionTimeout = const Duration(seconds: 8);
            hc.findProxy = (u) => 'PROXY ${uri.host}:${uri.port == 0 ? 8080 : uri.port}';

            final req = await hc.getUrl(Uri.parse(urlStr));
            req.headers.set('Accept', 'application/vnd.github+json');
            req.headers.set('User-Agent', 'qiaoba-toolbox');
            final resp = await req.close();
            if (resp.statusCode == 200) {
              final text = await resp.transform(utf8.decoder).join();
              releaseData = _parseReleaseJson(text);
              hc.close();
              if (releaseData != null) break;
            }
            hc.close();
          }
        } else {
          // 直连或通过已包含加速前缀的镜像节点
          final resp = await http.get(
            Uri.parse(urlStr),
            headers: {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'qiaoba-toolbox',
            },
          ).timeout(const Duration(seconds: 8));

          if (resp.statusCode == 200) {
            releaseData = _parseReleaseJson(resp.body);
            if (releaseData != null) break;
          }
        }
      } catch (e) {
        debugPrint('Update candidate failed on $urlStr: $e');
      }
    }

    if (releaseData == null) return null;

    final tagName = (releaseData['tag_name'] ?? '') as String;
    final latest = tagName.replaceFirst(RegExp(r'^v'), '');

    if (!_isNewer(latest, currentVersion)) {
      return null;
    }

    String apkUrl = '';
    String ipaUrl = '';
    for (final asset in (releaseData['assets'] as List? ?? [])) {
      final name = (asset['name'] ?? '').toString().toLowerCase();
      if (name.endsWith('.apk')) {
        apkUrl = asset['browser_download_url'] ?? '';
      } else if (name.endsWith('.ipa')) {
        ipaUrl = asset['browser_download_url'] ?? '';
      }
    }
    final releaseUrl = releaseData['html_url']?.toString() ??
        'https://github.com/$repo/releases/tag/v$latest';

    return {
      'version': latest,
      'current': currentVersion,
      'notes': releaseData['body']?.toString() ?? '',
      'apkUrl': apkUrl,
      'ipaUrl': ipaUrl,
      'releaseUrl': releaseUrl,
    };
  }

  /// 统一解析 Release 对象（支持单体 latest 对象或列表数组返回）
  Map<String, dynamic>? _parseReleaseJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic> && decoded.containsKey('tag_name')) {
        return decoded;
      }
      if (decoded is List && decoded.isNotEmpty) {
        for (final item in decoded) {
          if (item is Map<String, dynamic> &&
              item['draft'] == false &&
              item.containsKey('tag_name')) {
            return item;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// 语义化版本号对比: latest > current 返回 true
  bool _isNewer(String latest, String current) {
    List<int> parse(String v) =>
        v.split(RegExp(r'[.\-+]')).map((e) => int.tryParse(e) ?? 0).toList();
    final a = parse(latest);
    final b = parse(current);
    final len = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < len; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  /// 下载 APK（支持镜像前缀 / HTTP 代理）到应用私有缓存目录，返回文件路径
  static Future<String> downloadApk(
      String url, void Function(int, int)? onProgress) async {
    final client = HttpClient();
    client.badCertificateCallback = (cert, host, port) => true;

    try {
      await ProxyConfig.applyHttpClientProxy(client);
    } catch (_) {}

    final req = await client.getUrl(Uri.parse(url));
    req.followRedirects = true;
    req.maxRedirects = 5;
    final resp = await req.close();
    if (resp.statusCode != 200) {
      throw Exception('下载失败 HTTP ${resp.statusCode}');
    }

    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/qiaoba-toolbox-update.apk');
    if (file.existsSync()) file.deleteSync();

    final sink = file.openWrite();
    final total =
        int.parse(resp.headers.value(HttpHeaders.contentLengthHeader) ?? '0');
    var received = 0;
    await for (final chunk in resp) {
      received += chunk.length;
      sink.add(chunk);
      onProgress?.call(received, total);
    }
    await sink.close();
    client.close();
    return file.path;
  }
}
