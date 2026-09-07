import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import 'dx_captcha_dialog.dart';
import 'zto_gateway.dart';

/// 中通会员助手 — 100% 纯 Flutter 原生渲染（0延迟秒进，仅在滑块验证时弹出轻量对话框）
class ZtoPage extends StatefulWidget {
  const ZtoPage({super.key});

  @override
  State<ZtoPage> createState() => _ZtoPageState();
}

class _ZtoPageState extends State<ZtoPage> {
  final ZtoGateway _gateway = ZtoGateway();

  // 当前主视图：0=登录, 1=注册, 2=忘记密码
  int _currentTab = 0;
  bool _obscurePwd = true;
  bool _obscureRegPwd = true;
  bool _obscureRegPwd2 = true;
  bool _obscureForgotPwd = true;
  bool _obscureForgotPwd2 = true;

  // 登录表单
  final _loginPhoneCtrl = TextEditingController();
  final _loginPwdCtrl = TextEditingController();
  bool _loggingIn = false;
  String _loginToken = '';

  // 注册表单
  final _regPhoneCtrl = TextEditingController();
  final _regCodeCtrl = TextEditingController();
  final _regPwdCtrl = TextEditingController();
  final _regPwd2Ctrl = TextEditingController();
  bool _regSubmitting = false;
  String? _regCaptchaId;
  String? _regCaptchaCode;
  bool _regCodeSending = false;
  int _regCountdown = 0;
  Timer? _regTimer;

  // 忘记密码表单
  int _forgotStep = 1; // 1=验证码, 2=重置密码, 3=完成
  final _forgotPhoneCtrl = TextEditingController();
  final _forgotCodeCtrl = TextEditingController();
  final _forgotNewPwdCtrl = TextEditingController();
  final _forgotNewPwd2Ctrl = TextEditingController();
  bool _forgotSubmitting = false;
  String? _forgotCaptchaId;
  String? _forgotCaptchaCode;
  bool _forgotCodeSending = false;
  int _forgotCountdown = 0;
  Timer? _forgotTimer;

