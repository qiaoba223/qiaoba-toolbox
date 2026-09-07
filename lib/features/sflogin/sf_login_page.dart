import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme/app_theme.dart';
import 'sf_gateway.dart';
import 'sf_history_store.dart';

/// 顺丰登录助手 — 官方 H5 WebView 内嵌方案
///
/// 设计说明：
///   顺丰 App 的登录/改密风控参数（riskStr / riskInfo）由顺丰原生 SDK 生成，
///   纯客户端无法计算。因此本页面内嵌顺丰官方 H5（ccas-h5.sf-express.com），
///   用户在真实风控环境完成登录/改密，App 侧自动提取登录后的完整 Cookie（CK）
///   与用户信息，并可沉淀到历史记录。
class SfLoginPage extends StatefulWidget {
  const SfLoginPage({super.key});

  @override
  State<SfLoginPage> createState() => _SfLoginPageState();
}

class _SfLoginPageState extends State<SfLoginPage> {
  WebViewController? _controller;

  /// 当前主模式：0=登录, 1=忘记密码
  int _mode = 0;

  bool _loading = true;
  bool _capturing = false;
  SfCookieInfo? _captured;
  List<SfHistoryItem> _history = const [];

  /// 最近一次顺丰域请求携带的 Cookie 头（可含 HttpOnly 的 sessionId）
  String _headerCookie = '';

