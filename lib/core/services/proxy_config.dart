import 'package:shared_preferences/shared_preferences.dart';

/// 代理模式
enum ProxyMode { direct, mirror, http }

/// 代理配置管理（gh-proxy.com 默认镜像 / 可切换 / 可删除）
class ProxyConfig {
  static const String defaultMirror = 'https://gh-proxy.com/';

  static Future<ProxyMode> getMode() async {
    final prefs = await SharedPreferences.getInstance();
    final s = prefs.getString('proxy_mode') ?? 'mirror';
    return ProxyMode.values.firstWhere(
      (e) => e.name == s,
      orElse: () => ProxyMode.mirror,
    );
  }

  static Future<String> getValue() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('proxy_value') ?? defaultMirror;
  }

  static Future<void> save(ProxyMode mode, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('proxy_mode', mode.name);
    await prefs.setString('proxy_value', value);
  }

  /// 描述文本（用于 UI 显示）
  static Future<String> describe() async {
    final mode = await getMode();
    final value = await getValue();
    switch (mode) {
      case ProxyMode.direct:
        return '直连（不用代理）';
      case ProxyMode.mirror:
        return '镜像加速: $value';
      case ProxyMode.http:
        return 'HTTP 代理: $value';
    }
  }

  /// 把 GitHub 下载 URL 按代理配置转换
  static Future<String> resolveDownloadUrl(String githubUrl) async {
    final mode = await getMode();
    final value = await getValue();
    switch (mode) {
      case ProxyMode.direct:
        return githubUrl;
      case ProxyMode.mirror:
        return value.endsWith('/') ? '$value$githubUrl' : '$value/$githubUrl';
      case ProxyMode.http:
        return githubUrl; // HTTP 代理在 HttpClient.findProxy 处理
    }
  }

  /// 给 HttpClient 应用 HTTP 代理（仅 http 模式）
  static Future<void> applyHttpClientProxy(dynamic client) async {
    final mode = await getMode();
    if (mode != ProxyMode.http) return;
    final value = await getValue();
    if (value.isEmpty) return;
    var p = value;
    if (!p.contains('://')) p = 'http://$p';
    final uri = Uri.parse(p);
    final host = uri.host;
    final port = uri.port == 0 ? 8080 : uri.port;
    client.findProxy = (u) => 'PROXY $host:$port';
  }
}