  @override
  void dispose() {
    _gateway.close();
    _loginPhoneCtrl.dispose();
    _loginPwdCtrl.dispose();
    _regPhoneCtrl.dispose();
    _regCodeCtrl.dispose();
    _regPwdCtrl.dispose();
    _regPwd2Ctrl.dispose();
    _forgotPhoneCtrl.dispose();
    _forgotCodeCtrl.dispose();
    _forgotNewPwdCtrl.dispose();
    _forgotNewPwd2Ctrl.dispose();
    _regTimer?.cancel();
    _forgotTimer?.cancel();
    super.dispose();
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

  // ════════════════════ 登录逻辑 ════════════════════
  Future<void> _doLogin() async {
    final phone = _loginPhoneCtrl.text.trim();
    final pwd = _loginPwdCtrl.text;
    if (phone.isEmpty) {
      _toast('请输入中通手机号或账号');
      return;
    }
    if (pwd.isEmpty) {
      _toast('请输入登录密码');
      return;
    }

    setState(() {
      _loggingIn = true;
      _loginToken = '';
    });

    try {
      final res = await _gateway.login(phone, pwd);
      if (res['status'] == 'success') {
        setState(() => _loginToken = res['token'] ?? '');
        _toast('🎉 登录成功');
      } else {
        _toast('❌ ${res['message'] ?? '登录失败，请检查账号密码'}');
      }
    } catch (e) {
      _toast('网络异常: $e');
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  // ════════════════════ 注册逻辑 ════════════════════
  Future<void> _openRegCaptcha() async {
    final token = await DxCaptchaDialog.show(context);
    if (token != null && token.isNotEmpty) {
      setState(() {
        _regCaptchaId = 'dingxiang';
        _regCaptchaCode = token;
      });
      _toast('✅ 安全验证通过，请获取短信验证码');
    }
  }

  Future<void> _sendRegSms() async {
    final phone = _regPhoneCtrl.text.trim();
    if (phone.length != 11) {
      _toast('请输入有效的 11 位手机号码');
      return;
    }
    if (_regCaptchaCode == null || _regCaptchaCode!.isEmpty) {
      _toast('请先完成安全验证');
      return;
    }

    setState(() => _regCodeSending = true);
    try {
      // 预先确保拉取到最新的 captchaId
      final capRes = await _gateway.getCaptcha();
      final capId = capRes['id'] ?? _regCaptchaId ?? '';
      final res = await _gateway.sendRegisterCode(
          phone, capId, _regCaptchaCode!);
      if (res['status'] == 'success') {
        _toast('验证码已发送至手机: ${phone.substring(0, 3)}****${phone.substring(7)}');
        setState(() => _regCountdown = 60);
        _regTimer?.cancel();
        _regTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (_regCountdown <= 1) {
            t.cancel();
            if (mounted) setState(() => _regCountdown = 0);
          } else {
            if (mounted) setState(() => _regCountdown--);
          }
        });
      } else {
        _toast('❌ ${res['message'] ?? '验证码下发失败'}');
        setState(() => _regCaptchaCode = null); // 需重新滑块
      }
    } catch (e) {
      _toast('请求失败: $e');
    } finally {
      if (mounted) setState(() => _regCodeSending = false);
    }
  }

  Future<void> _doRegister() async {
    final phone = _regPhoneCtrl.text.trim();
    final code = _regCodeCtrl.text.trim();
    final pwd = _regPwdCtrl.text;
    final pwd2 = _regPwd2Ctrl.text;

    if (phone.length != 11) {
      _toast('请输入有效的 11 位手机号码');
      return;
    }
    if (code.isEmpty) {
      _toast('请输入短信验证码');
      return;
    }
    if (pwd.length < 8) {
      _toast('密码长度不能少于 8 位');
      return;
    }
    if (pwd != pwd2) {
      _toast('两次输入的密码不一致');
      return;
    }

    setState(() => _regSubmitting = true);
    try {
      final res = await _gateway.register(phone, code, pwd);
      if (res['status'] == 'success') {
        _toast('🎉 注册成功！已自动填入账号，请登录');
        setState(() {
          _currentTab = 0;
          _loginPhoneCtrl.text = phone;
          _loginPwdCtrl.text = pwd;
        });
      } else {
        _toast('❌ ${res['message'] ?? '注册失败'}');
      }
    } catch (e) {
      _toast('网络请求失败: $e');
    } finally {
      if (mounted) setState(() => _regSubmitting = false);
    }
  }

  // ════════════════════ 找回密码逻辑 ════════════════════
  Future<void> _openForgotCaptcha() async {
    final token = await DxCaptchaDialog.show(context);
    if (token != null && token.isNotEmpty) {
      setState(() {
        _forgotCaptchaId = 'dingxiang';
        _forgotCaptchaCode = token;
      });
      _toast('✅ 安全验证通过，请获取短信验证码');
    }
  }

  Future<void> _sendForgotSms() async {
    final phone = _forgotPhoneCtrl.text.trim();
    if (phone.length != 11) {
      _toast('请输入有效的 11 位手机号码');
      return;
    }
    if (_forgotCaptchaCode == null || _forgotCaptchaCode!.isEmpty) {
      _toast('请先完成安全验证');
      return;
    }

    setState(() => _forgotCodeSending = true);
    try {
      final capRes = await _gateway.getCaptcha();
      final capId = capRes['id'] ?? _forgotCaptchaId ?? '';
      final res = await _gateway.sendForgotCode(
          phone, capId, _forgotCaptchaCode!);
      if (res['status'] == 'success') {
        _toast('验证码已下发至手机号');
        setState(() => _forgotCountdown = 60);
        _forgotTimer?.cancel();
        _forgotTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (_forgotCountdown <= 1) {
            t.cancel();
            if (mounted) setState(() => _forgotCountdown = 0);
          } else {
            if (mounted) setState(() => _forgotCountdown--);
          }
        });
      } else {
        _toast('❌ ${res['message'] ?? '发送失败'}');
        setState(() => _forgotCaptchaCode = null);
      }
    } catch (e) {
      _toast('网络异常: $e');
    } finally {
      if (mounted) setState(() => _forgotCodeSending = false);
    }
  }

  Future<void> _verifyForgotCode() async {
    final phone = _forgotPhoneCtrl.text.trim();
    final code = _forgotCodeCtrl.text.trim();
    if (phone.length != 11) {
      _toast('请输入手机号码');
      return;
    }
    if (code.isEmpty) {
      _toast('请输入短信验证码');
      return;
    }

    setState(() => _forgotSubmitting = true);
    try {
      final res = await _gateway.verifyForgotCode(phone, code);
      if (res['status'] == 'success') {
        setState(() => _forgotStep = 2);
      } else {
        _toast('❌ ${res['message'] ?? '短信验证码错误'}');
      }
    } catch (e) {
      _toast('网络异常: $e');
    } finally {
      if (mounted) setState(() => _forgotSubmitting = false);
    }
  }

  Future<void> _doResetPassword() async {
    final phone = _forgotPhoneCtrl.text.trim();
    final code = _forgotCodeCtrl.text.trim();
    final pwd = _forgotNewPwdCtrl.text;
    final pwd2 = _forgotNewPwd2Ctrl.text;

    if (pwd.length < 8) {
      _toast('新密码至少 8 位');
      return;
    }
    if (pwd != pwd2) {
      _toast('两次输入的新密码不一致');
      return;
    }

    setState(() => _forgotSubmitting = true);
    try {
      final res = await _gateway.resetPassword(phone, code, pwd);
      if (res['status'] == 'success') {
        setState(() => _forgotStep = 3);
      } else {
        _toast('❌ ${res['message'] ?? '重置密码失败'}');
      }
    } catch (e) {
      _toast('网络异常: $e');
    } finally {
      if (mounted) setState(() => _forgotSubmitting = false);
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
            onPressed: () => Navigator.pop(context),
          ),
          title: Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF2A3A80), AppTheme.ztoColor]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                child: Text('Z',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16)),
              ),
            ),
            const SizedBox(width: 10),
            const Text('中通会员助手'),
          ]),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_currentTab != 2) ...[
                _buildNativeTabBar(isDark),
                const SizedBox(height: 16),
              ] else ...[
                _buildForgotHeader(isDark),
                const SizedBox(height: 16),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _currentTab == 0
                        ? _buildLoginView(isDark)
                        : _currentTab == 1
                            ? _buildRegisterView(isDark)
                            : _buildForgotView(isDark),
                  ),
                ),
              ),
              if (_loginToken.isNotEmpty && _currentTab == 0) ...[
                const SizedBox(height: 16),
                _buildTokenResultCard(isDark),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ════════════════════ 组件构建 ════════════════════

  /// 原生轻质感 Tab 选项卡
  Widget _buildNativeTabBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkInputFill : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _tabBtn('账号登录', 0, isDark),
          ),
          Expanded(
            child: _tabBtn('注册账号', 1, isDark),
          ),
        ],
      ),
    );
  }

  Widget _tabBtn(String title, int tabIndex, bool isDark) {
    final active = _currentTab == tabIndex;
    return GestureDetector(
      onTap: () => setState(() {
        _currentTab = tabIndex;
        _loginToken = '';
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 38,
        decoration: BoxDecoration(
          color: active
              ? (isDark ? const Color(0xFF1E293B) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.25 : 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Center(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: active
                  ? AppTheme.primary
                  : (isDark ? AppTheme.darkTextMuted : AppTheme.lightTextSub),
            ),
          ),
        ),
      ),
    );
  }

  /// 找回密码头部进度条
  Widget _buildForgotHeader(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: () => setState(() {
            _currentTab = 0;
            _forgotStep = 1;
          }),
          child: Row(children: const [
            Icon(Icons.arrow_back_ios_rounded, size: 14, color: AppTheme.primary),
            SizedBox(width: 4),
            Text('返回登录',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary)),
          ]),
        ),
        Text(
          '步骤 $_forgotStep / 3',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextMuted,
          ),
        ),
      ],
    );
  }

  /// 登录视图
  Widget _buildLoginView(bool isDark) {
    return Column(
      key: const ValueKey('login_panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel('手机号码 / 账号', isDark),
        TextField(
          controller: _loginPhoneCtrl,
          keyboardType: TextInputType.phone,
          maxLength: 11,
          decoration: const InputDecoration(
            hintText: '请输入中通手机号',
            counterText: '',
            prefixIcon: Icon(Icons.phone_android_rounded, size: 18),
          ),
        ),
        const SizedBox(height: 14),
        _fieldLabel('登录密码', isDark),
        TextField(
          controller: _loginPwdCtrl,
          obscureText: _obscurePwd,
          decoration: InputDecoration(
            hintText: '请输入登录密码',
            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePwd
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                size: 18,
              ),
              onPressed: () => setState(() => _obscurePwd = !_obscurePwd),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => setState(() {
              _currentTab = 2;
              _forgotStep = 1;
            }),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('忘记密码？',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary)),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _loggingIn ? null : _doLogin,
          child: _loggingIn
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('立即登录'),
        ),
      ],
    );
  }

  /// 注册视图
  Widget _buildRegisterView(bool isDark) {
    final verified = _regCaptchaCode != null && _regCaptchaCode!.isNotEmpty;

    return Column(
      key: const ValueKey('register_panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel('手机号码', isDark),
        TextField(
          controller: _regPhoneCtrl,
          keyboardType: TextInputType.phone,
          maxLength: 11,
          decoration: const InputDecoration(
            hintText: '请输入 11 位手机号码',
            counterText: '',
            prefixIcon: Icon(Icons.phone_android_rounded, size: 18),
          ),
        ),
        const SizedBox(height: 14),
        _fieldLabel('安全验证', isDark),
        OutlinedButton.icon(
          onPressed: verified ? null : _openRegCaptcha,
          icon: Icon(
            verified ? Icons.check_circle_rounded : Icons.shield_outlined,
            size: 18,
            color: verified ? AppTheme.success : AppTheme.primary,
          ),
          label: Text(verified ? '安全验证已通过' : '点击完成安全滑块验证'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            side: BorderSide(
              color: verified
                  ? AppTheme.success
                  : (isDark ? AppTheme.darkBorder : AppTheme.primary),
            ),
            foregroundColor: verified ? AppTheme.success : AppTheme.primary,
          ),
        ),
        const SizedBox(height: 14),
        _fieldLabel('短信验证码', isDark),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _regCodeCtrl,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  hintText: '6 位数字验证码',
                  counterText: '',
                  prefixIcon: Icon(Icons.sms_outlined, size: 18),
                ),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: (_regCodeSending || _regCountdown > 0)
                  ? null
                  : _sendRegSms,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(105, 48),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(
                _regCodeSending
                    ? '发送中...'
                    : (_regCountdown > 0 ? '${_regCountdown}s' : '获取验证码'),
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _fieldLabel('登录密码 (至少 8 位)', isDark),
        TextField(
          controller: _regPwdCtrl,
          obscureText: _obscureRegPwd,
          decoration: InputDecoration(
            hintText: '请设置 8 位以上登录密码',
            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureRegPwd
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                size: 18,
              ),
              onPressed: () => setState(() => _obscureRegPwd = !_obscureRegPwd),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _fieldLabel('确认密码', isDark),
        TextField(
          controller: _regPwd2Ctrl,
          obscureText: _obscureRegPwd2,
          decoration: InputDecoration(
            hintText: '请再次输入登录密码',
            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureRegPwd2
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                size: 18,
              ),
              onPressed: () =>
                  setState(() => _obscureRegPwd2 = !_obscureRegPwd2),
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _regSubmitting ? null : _doRegister,
          child: _regSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('立即注册'),
        ),
      ],
    );
  }

  /// 找回密码视图
  Widget _buildForgotView(bool isDark) {
    if (_forgotStep == 1) {
      final verified =
          _forgotCaptchaCode != null && _forgotCaptchaCode!.isNotEmpty;
      return Column(
        key: const ValueKey('forgot_step1'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _fieldLabel('注册手机号', isDark),
          TextField(
            controller: _forgotPhoneCtrl,
            keyboardType: TextInputType.phone,
            maxLength: 11,
            decoration: const InputDecoration(
              hintText: '请输入注册手机号',
              counterText: '',
              prefixIcon: Icon(Icons.phone_android_rounded, size: 18),
            ),
          ),
          const SizedBox(height: 14),
          _fieldLabel('安全验证', isDark),
          OutlinedButton.icon(
            onPressed: verified ? null : _openForgotCaptcha,
            icon: Icon(
              verified ? Icons.check_circle_rounded : Icons.shield_outlined,
              size: 18,
              color: verified ? AppTheme.success : AppTheme.primary,
            ),
            label: Text(verified ? '安全验证已通过' : '点击完成安全滑块验证'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              side: BorderSide(
                color: verified
                    ? AppTheme.success
                    : (isDark ? AppTheme.darkBorder : AppTheme.primary),
              ),
              foregroundColor: verified ? AppTheme.success : AppTheme.primary,
            ),
          ),
          const SizedBox(height: 14),
          _fieldLabel('短信验证码', isDark),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _forgotCodeCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    hintText: '6 位数字验证码',
                    counterText: '',
                    prefixIcon: Icon(Icons.sms_outlined, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: (_forgotCodeSending || _forgotCountdown > 0)
                    ? null
                    : _sendForgotSms,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(105, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(
                  _forgotCodeSending
                      ? '发送中...'
                      : (_forgotCountdown > 0
                          ? '${_forgotCountdown}s'
                          : '获取验证码'),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _forgotSubmitting ? null : _verifyForgotCode,
            child: _forgotSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('下一步'),
          ),
        ],
      );
    } else if (_forgotStep == 2) {
      return Column(
        key: const ValueKey('forgot_step2'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _fieldLabel('新登录密码 (至少 8 位)', isDark),
          TextField(
            controller: _forgotNewPwdCtrl,
            obscureText: _obscureForgotPwd,
            decoration: InputDecoration(
              hintText: '请输入新登录密码',
              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureForgotPwd
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  size: 18,
                ),
                onPressed: () =>
                    setState(() => _obscureForgotPwd = !_obscureForgotPwd),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _fieldLabel('确认新密码', isDark),
          TextField(
            controller: _forgotNewPwd2Ctrl,
            obscureText: _obscureForgotPwd2,
            decoration: InputDecoration(
              hintText: '请再次输入新登录密码',
              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureForgotPwd2
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  size: 18,
                ),
                onPressed: () =>
                    setState(() => _obscureForgotPwd2 = !_obscureForgotPwd2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _forgotSubmitting ? null : _doResetPassword,
            child: _forgotSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('确认修改密码'),
          ),
        ],
      );
    } else {
      return Column(
        key: const ValueKey('forgot_step3'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          const Icon(Icons.check_circle_rounded,
              color: AppTheme.success, size: 54),
          const SizedBox(height: 12),
          Text(
            '密码重置成功！',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: isDark ? AppTheme.darkTextMain : AppTheme.lightTextMain,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '请使用新密码重新登录账号',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppTheme.darkTextMuted : AppTheme.lightTextSub,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => setState(() {
              _currentTab = 0;
              _forgotStep = 1;
              _loginPhoneCtrl.text = _forgotPhoneCtrl.text;
              _loginPwdCtrl.text = _forgotNewPwdCtrl.text;
            }),
            child: const Text('返回登录'),
          ),
        ],
      );
    }
  }

  /// 登录凭证卡片
  Widget _buildTokenResultCard(bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.check_circle_rounded,
                  color: AppTheme.success, size: 18),
              const SizedBox(width: 8),
              Text(
                '登录凭证 (Token)',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: isDark ? AppTheme.darkTextMain : AppTheme.lightTextMain,
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkInputFill : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                ),
              ),
              child: SelectableText(
                _loginToken,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: isDark ? AppTheme.darkTextMain : AppTheme.lightTextMain,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _loginToken));
                _toast('Token 已成功复制到剪贴板');
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('复制 Token'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldLabel(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: isDark ? AppTheme.darkTextMain : const Color(0xFF334155),
        ),
      ),
    );
  }
}
