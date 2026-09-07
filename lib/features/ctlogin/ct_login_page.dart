import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import 'ct_crypto_util.dart';
import 'ct_gateway.dart';
import 'ct_history_store.dart';

/// 电信登录助手页面 — 完整移植原版逻辑
class CtLoginPage extends StatefulWidget {
  const CtLoginPage({super.key});

  @override
  State<CtLoginPage> createState() => _CtLoginPageState();
}

class _CtLoginPageState extends State<CtLoginPage> {
  int _step = 1; // 1=手机号 2=图形验证 3=短信登录 4=成功
  bool _loading = false;

  final _phoneCtrl = TextEditingController();
  final _captchaCtrl = TextEditingController();
  final _smsCtrl = TextEditingController();
  final _remarkCtrl = TextEditingController();

  String _phone = '';
  String _captchaKey = '';
  String _smsId = '';
  String _rawAndroidId = '';
  String _encAndroidId = '';
  String _remark = '密码';

  CtGateway? _gateway;
  Image? _captchaImage;
  List<CtHistoryItem> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _captchaCtrl.dispose();
    _smsCtrl.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final list = await CtHistoryStore.load();
    if (mounted) setState(() => _history = list);
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

  /// 一键复制所有历史账号（默认没有记录时不复制）
  void _copyAllHistory({bool rawId = false}) {
    if (_history.isEmpty) return;
    final lines = _history.map((item) {
      final remark = item.remark.isEmpty ? '密码' : item.remark;
      final idPart = rawId ? item.androidId : CryptoUtil.encodeString(item.androidId);
      return '${item.phone}#$remark#$idPart';
    }).join('\n');
    final suffix = rawId ? '设备ID' : '转换ID';
    _copy(lines, '已复制全部 ${_history.length} 条账号（手机号#密码#$suffix）');
  }

  void _resetFlow() {
    setState(() {
      _step = 1;
      _phone = '';
      _captchaKey = '';
      _smsId = '';
      _rawAndroidId = '';
      _encAndroidId = '';
      _remark = '密码';
      _captchaImage = null;
      _gateway = null;
      _phoneCtrl.clear();
      _captchaCtrl.clear();
      _smsCtrl.clear();
      _remarkCtrl.clear();
    });
  }

