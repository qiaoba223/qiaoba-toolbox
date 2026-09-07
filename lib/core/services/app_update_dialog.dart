import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import 'app_update_service.dart';
import 'proxy_config.dart';

/// 现代化应用内一键更新弹窗（双端适配：安卓 App 内直装，iOS 支持 Safari 唤醒、巨魔直链复制与协议拉起）
void showUpdateDialog(BuildContext context, Map<String, String> info) {
  final version = info['version'] ?? '';
  final current = info['current'] ?? '';
  final apkUrl = info['apkUrl'] ?? '';
  final ipaUrl = info['ipaUrl'] ?? '';
  final releaseUrl = info['releaseUrl'] ??
      'https://github.com/qiaoba223/qiaoba-toolbox/releases/tag/v$version';
  final notes = info['notes'] ?? '';

  final isIos = Platform.isIOS;

  bool downloading = false;
  double progress = 0;
  String progressText = '准备下载...';

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => PopScope(
        canPop: !downloading,
        child: AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          actionsPadding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          title: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.primaryLight,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.rocket_launch_rounded,
                  color: AppTheme.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('发现新版本 v$version',
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.textMain)),
                  Text('当前版本: v$current',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textMuted)),
                ],
              ),
            ),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (notes.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxHeight: 130),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      notes,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF475569),
                          height: 1.5),
                    ),
                  ),
                ),
              if (downloading) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                    minHeight: 8,
                    backgroundColor: const Color(0xFFE2E8F0),
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                  ),
                ),
                const SizedBox(height: 8),
                Text(progressText,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B))),
              ] else ...[
                const SizedBox(height: 14),
                // 代理加速设置条
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await showProxySettingsDialog(context, () {
                      showUpdateDialog(context, info);
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: FutureBuilder<String>(
                      future: ProxyConfig.describe(),
                      builder: (context, snap) {
                        return Row(children: [
                          const Icon(Icons.speed_rounded,
                              size: 16, color: AppTheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              snap.data ?? '加载代理中...',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF334155)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Text('修改',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.primary)),
                          const SizedBox(width: 2),
                          const Icon(Icons.chevron_right_rounded,
                              size: 14, color: AppTheme.primary),
                        ]);
                      },
                    ),
                  ),
                ),
                if (isIos) ...[
                  const SizedBox(height: 12),
                  // iOS 快捷操作区
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.copy_rounded, size: 14),
                        label: const Text('复制IPA直链',
                            style: TextStyle(fontSize: 12)),
                        onPressed: () async {
                          final finalIpaUrl =
                              await ProxyConfig.resolveDownloadUrl(ipaUrl);
                          await Clipboard.setData(
                              ClipboardData(text: finalIpaUrl));
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    '✅ IPA 下载直链已复制，可前往巨魔 (TrollStore) 直接粘贴安装！'),
                                duration: Duration(seconds: 3),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.open_in_browser_rounded,
                            size: 14),
                        label:
                            const Text('网页查看', style: TextStyle(fontSize: 12)),
                        onPressed: () async {
                          final uri = Uri.parse(releaseUrl);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          }
                        },
                      ),
                    ),
                  ]),
                ],
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: downloading ? null : () => Navigator.pop(ctx),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.textMuted,
                textStyle:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              child: const Text('稍后再说'),
            ),
            if (!isIos)
              FilledButton(
                onPressed: downloading
                    ? null
                    : () async {
                        setState(() => downloading = true);
                        try {
                          final url =
                              await ProxyConfig.resolveDownloadUrl(apkUrl);
                          final path =
                              await AppUpdateService.downloadApk(url,
                                  (rec, total) {
                            if (ctx.mounted) {
                              setState(() {
                                progress = total > 0 ? rec / total : 0;
                                progressText = total > 0
                                    ? '已下载 ${(rec / 1048576).toStringAsFixed(1)} / ${(total / 1048576).toStringAsFixed(1)} MB (${(progress * 100).toInt()}%)'
                                    : '已下载 ${(rec / 1048576).toStringAsFixed(1)} MB';
                              });
                            }
                          });
                          if (ctx.mounted) Navigator.pop(ctx);
                          await _installApk(path);
                        } catch (e) {
                          if (ctx.mounted) {
                            setState(() {
                              downloading = false;
                              progressText = '下载失败';
                            });
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text('下载异常: $e')),
                            );
                          }
                        }
                      },
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('立即一键更新'),
              )
            else
              FilledButton.icon(
                icon: const Icon(Icons.download_for_offline_rounded, size: 18),
                label: const Text('Safari 中下载安装包'),
                onPressed: () async {
                  final finalIpaUrl =
                      await ProxyConfig.resolveDownloadUrl(ipaUrl);
                  final uri = Uri.parse(finalIpaUrl.isNotEmpty ? finalIpaUrl : releaseUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// 代理设置弹窗：每个卡片左右 100% 对齐，内部结构严整
Future<void> showProxySettingsDialog(
    BuildContext context, VoidCallback onChanged) async {
  final mode = await ProxyConfig.getMode();
  final value = await ProxyConfig.getValue();
  var selMode = mode;

  final mirrorCtrl = TextEditingController(
      text: (mode == ProxyMode.mirror && value.isNotEmpty)
          ? value
          : ProxyConfig.defaultMirror);
  final httpCtrl = TextEditingController(
      text: (mode == ProxyMode.http) ? value : '');

  if (!context.mounted) return;
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        backgroundColor: Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        title: const Row(children: [
          Icon(Icons.tune_rounded, color: AppTheme.primary, size: 22),
          SizedBox(width: 8),
          Text('下载网络加速设置',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ]),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('解决 GitHub Releases 资源在国内下载缓慢或超时：',
                  style: TextStyle(
                      fontSize: 12, color: Color(0xFF64748B), height: 1.4)),
              const SizedBox(height: 12),

              // 选项 1: gh-proxy.com 镜像加速 (推荐)
              _buildAlignedOptionCard(
                selected: selMode == ProxyMode.mirror,
                onTap: () => setState(() => selMode = ProxyMode.mirror),
                title: '⚡ gh-proxy.com 镜像加速',
                subtitle: '国内直连加速通道（默认推荐）',
                badgeText: '推荐',
                child: selMode == ProxyMode.mirror
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: TextField(
                          controller: mirrorCtrl,
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            hintText: 'https://gh-proxy.com/',
                            prefixIcon: const Icon(Icons.link_rounded,
                                size: 16, color: AppTheme.primary),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.refresh_rounded,
                                  size: 16),
                              tooltip: '恢复默认',
                              onPressed: () => mirrorCtrl.text =
                                  ProxyConfig.defaultMirror,
                            ),
                          ),
                        ),
                      )
                    : null,
              ),

              const SizedBox(height: 10),

              // 选项 2: 直连不使用代理
              _buildAlignedOptionCard(
                selected: selMode == ProxyMode.direct,
                onTap: () => setState(() => selMode = ProxyMode.direct),
                title: '🚫 直连下载（不用代理）',
                subtitle: '直接连接 GitHub 官方节点',
              ),

              const SizedBox(height: 10),

              // 选项 3: 本地/局域网 HTTP 代理
              _buildAlignedOptionCard(
                selected: selMode == ProxyMode.http,
                onTap: () => setState(() => selMode = ProxyMode.http),
                title: '🔌 自定义 HTTP 代理',
                subtitle: '适合科学上网客户端，如 127.0.0.1:7890',
                child: selMode == ProxyMode.http
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: TextField(
                          controller: httpCtrl,
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            hintText: '127.0.0.1:7890',
                            prefixIcon: const Icon(Icons.router_rounded,
                                size: 16, color: Color(0xFF64748B)),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.clear_rounded,
                                  size: 16),
                              onPressed: () => httpCtrl.clear(),
                            ),
                          ),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await ProxyConfig.save(ProxyMode.direct, '');
              if (ctx.mounted) Navigator.pop(ctx);
              onChanged();
            },
            child: const Text('停用并清除',
                style: TextStyle(color: AppTheme.danger, fontSize: 13)),
          ),
          FilledButton(
            onPressed: () async {
              String val = '';
              if (selMode == ProxyMode.mirror) {
                val = mirrorCtrl.text.trim();
                if (val.isEmpty) val = ProxyConfig.defaultMirror;
              } else if (selMode == ProxyMode.http) {
                val = httpCtrl.text.trim();
              }
              await ProxyConfig.save(selMode, val);
              if (ctx.mounted) Navigator.pop(ctx);
              onChanged();
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('保存配置'),
          ),
        ],
      ),
    ),
  );
}

/// 严整对齐的单选卡片
Widget _buildAlignedOptionCard({
  required bool selected,
  required VoidCallback onTap,
  required String title,
  required String subtitle,
  String? badgeText,
  Widget? child,
}) {
  return InkWell(
    borderRadius: BorderRadius.circular(12),
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: selected ? AppTheme.primaryLight : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? AppTheme.primary : AppTheme.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 18,
              color: selected ? AppTheme.primary : const Color(0xFF94A3B8),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? AppTheme.textMain
                                : const Color(0xFF334155))),
                    if (badgeText != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(badgeText,
                            style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFD97706))),
                      ),
                    ],
                  ]),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF94A3B8))),
                ],
              ),
            ),
          ]),
          if (child != null) child,
        ],
      ),
    ),
  );
}

final _installChannel = const MethodChannel('qiaoba_toolbox/installer');

Future<void> _installApk(String path) async {
  await _installChannel.invokeMethod('installApk', {'path': path});
}
