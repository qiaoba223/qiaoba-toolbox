import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import 'jacc_client.dart';

/// 央视频CK获取页面 — JACC 原生协议直连
class YspckPage extends StatefulWidget {
  const YspckPage({super.key});

  @override
  State<YspckPage> createState() => _YspckPageState();
}

class _YspckPageState extends State<YspckPage> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  bool _sending = false;
  bool _logging = false;
  bool _smsSent = false;
  int _countdown = 0;

  JaccLoginResult? _loginResult;
  String _finalCookie = '';

  late final JaccClient _client = JaccClient();

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _copy(String text, [String msg = '已复制']) async {
    await Clipboard.setData(ClipboardData(text: text));
    _toast(msg);
  }

  Future<void> _sendSms() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.length != 11 || !phone.startsWith('1')) {
      _toast('请输入正确的 11 位手机号');
      return;
    }
    setState(() => _sending = true);
    try {
      final res = await _client.sendSms(phone);
      if (res.success) {
        setState(() {
          _smsSent = true;
          _countdown = 60;
        });
        _toast('✅ ${res.msg}');
        _startCountdown();
      } else {
        _toast('❌ ${res.msg}');
      }
    } catch (e) {
      _toast('❌ ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startCountdown() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _countdown--);
      return _countdown > 0;
    });
  }

  Future<void> _doLogin() async {
    final phone = _phoneCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    if (phone.length != 11) {
      _toast('请输入正确的 11 位手机号');
      return;
    }
    if (code.length != 6) {
      _toast('请输入 6 位验证码');
      return;
    }
    setState(() => _logging = true);
    try {
      final res = await _client.verifySms(phone, code);
      if (res.success) {
        final cookie = JaccClient.buildFinalCookie(login: res, guid: _client.guid);
        setState(() {
          _loginResult = res;
          _finalCookie = cookie;
        });
        _toast('🎉 登录成功，Cookie 已生成');
      } else {
        _toast('❌ ${res.err}');
      }
    } catch (e) {
      _toast('❌ ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _logging = false);
    }
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
              onPressed: () => Navigator.pop(context)),
          title: Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFFF6B5B), AppTheme.yspColor]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                  child: Icon(Icons.play_arrow, color: Colors.white, size: 18)),
            ),
            const SizedBox(width: 10),
            const Text('央视频CK获取'),
          ]),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            _buildInputCard(isDark),
            const SizedBox(height: 16),
            if (_loginResult != null) _buildResultCard(isDark),
          ]),
        ),
      ),
    );
  }

  Widget _buildInputCard(bool isDark) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _label('央视频手机号', isDark),
                TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    maxLength: 11,
                    decoration: const InputDecoration(
                        hintText: '请输入央视频注册手机号', counterText: '')),
                const SizedBox(height: 12),
                _label('短信验证码', isDark),
                Row(children: [
                  Expanded(
                      child: TextField(
                          controller: _codeCtrl,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          enabled: _smsSent,
                          decoration: InputDecoration(
                              hintText: _smsSent ? '6 位验证码' : '请先获取验证码',
                              counterText: ''))),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: (_sending || _countdown > 0) ? null : _sendSms,
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(110, 48)),
                    child: Text(
                        _sending
                            ? '发送中...'
                            : (_countdown > 0 ? '${_countdown}s' : '获取验证码'),
                        style: const TextStyle(fontSize: 13)),
                  ),
                ]),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _logging ? null : _doLogin,
                  style:
                      FilledButton.styleFrom(backgroundColor: AppTheme.yspColor),
                  child: _logging
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('获取 CK'),
                ),
              ]),
        ),
      );

  Widget _label(String text, bool isDark) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isDark ? AppTheme.darkTextMain : const Color(0xFF334155))),
      );

  Widget _fieldBox(String title, String value, bool isDark, {VoidCallback? onCopy}) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: isDark ? AppTheme.darkInputFill : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(title,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub)),
            if (onCopy != null)
              GestureDetector(
                onTap: onCopy,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: isDark
                          ? AppTheme.yspColor.withOpacity(0.2)
                          : AppTheme.primaryLight,
                      borderRadius: BorderRadius.circular(10)),
                  child: const Text('复制',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.yspColor)),
                ),
              ),
          ]),
          const SizedBox(height: 4),
          SelectableText(value.isEmpty ? '-' : value,
              style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: isDark ? AppTheme.darkTextMain : AppTheme.lightTextMain,
                  height: 1.4)),
        ]),
      );

  Widget _buildResultCard(bool isDark) {
    final login = _loginResult!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.check_circle,
                    color: AppTheme.success, size: 22),
                const SizedBox(width: 6),
                Text('获取成功',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? AppTheme.darkTextMain
                            : AppTheme.lightTextMain)),
              ]),
              const SizedBox(height: 4),
              if (login.nickname.isNotEmpty)
                Text('用户: ${login.nickname}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? AppTheme.darkTextMuted
                            : AppTheme.lightTextSub)),
              const SizedBox(height: 16),
              _fieldBox('完整 Cookie (vplatform=3)', _finalCookie, isDark,
                  onCopy: () => _copy(_finalCookie, 'Cookie 已复制')),
            ]),
      ),
    );
  }
}