  Future<void> _initiate() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.length != 11 || !phone.startsWith('1')) {
      _toast('请输入正确的 11 位手机号');
      return;
    }
    setState(() => _loading = true);
    try {
      if (await CtHistoryStore.contains(phone)) {
        _toast('⚠️ 历史记录已存在该号码，请先在下方历史记录中删除后再添加');
        return;
      }
      _phone = phone;
      final gateway = CtGateway(
          CryptoUtil.randomDeviceModel(), CryptoUtil.randomAndroidId());
      _gateway = gateway;
      final res = await gateway.initiate(phone);
      if (res.needCaptcha) {
        setState(() {
          _captchaKey = res.key;
          _step = 2;
        });
        _showCaptchaImage(res.image);
      } else {
        setState(() {
          _smsId = res.smsId;
          _step = 3;
        });
        _toast('短信已发送，请输入验证码');
      }
    } catch (e) {
      _toast('❌ ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showCaptchaImage(String base64Image) {
    if (base64Image.isEmpty) return;
    try {
      final img = Image.memory(base64Decode(base64Image), fit: BoxFit.contain);
      if (mounted) setState(() => _captchaImage = img);
    } catch (_) {}
  }

  Future<void> _refreshCaptcha() async {
    try {
      final res = await _gateway!.getCaptcha();
      setState(() => _captchaKey = res.key);
      _showCaptchaImage(res.image);
    } catch (e) {
      _toast('刷新验证码失败');
    }
  }

  Future<void> _sendSms() async {
    final code = _captchaCtrl.text.trim();
    if (code.length != 4) {
      _toast('验证码必须 4 位');
      return;
    }
    setState(() => _loading = true);
    try {
      final smsId = await _gateway!.sendSms(_phone, code, _captchaKey);
      setState(() {
        _smsId = smsId;
        _step = 3;
        _captchaImage = null;
        _captchaCtrl.clear();
      });
      _toast('短信已发送，请输入验证码');
    } catch (e) {
      _toast('❌ ${e.toString().replaceFirst('Exception: ', '')}');
      await _refreshCaptcha();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _doLogin() async {
    final sms = _smsCtrl.text.trim();
    if (sms.length != 6) {
      _toast('验证码必须 6 位');
      return;
    }
    setState(() => _loading = true);
    try {
      final remarkInput = _remarkCtrl.text.trim();
      final effective = remarkInput.isEmpty ? '密码' : remarkInput;

      if (await CtHistoryStore.contains(_phone)) {
        _toast('⚠️ 历史记录已存在该号码，请先在下方历史记录中删除后再添加');
        await _loadHistory();
        return;
      }

      final res = await _gateway!.login(_phone, _smsId, sms);
      if (!res.success) {
        _toast('❌ ${res.message}');
        return;
      }
      await CtHistoryStore.save(_phone, res.androidId!, effective);
      await _loadHistory();
      setState(() {
        _rawAndroidId = res.androidId!;
        _encAndroidId = res.encodedAndroidId!;
        _remark = effective;
        _step = 4;
      });
    } catch (e) {
      _toast('❌ ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _loading = false);
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
                    colors: [Color(0xFF1E88E5), AppTheme.ctColor]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Center(
                  child: Text('翼',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 15))),
            ),
            const SizedBox(width: 10),
            const Text('电信登录助手'),
          ]),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            _buildStepBar(isDark),
            const SizedBox(height: 16),
            _buildCard(isDark),
            const SizedBox(height: 16),
            if (_history.isNotEmpty) _buildHistory(isDark),
          ]),
        ),
      ),
    );
  }

  Widget _buildStepBar(bool isDark) {
    Widget dot(int n, {bool active = false, bool done = false}) => Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: done
                ? AppTheme.success
                : active
                    ? AppTheme.ctColor
                    : (isDark ? AppTheme.darkCard : const Color(0xFFF1F5F9)),
            border: Border.all(
                color: done
                    ? AppTheme.success
                    : active
                        ? AppTheme.ctColor
                        : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
                width: 2),
          ),
          child: Center(
            child: done
                ? const Icon(Icons.check, color: Colors.white, size: 15)
                : Text('$n',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: active
                            ? Colors.white
                            : (isDark
                                ? AppTheme.darkTextMuted
                                : AppTheme.lightTextMuted))),
          ),
        );
    Widget bar(bool done) => Expanded(
        child: Container(
            height: 2,
            color: done
                ? AppTheme.success
                : (isDark ? AppTheme.darkBorder : AppTheme.lightBorder)));
    return Row(children: [
      dot(1, active: _step == 1, done: _step > 1),
      bar(_step > 1),
      dot(2, active: _step == 2, done: _step > 2),
      bar(_step > 2),
      dot(3, active: _step == 3, done: _step > 3),
    ]);
  }

  Widget _buildCard(bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_step == 1) _buildStep1(isDark),
          if (_step == 2) _buildStep2(isDark),
          if (_step == 3) _buildStep3(isDark),
          if (_step == 4) _buildSuccess(),
        ]),
      ),
    );
  }

  Widget _label(String text, bool isDark, {String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(text,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppTheme.darkTextMain : const Color(0xFF334155))),
          if (hint != null)
            Text(hint,
                style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppTheme.darkTextMuted : AppTheme.textMuted)),
        ]),
      );

  Widget _loadingBtn(String label, VoidCallback onTap) => FilledButton(
        onPressed: _loading ? null : onTap,
        child: _loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Text(label),
      );

  Widget _buildStep1(bool isDark) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _label('中国电信手机号', isDark),
        TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            maxLength: 11,
            decoration: const InputDecoration(
                hintText: '请输入 11 位手机号', counterText: '')),
        const SizedBox(height: 12),
        _loadingBtn('下一步', _initiate),
      ]);

  Widget _buildStep2(bool isDark) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _label('图形验证码', isDark, hint: '点击图片可刷新'),
        Row(children: [
          Expanded(
              child: TextField(
                  controller: _captchaCtrl,
                  maxLength: 4,
                  decoration: const InputDecoration(
                      hintText: '4 位验证码', counterText: ''))),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _refreshCaptcha,
            child: Container(
              width: 120,
              height: 48,
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: isDark ? AppTheme.darkBorder : AppTheme.border,
                      width: 1.5)),
              child: _captchaImage ??
                  const Center(
                      child: Text('加载中...', style: TextStyle(fontSize: 12))),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        _loadingBtn('发送短信验证码', _sendSms),
      ]);

  Widget _buildStep3(bool isDark) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _label('短信验证码', isDark),
        TextField(
            controller: _smsCtrl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(
                hintText: '6 位验证码', counterText: '')),
        const SizedBox(height: 12),
        _label('备注密码（可选）', isDark, hint: '留空则复制为默认「密码」'),
        TextField(
            controller: _remarkCtrl,
            maxLength: 32,
            decoration: const InputDecoration(
                hintText: '自定义密码备注，如：Abc12345', counterText: '')),
        const SizedBox(height: 12),
        _loadingBtn('立即登录', _doLogin),
      ]);

  Widget _idBox(String title, String value, VoidCallback onCopy) {
    final isDark = ThemeController.instance.isDark(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: isDark ? AppTheme.darkInputFill : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isDark ? AppTheme.darkTextSub : AppTheme.lightTextSub)),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
              child: SelectableText(value,
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppTheme.darkTextMain
                          : AppTheme.lightTextMain))),
          const SizedBox(width: 8),
          OutlinedButton(
              onPressed: onCopy,
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(60, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 10)),
              child: const Text('复制', style: TextStyle(fontSize: 12))),
        ]),
      ]),
    );
  }

  Widget _buildSuccess() {
    final isDark = ThemeController.instance.isDark(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 8),
      const Icon(Icons.check_circle, color: AppTheme.success, size: 56),
      const SizedBox(height: 8),
      Text('✅ 登录成功',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: isDark ? AppTheme.darkTextMain : AppTheme.lightTextMain)),
      const SizedBox(height: 16),
      _idBox('Android ID（原始）', _rawAndroidId, () => _copy(_rawAndroidId)),
      _idBox('Android ID（转换后 +2 编码）', _encAndroidId, () => _copy(_encAndroidId)),
      FilledButton.tonal(
        onPressed: () => _copy('$_phone#$_remark#$_rawAndroidId'),
        style: FilledButton.styleFrom(
            backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
            foregroundColor: AppTheme.ctColor,
            side: const BorderSide(color: AppTheme.ctColor, width: 1.5),
            elevation: 0),
        child: Text('📋 复制（手机号#$_remark#设备ID）'),
      ),
      const SizedBox(height: 8),
      FilledButton.tonal(
        onPressed: () => _copy('$_phone#$_remark#$_encAndroidId'),
        style: FilledButton.styleFrom(
            backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
            foregroundColor: AppTheme.ctColor,
            side: const BorderSide(color: AppTheme.ctColor, width: 1.5),
            elevation: 0),
        child: Text('📋 复制（手机号#$_remark#转换ID）'),
      ),
      const SizedBox(height: 8),
      OutlinedButton(onPressed: _resetFlow, child: const Text('继续登录其他账号')),
    ]);
  }

  Widget _buildHistory(bool isDark) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Row(children: [
              const Icon(Icons.history, size: 18, color: AppTheme.ctColor),
              const SizedBox(width: 6),
              Text('历史记录',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? AppTheme.darkTextMain
                          : AppTheme.lightTextMain)),
            ]),
            Row(children: [
              TextButton.icon(
                onPressed: _history.isEmpty
                    ? null
                    : () => _copyAllHistory(rawId: false),
                icon: const Icon(Icons.copy_all_rounded,
                    size: 15, color: AppTheme.ctColor),
                label: const Text('全部#转换ID',
                    style: TextStyle(fontSize: 12, color: AppTheme.ctColor)),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32)),
              ),
              TextButton.icon(
                onPressed: _history.isEmpty
                    ? null
                    : () => _copyAllHistory(rawId: true),
                icon: const Icon(Icons.copy_all_rounded,
                    size: 15, color: AppTheme.ctColor),
                label: const Text('全部#设备ID',
                    style: TextStyle(fontSize: 12, color: AppTheme.ctColor)),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32)),
              ),
              TextButton.icon(
                onPressed: () async {
                  await CtHistoryStore.clear();
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
          ]),
          const SizedBox(height: 4),
          ..._history.map((i) => _buildHistoryItem(i, isDark)),
        ]),
      ),
    );
  }

  Widget _buildHistoryItem(CtHistoryItem item, bool isDark) {
    final encId = CryptoUtil.encodeString(item.androidId);
    final dt = DateTime.fromMillisecondsSinceEpoch(item.at);
    final timeStr =
        '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        border: Border(
            bottom: BorderSide(
                color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder,
                width: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          GestureDetector(
            onTap: () {
              _phoneCtrl.text = item.phone;
              _toast('已填入手机号: ${item.phone}');
            },
            child: Text(item.phone,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: isDark
                        ? AppTheme.darkTextMain
                        : AppTheme.lightTextMain)),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () {
              _remarkCtrl.text = item.remark;
              _toast('已填入备注密码: ${item.remark}');
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: isDark
                      ? AppTheme.ctColor.withOpacity(0.2)
                      : AppTheme.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.ctColor.withOpacity(0.3))),
              child: Text('→ ${item.remark}',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.lightBlueAccent : AppTheme.ctColor)),
            ),
          ),
          const SizedBox(width: 8),
          Text(timeStr,
              style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? AppTheme.darkTextMuted
                      : AppTheme.lightTextMuted)),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () async {
              await CtHistoryStore.delete(item.phone);
              await _loadHistory();
              _toast('已删除: ${item.phone}');
            },
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFECACA))),
              child:
                  const Icon(Icons.close, size: 14, color: AppTheme.danger),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        SelectableText('${item.androidId} → $encId',
            style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: isDark
                    ? AppTheme.darkTextSub
                    : AppTheme.lightTextSub)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: _miniBtn('复制（手机号#${item.remark}#设备ID）',
                  () => _copy('${item.phone}#${item.remark}#${item.androidId}'),
                  isDark)),
          const SizedBox(width: 6),
          Expanded(
              child: _miniBtn('复制（手机号#${item.remark}#转换ID）',
                  () => _copy('${item.phone}#${item.remark}#$encId'),
                  isDark)),
        ]),
      ]),
    );
  }

  Widget _miniBtn(String text, VoidCallback onTap, [bool isDark = false]) =>
      OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
          side: BorderSide(
              color: isDark ? AppTheme.darkBorder : AppTheme.lightBorder),
          foregroundColor:
              isDark ? AppTheme.darkTextSub : const Color(0xFF334155),
          textStyle:
              const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        ),
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
}