  @override
  void initState() {
    super.initState();
    _initWebView();
    _startPolling();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final list = await SfHistoryStore.load();
    if (mounted) setState(() => _history = list);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  void _initWebView() {
    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setUserAgent(SfGateway.mobileUA)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
          _hookBridge();
          _tryCapture();
        },
        onWebResourceError: (e) {
          if (mounted && e.isForMainFrame == true) {
            setState(() => _loading = false);
          }
        },
        onNavigationRequest: (request) {
          // 顺丰域内跳转时确保网络钩子已注入
          if (SfGateway.isSfHost(request.url)) {
            _captureFromRequest();
          }
          return NavigationDecision.navigate;
        },
      ))
      // 顺丰 H5 会向 ReactNativeWebView 回传登录/用户事件，捕获之
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: (msg) {
          _onBridgeMessage(msg.message);
        },
      );

    ctrl.loadRequest(Uri.parse(_entryUrl));
    _controller = ctrl;
  }

  String get _entryUrl =>
      _mode == 1 ? SfGateway.forgotEntry : SfGateway.loginEntry;

  /// 注入到顺丰页面：桥接 ReactNativeWebView 回传
  Future<void> _hookBridge() async {
    final ctrl = _controller;
    if (ctrl == null) return;
    const js = '''
(function(){
  if (window.__sfHooked) return; window.__sfHooked = true;
  try {
    window.ReactNativeWebView = {
      postMessage: function(s){ try { FlutterBridge.postMessage(s); } catch(e){} }
    };
  } catch(e){}
})();
''';
    try {
      await ctrl.runJavaScript(js);
    } catch (_) {}
    await _captureFromRequest();
  }

  /// 探测登录态并提取 Cookie（每 2 秒轮询一次，直到拿到完整凭证）
  Timer? _pollTimer;

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _tryCapture());
  }

  /// 通过 JS 钩子抓取顺丰域请求的 Cookie 头（含 HttpOnly sessionId）
  Future<void> _captureFromRequest() async {
    final ctrl = _controller;
    if (ctrl == null) return;
    const js = r'''
(function(){
  if (window.__sfNetHooked) return; window.__sfNetHooked = true;
  function report(c){ try { FlutterBridge.postMessage(JSON.stringify(
    {method:'cookie', cookie:c})); } catch(e){} }
  // 钩 fetch
  var of = window.fetch;
  if (of) {
    window.fetch = function(){
      try {
        var h = arguments[1] && arguments[1].headers;
        if (h) {
          var c = (h['Cookie'] || h['cookie'] ||
                   (h.get && h.get('Cookie')));
          if (c) report(c);
        }
      } catch(e){}
      return of.apply(this, arguments);
    };
  }
  // 钩 XHR
  var ox = XMLHttpRequest.prototype.setRequestHeader;
  XMLHttpRequest.prototype.setRequestHeader = function(k,v){
    try { if (String(k).toLowerCase()==='cookie') report(v); } catch(e){}
    return ox.apply(this, arguments);
  };
})();
''';
    try {
      await ctrl.runJavaScript(js);
    } catch (_) {}
  }

  Future<void> _onBridgeMessage(String message) async {
    try {
      final data = jsonDecode(message);
      if (data is Map) {
        final method = data['method']?.toString() ?? '';
        if (method == 'cookie') {
          final c = data['cookie']?.toString() ?? '';
          if (c.isNotEmpty) {
            _headerCookie = c;
            _tryCapture();
          }
          return;
        }
        // 顺丰 H5 完成后会回传 backToBefore 等事件，触发一次抓取
        if (method.isNotEmpty) _tryCapture();
      }
    } catch (_) {}
  }

  Future<void> _tryCapture() async {
    final ctrl = _controller;
    if (ctrl == null || _capturing) return;
    _capturing = true;
    try {
      // 顺丰 H5 登录成功后，sessionId 可能为 HttpOnly，document.cookie 取不到。
      // 因此通过页面内的 token/check 接口回读登录态与用户信息，
      // 再结合 Cookie 头的拦截结果（_headerCookie）拼接出完整 CK。
      final js = '''
(function(){
  try {
    return JSON.stringify({
      cookie: document.cookie || '',
      url: location.href
    });
  } catch(e){ return '{}'; }
})();
''';
      final raw = await ctrl.runJavaScriptReturningResult(js);
      var s = raw.toString();
      if (s.startsWith('"') && s.endsWith('"')) {
        s = s.substring(1, s.length - 1);
      }
      s = s.replaceAll(r'\"', '"').replaceAll(r'\\', '');
      String cookieStr = '';
      try {
        final obj = jsonDecode(s) as Map<String, dynamic>;
        cookieStr = obj['cookie']?.toString() ?? '';
      } catch (_) {
        cookieStr = s;
      }

      // 合并由请求头拦截到的 Cookie（可含 HttpOnly 的 sessionId）
      final buf = StringBuffer(cookieStr);
      if (_headerCookie.isNotEmpty) {
        for (final part in _headerCookie.split(';')) {
          final kv = part.trim();
          if (kv.isEmpty) continue;
          final name = kv.split('=').first;
          if (!buf.toString().contains('$name=')) {
            buf.write('; $kv');
          }
        }
      }

      final info = SfGateway.parseCookie(buf.toString());

      // 若 Cookie 完整，直接采用；否则尝试用手机号兜底（H5 已登录时 uid 必存在）
      if (info.isComplete) {
        if (mounted) {
          setState(() => _captured = info);
        }
        await _persist(info);
        _pollTimer?.cancel();
      }
    } catch (_) {
    } finally {
      _capturing = false;
    }
  }

  Future<void> _persist(SfCookieInfo info) async {
    await SfHistoryStore.save(
      mobile: info.loginMobile,
      sessionId: info.sessionId,
      userId: info.loginUserId,
      ck: info.ck,
    );
    await _loadHistory();
    if (mounted) _toast('🎉 已捕获登录凭证: ${info.maskedMobile}');
  }

  void _switchMode(int m) {
    setState(() {
      _mode = m;
      _loading = true;
      _captured = null;
    });
    _initWebView();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ThemeController.instance.isDark(context);
    ThemeController.applySystemOverlay(isDark);

    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: isDark ? AppTheme.darkCard : Colors.white,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        appBar: AppBar(
          systemOverlayStyle: overlayStyle,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          title: Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFE63946), Color(0xFFC1121F)]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text('SF',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 13)),
              ),
            ),
            const SizedBox(width: 10),
            const Text('顺丰登录助手'),
          ]),
          actions: [
            IconButton(
              tooltip: '刷新',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () {
                setState(() => _loading = true);
                _controller?.reload();
              },
            ),
          ],
        ),
        body: Column(
          children: [
            _buildModeBar(isDark),
            _buildStatusBanner(isDark),
            Expanded(
              child: Stack(
                children: [
                  if (_controller != null)
                    WebViewWidget(controller: _controller!),
                  if (_loading)
                    const Center(
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                ],
              ),
            ),
            _buildCapturedPanel(isDark),
            _buildHistoryBar(isDark),
          ],
        ),
      ),
    );
  }

  /// 顶部模式切换：登录 / 忘记密码
  Widget _buildModeBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: isDark ? AppTheme.darkCard : Colors.white,
      child: Row(children: [
        Expanded(child: _modeBtn('账号登录', 0, isDark)),
        const SizedBox(width: 8),
        Expanded(child: _modeBtn('忘记密码', 1, isDark)),
      ]),
    );
  }

  Widget _modeBtn(String title, int idx, bool isDark) {
    final active = _mode == idx;
    return GestureDetector(
      onTap: () => _switchMode(idx),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 36,
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFFE63946)
              : (isDark ? AppTheme.darkInputFill : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: active
                  ? Colors.white
                  : (isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub),
            ),
          ),
        ),
      ),
    );
  }

  /// 顶部说明条
  Widget _buildStatusBanner(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: isDark ? const Color(0xFF1A2236) : const Color(0xFFFFF5F5),
      child: Row(children: [
        const Icon(Icons.info_outline_rounded,
            size: 14, color: Color(0xFFE63946)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '顺丰官方安全环境，完成登录后自动捕获凭证',
            style: TextStyle(
              fontSize: 11.5,
              color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub,
            ),
          ),
        ),
      ]),
    );
  }

  /// 凭证展示面板
  Widget _buildCapturedPanel(bool isDark) {
    final info = _captured;
    if (info == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        border: Border(
          top: BorderSide(
              color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.verified_rounded,
                size: 16, color: AppTheme.success),
            const SizedBox(width: 6),
            Text('登录成功 · ${info.maskedMobile}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: isDark
                        ? AppTheme.darkTextMain
                        : AppTheme.lightTextMain)),
          ]),
          const SizedBox(height: 8),
          _kvRow('sessionId', info.sessionId, isDark),
          _kvRow('UID', info.loginUserId, isDark),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () async {
                  await sfCopy(info.ck);
                  _toast('已复制完整 CK');
                },
                icon: const Icon(Icons.copy_rounded, size: 16),
                label: const Text('复制完整 CK',
                    style: TextStyle(fontSize: 13)),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE63946),
                  minimumSize: const Size.fromHeight(40),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await sfCopy(
                      '${info.loginMobile}#${info.loginUserId}');
                  _toast('已复制 手机号#UID');
                },
                icon: const Icon(Icons.copy_all_rounded, size: 16),
                label:
                    const Text('手机号#UID', style: TextStyle(fontSize: 13)),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _kvRow(String k, String v, bool isDark) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 74,
            child: Text(k,
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? AppTheme.darkTextMuted
                        : AppTheme.lightTextMuted)),
          ),
          Expanded(
            child: Text(
              v.isEmpty ? '—' : v,
              style: TextStyle(
                  fontSize: 11.5,
                  color:
                      isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub),
            ),
          ),
        ]),
      );

  /// 底部历史记录栏
  Widget _buildHistoryBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        border: Border(
          top: BorderSide(
              color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
        ),
      ),
      child: Row(children: [
        Text('历史记录',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color:
                    isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub)),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: const Color(0xFFE63946).withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('${_history.length}',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFE63946))),
        ),
        const Spacer(),
        PopupMenuButton<String>(
          enabled: _history.isNotEmpty,
          tooltip: '复制全部',
          padding: EdgeInsets.zero,
          splashRadius: 20,
          onSelected: (v) async {
            if (_history.isEmpty) return;
            if (v == 'ck') {
              final all = _history.map((e) => e.ck).join('\n');
              await sfCopy(all);
              _toast('已复制全部 CK（${_history.length} 条）');
            } else {
              final all = _history
                  .map((e) => '${e.mobile}#${e.userId}')
                  .join('\n');
              await sfCopy(all);
              _toast('已复制全部 手机号#UID（${_history.length} 条）');
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'ck',
              height: 44,
              child: Text('复制全部 CK', style: TextStyle(fontSize: 13)),
            ),
            const PopupMenuItem(
              value: 'uid',
              height: 44,
              child: Text('复制全部 手机号#UID', style: TextStyle(fontSize: 13)),
            ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.copy_all_rounded, size: 15, color: Color(0xFFE63946)),
              SizedBox(width: 4),
              Text('复制全部',
                  style: TextStyle(fontSize: 12, color: Color(0xFFE63946))),
              Icon(Icons.arrow_drop_down_rounded,
                  size: 18, color: Color(0xFFE63946)),
            ]),
          ),
        ),
        TextButton.icon(
          onPressed: _history.isEmpty
              ? null
              : () async {
                  await SfHistoryStore.clear();
                  await _loadHistory();
                  _toast('历史记录已清空');
                },
          icon: const Icon(Icons.delete_outline,
              size: 16, color: AppTheme.danger),
          label: const Text('清空',
              style: TextStyle(fontSize: 12, color: AppTheme.danger)),
          style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32)),
        ),
      ]),
    );
  }
}
