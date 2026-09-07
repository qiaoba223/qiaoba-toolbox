import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/theme/app_theme.dart';

/// 顶象安全验证码轻量弹窗 — 纯净卡片形态（精准贴合验证码图片尺寸，去除多余外框与悬空叉号）
class DxCaptchaDialog extends StatefulWidget {
  final ValueChanged<String> onSuccess;

  const DxCaptchaDialog({super.key, required this.onSuccess});

  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      barrierColor: Colors.black54,
      barrierDismissible: true,
      builder: (ctx) => DxCaptchaDialog(
        onSuccess: (token) => Navigator.of(ctx).pop(token),
      ),
    );
  }

  @override
  State<DxCaptchaDialog> createState() => _DxCaptchaDialogState();
}

class _DxCaptchaDialogState extends State<DxCaptchaDialog> {
  WebViewController? _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    final isDark = ThemeController.instance.isDark();
    final ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _loading = false);
        },
      ))
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: (msg) {
          try {
            final data = jsonDecode(msg.message) as Map<String, dynamic>;
            final action = data['action'] as String? ?? '';
            if (action == 'success') {
              final token = data['token'] as String? ?? '';
              if (token.isNotEmpty) {
                widget.onSuccess(token);
              }
            } else if (action == 'close') {
              if (mounted) Navigator.of(context).pop();
            }
          } catch (_) {}
        },
      );

    final html = _buildHtml(isDark);
    ctrl.loadHtmlString(html, baseUrl: 'https://hdgateway.zto.com/');
    _controller = ctrl;
  }

  String _buildHtml(bool isDark) {
    final themeClass = isDark ? 'dark' : 'light';

    return '''
<!DOCTYPE html>
<html lang="zh-CN" class="$themeClass">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
<script src="https://cdn.dingxiang-inc.com/ctu-group/captcha-ui/v5/index.js" crossorigin="anonymous"></script>
<style>
  * {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
    -webkit-tap-highlight-color: transparent;
  }
  html, body {
    width: 100%;
    height: 100%;
    background-color: transparent;
    overflow: hidden;
    display: flex;
    justify-content: center;
    align-items: center;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  }
  #dxMount {
    width: 300px;
    height: 295px;
    display: flex;
    justify-content: center;
    align-items: center;
    position: relative;
  }
  /* 让顶象卡片居中紧贴，去除负 margin */
  .dx_captcha {
    position: static !important;
    margin: 0 auto !important;
    box-shadow: 0 12px 32px rgba(0, 0, 0, 0.28) !important;
    border-radius: 16px !important;
  }
  /* 彻底去除悬空在右上方的多余小叉号，避免出现多余杂乱按键 */
  .dx_captcha_basic_tr-btn-close {
    display: none !important;
  }
  /* 隐藏顶象内部的全屏蒙层，交给 Flutter 原生模态蒙层控制 */
  .dx_captcha_loading_overlay {
    display: none !important;
  }
</style>
</head>
<body>
<div id="dxMount"></div>
<script>
  window.onload = function() {
    try {
      var cap = _dx.Captcha(document.getElementById('dxMount'), {
        appId: '12b955c66f4182ea4c3566592b1d87be',
        apiServer: 'https://cap-8.dingxiang-inc.com',
        style: 'popup',
        width: 300,
        success: function(token) {
          if (window.FlutterBridge && window.FlutterBridge.postMessage) {
            window.FlutterBridge.postMessage(JSON.stringify({action: 'success', token: token}));
          }
        },
        fail: function(err) {},
        hide: function() {
          if (window.FlutterBridge && window.FlutterBridge.postMessage) {
            window.FlutterBridge.postMessage(JSON.stringify({action: 'close'}));
          }
        }
      });
      cap.show();
    } catch(e) {
      console.error(e);
    }
  };
</script>
</body>
</html>
''';
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    // 精确等于顶象验证码卡片的尺寸（宽 306，高 300），上下左右无任何多余空框与留白
    final cardWidth = min(screenSize.width * 0.90, 306.0);
    const cardHeight = 300.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      elevation: 0,
      child: Center(
        child: SizedBox(
          width: cardWidth,
          height: cardHeight,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_controller != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: WebViewWidget(controller: _controller!),
                ),
              if (_loading)
                Container(
                  width: 140,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.75),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        '正在加载验证码...',
                        style: TextStyle(fontSize: 12, color: Colors.white),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
