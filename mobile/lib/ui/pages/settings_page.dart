import 'package:flutter/material.dart';

import '../../core/mobile_controller.dart';
import '../../core/mobile_scope.dart';
import '../../core/protocol.dart';
import '../brand.dart';
import '../theme.dart';
import '../widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _relay = TextEditingController();
  final TextEditingController _stunUrl = TextEditingController();
  final TextEditingController _turnUrl = TextEditingController();
  final TextEditingController _turnUsername = TextEditingController();
  final TextEditingController _turnCredential = TextEditingController();
  String? _lastRelay;
  (String, String, String, String)? _lastRtc;
  bool _savingRtc = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final config = MobileScope.of(context).config;
    if (config.relayUrl != _lastRelay) {
      _lastRelay = config.relayUrl;
      _relay.text = config.relayUrl;
    }
    final rtc = (
      config.stunUrl,
      config.turnUrl,
      config.turnUsername,
      config.turnCredential,
    );
    if (rtc != _lastRtc) {
      _lastRtc = rtc;
      _stunUrl.text = config.stunUrl;
      _turnUrl.text = config.turnUrl;
      _turnUsername.text = config.turnUsername;
      _turnCredential.text = config.turnCredential;
    }
  }

  @override
  void dispose() {
    _relay.dispose();
    _stunUrl.dispose();
    _turnUrl.dispose();
    _turnUsername.dispose();
    _turnCredential.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = MobileScope.of(context);
    final config = controller.config;
    final status = controller.status;
    final statusColor = status.sessionActive
        ? AppColors.red
        : status.relay == 'online'
            ? AppColors.green
            : status.running
                ? AppColors.orange
                : AppColors.textTertiary;
    final statusText = status.sessionActive
        ? '被控中'
        : status.relay == 'online'
            ? '信令在线'
            : status.running
                ? '连接中'
                : '未开启';
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            child: const Text('设置', style: AppText.h2),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    children: [
                      const BrandMark(size: 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(config.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.bodyStrong),
                            const SizedBox(height: 3),
                            Text(
                              formatDeviceId(config.id),
                              style: AppText.caption,
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        statusText,
                        style: TextStyle(fontSize: 11, color: statusColor),
                      ),
                    ],
                  ),
                ),
                SectionCard(
                  title: '信令服务器（WS / WSS）',
                  subtitle: '两端须连接同一信令服务；局域网也需要信令',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: AppTextField(
                              controller: _relay,
                              hint: 'ws://IP:7080/ws',
                              keyboardType: TextInputType.url,
                              prefixIcon:
                                  const Icon(Icons.dns_outlined, size: 18),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 50,
                            width: 72,
                            child: FilledButton(
                              onPressed: () async {
                                await controller.saveRelayUrl(_relay.text);
                                if (!context.mounted) return;
                                FocusScope.of(context).unfocus();
                              },
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(72, 50),
                                padding: EdgeInsets.zero,
                              ),
                              child: const Text('保存',
                                  style: TextStyle(fontSize: 14)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'WS / WSS 仅用于信令。模拟器可用 ws://10.0.2.2:7080/ws；'
                        '真机填写实际信令服务地址，公网推荐 WSS 与可信证书。'
                        '保存不停止当前会话；被控服务运行时，新地址下次开启生效。',
                        style: AppText.caption,
                      ),
                    ],
                  ),
                ),
                SectionCard(
                  title: 'WebRTC 连接（STUN / TURN）',
                  subtitle: '优先 UDP 直连，不通时通过 TURN 中转',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _rtcField('STUN URL', _stunUrl, hint: '留空关闭 STUN'),
                      _rtcField('TURN URL', _turnUrl, hint: '留空关闭 TURN'),
                      _rtcField('TURN 用户名', _turnUsername, hint: '启用 TURN 时必填'),
                      _rtcField('TURN 密码', _turnCredential,
                          hint: '启用 TURN 时必填', obscure: true),
                      const Text(
                        '支持 stun: / stuns: / turn: / turns: 标准地址、[IPv6]，'
                        '以及 ?transport=udp 或 ?transport=tcp。'
                        '公网推荐 TURNS 与可信证书，请填写实际部署的 TURN 服务。'
                        '留空关闭对应服务可能降低跨网络连接成功率。',
                        style: AppText.caption,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '双方使用各自本地配置，TURN 凭据不发送给对端。'
                        '保存不打断当前会话：控制端下次会话、被控端下次开启服务生效，'
                        '不会自动停止服务。',
                        style: AppText.caption,
                      ),
                      const SizedBox(height: 14),
                      FilledButton(
                        onPressed:
                            _savingRtc ? null : () => _saveRtc(controller),
                        child: Text(_savingRtc ? '正在保存' : '保存 RTC 配置'),
                      ),
                    ],
                  ),
                ),
                SectionCard(
                  title: '被控端权限',
                  subtitle: '免 root 输入依赖系统无障碍服务',
                  child: Column(
                    children: [
                      PermissionRow(
                        icon: Icons.accessibility_new,
                        title: '无障碍输入服务',
                        subtitle: status.accessibilityEnabled
                            ? '已启用，可接收点击、滑动与文本'
                            : '未启用，只能查看画面',
                        enabled: status.accessibilityEnabled,
                        actionLabel: status.accessibilityEnabled ? null : '去开启',
                        onAction: controller.openAccessibility,
                      ),
                      const Divider(height: 1),
                      PermissionRow(
                        icon: Icons.notifications_active_outlined,
                        title: '前台服务通知',
                        subtitle: status.notificationGranted
                            ? '已授权'
                            : 'Android 13+ 需要通知权限',
                        enabled: status.notificationGranted,
                        actionLabel: status.notificationGranted ? null : '授权',
                        onAction: controller.requestNotifications,
                      ),
                      const Divider(height: 1),
                      PermissionRow(
                        icon: Icons.battery_saver_outlined,
                        title: '电池优化',
                        subtitle: '关闭电池优化可降低被系统杀后台的概率',
                        enabled: false,
                        actionLabel: '去设置',
                        onAction: controller.openBatterySettings,
                      ),
                    ],
                  ),
                ),
                SectionCard(
                  title: '设备与安全',
                  child: Column(
                    children: [
                      _SettingRow(
                        icon: Icons.pin_outlined,
                        label: '重置识别码与验证码',
                        onTap: () => _resetIdentity(controller),
                      ),
                      const Divider(height: 1),
                      _SettingRow(
                        icon: Icons.password_outlined,
                        label: '验证码',
                        value: config.password.replaceAll(RegExp(r'.'), '•'),
                        onTap: null,
                      ),
                      if (status.running) ...[
                        const Divider(height: 1),
                        _SettingRow(
                          icon: Icons.stop_circle_outlined,
                          label: '停止本机被控',
                          danger: true,
                          onTap: controller.stopHosting,
                        ),
                      ],
                    ],
                  ),
                ),
                const SectionCard(
                  title: '关于',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _AboutRow(label: '版本', value: '1.0.0'),
                      SizedBox(height: 8),
                      _AboutRow(
                          label: '协议', value: 'WebRTC / SRTP + DataChannel'),
                      SizedBox(height: 8),
                      _AboutRow(label: '信令', value: 'WS / WSS（公网推荐 WSS）'),
                      SizedBox(height: 8),
                      _AboutRow(label: '支持', value: 'Android 7.0+（API 24）'),
                      SizedBox(height: 12),
                      Text(
                        '无需账号。每次开启本机被控都需要用户确认系统屏幕共享授权，'
                        '远程连接需要验证码，请只向信任的人提供。'
                        '连接仍依赖信令服务，传输保护不能替代对对端和服务器的信任。',
                        style: AppText.caption,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'WebRTC 当前为 30 FPS、40 Mbps 高码率配置，清晰度优先。'
                        '控制端保留旧 JPEG 兼容模式；JPEG 质量与最大宽度不影响 WebRTC。',
                        style: AppText.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rtcField(String label, TextEditingController field,
      {required String hint, bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.caption),
          const SizedBox(height: 6),
          Semantics(
            label: label,
            child: AppTextField(
              key: ValueKey(label),
              controller: field,
              hint: hint,
              obscure: obscure,
              keyboardType:
                  obscure ? TextInputType.visiblePassword : TextInputType.text,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveRtc(MobileController controller) async {
    setState(() => _savingRtc = true);
    try {
      await controller.saveRtcSettings(
        stunUrl: _stunUrl.text,
        turnUrl: _turnUrl.text,
        turnUsername: _turnUsername.text,
        turnCredential: _turnCredential.text,
      );
      if (mounted) FocusScope.of(context).unfocus();
    } finally {
      if (mounted) setState(() => _savingRtc = false);
    }
  }

  Future<void> _resetIdentity(MobileController controller) async {
    final ok = await confirmDialog(
      context,
      title: '重置设备身份',
      message: '将生成新的识别码和验证码，旧的识别码立即失效。请先停止本机被控。',
      confirmLabel: '重置',
      danger: true,
    );
    if (!ok || !mounted) return;
    await controller.regenerateIdentity();
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.label,
    this.value,
    this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          children: [
            Icon(icon,
                size: 18,
                color: danger ? AppColors.red : AppColors.textTertiary),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(
                  fontSize: 14,
                  color: danger ? AppColors.red : AppColors.textPrimary,
                )),
            const Spacer(),
            if (value != null) Text(value!, style: AppText.caption),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right,
                  size: 18,
                  color: danger ? AppColors.red : AppColors.textTertiary),
            ],
          ],
        ),
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(label, style: AppText.caption),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
        ),
      ],
    );
  }
}
