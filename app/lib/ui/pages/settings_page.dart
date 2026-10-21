import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/app_controller.dart';
import '../../core/models.dart';
import '../../engine/host_engine.dart';
import '../../native/win32.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../app_scope.dart';
import '../widgets/dialogs.dart';
import '../widgets/ui_kit.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 26, 30, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppPageHeader(
                title: '设置',
                subtitle: '管理这台电脑的连接、画面与安全偏好。',
              ),
              SizedBox(height: 22),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 222, child: _SettingsNav()),
                    SizedBox(width: 20),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.only(bottom: 30),
                        child: _SettingsContent(),
                      ),
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

class _SettingsNav extends StatelessWidget {
  const _SettingsNav();

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    const items = [
      (SettingsTab.info, AppIcons.infoSquare, '本机信息'),
      (SettingsTab.general, Icons.dns_outlined, '连接设置'),
      (SettingsTab.desktop, AppIcons.desktop, '远程画面'),
      (SettingsTab.security, AppIcons.security, '安全验证'),
      (SettingsTab.notification, AppIcons.notification, '消息提醒'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              for (final item in items) ...[
                _NavItem(
                  icon: item.$2,
                  label: item.$3,
                  selected: controller.settingsTab == item.$1,
                  onTap: () => controller.setSettingsTab(item.$1),
                ),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                child: Hairline(),
              ),
              _NavItem(
                icon: AppIcons.newVersion,
                label: '检查更新',
                onTap: () => _showUpdate(context, controller),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              const Text('星轨远控 · 1.0.0', style: AppText.tiny),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _showUpdate(BuildContext context, AppController controller) =>
      showAppDialog(
        context: context,
        title: '星轨远控 1.0.0',
        content: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('当前版本已是最新版本。'),
            SizedBox(height: 14),
            _UpdateLine('全新浅色界面与星轨品牌视觉'),
            _UpdateLine('Windows 屏幕采集与键鼠注入'),
            _UpdateLine('Android 控制端与被控端'),
            _UpdateLine('Docker 中继服务器部署'),
          ],
        ),
        actions: [
          PrimaryButton(
            label: '知道了',
            width: 100,
            height: 36,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
}

class _UpdateLine extends StatelessWidget {
  const _UpdateLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          const Icon(AppIcons.checkFill, size: 14, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    this.selected = false,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HoverBuilder(
      builder: (hovered) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          height: 40,
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primarySoft
                : hovered
                    ? AppColors.surfaceMuted
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? AppColors.primary : AppColors.textMuted,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
              if (selected) ...[
                const Spacer(),
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsContent extends StatelessWidget {
  const _SettingsContent();

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return switch (controller.settingsTab) {
      SettingsTab.info => const _InfoPage(),
      SettingsTab.general => const _ConnectionPage(),
      SettingsTab.desktop => const _DesktopPage(),
      SettingsTab.security => const _SecurityPage(),
      SettingsTab.notification => const _NotificationPage(),
    };
  }
}

// ---------------------------------------------------------------------------
// 本机信息
// ---------------------------------------------------------------------------
class _InfoPage extends StatefulWidget {
  const _InfoPage();

  @override
  State<_InfoPage> createState() => _InfoPageState();
}

class _InfoPageState extends State<_InfoPage> {
  late final String _cpu = SystemInfo.cpuName;
  late final String _memory = SystemInfo.memoryText;
  late final String _os = SystemInfo.osDescription;
  late final String _disk =
      '${Platform.environment['SystemDrive'] ?? 'C:'} 系统盘';

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final mac = SystemInfo.macAddress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ContentHeading(
          title: '本机信息',
          subtitle: '这台设备的身份与系统环境。',
        ),
        AppCard(
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: AppGradients.brand,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.2),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child:
                    const Icon(AppIcons.desktop, size: 26, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(controller.identity.name, style: AppText.sectionTitle),
                    const SizedBox(height: 4),
                    Text(
                      controller.settings.deviceNote.isEmpty
                          ? '这台电脑的识别码与备注'
                          : controller.settings.deviceNote,
                      style: AppText.hint,
                    ),
                  ],
                ),
              ),
              GhostButton(
                label: '修改名称',
                width: 90,
                onPressed: () => showTextDialog(
                  context,
                  title: '修改设备名称',
                  initial: controller.identity.name,
                  onConfirm: controller.updateDeviceName,
                ),
              ),
              const SizedBox(width: 8),
              GhostButton(
                label: '修改备注',
                width: 90,
                onPressed: () => showTextDialog(
                  context,
                  title: '修改备注',
                  initial: controller.settings.deviceNote,
                  onConfirm: (value) =>
                      controller.updateSettings((s) => s.deviceNote = value),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: '设备身份',
          children: [
            _KeyValueRow(
              label: '设备识别码',
              value: controller.displayId,
              monospace: true,
              trailing: TextLink(
                label: '复制',
                fontSize: 12.5,
                onTap: controller.copyDeviceId,
              ),
            ),
            const Hairline(),
            _KeyValueRow(
              label: '设备名称',
              value: controller.identity.name,
              trailing: TextLink(
                label: '修改',
                fontSize: 12.5,
                onTap: () => showTextDialog(
                  context,
                  title: '修改设备名称',
                  initial: controller.identity.name,
                  onConfirm: controller.updateDeviceName,
                ),
              ),
            ),
            const Hairline(),
            _KeyValueRow(
              label: '系统版本',
              value: _os.isEmpty ? '-' : _os.replaceAll('"', ''),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: '硬件信息',
          children: [
            _SpecGrid(
              items: [
                ('处理器', _cpu.isEmpty ? '-' : _cpu),
                ('内存', _memory.isEmpty ? '-' : _memory),
                ('主硬盘', _disk),
                ('显卡', '-'),
                ('MAC 地址', mac.isEmpty ? '-' : mac),
                ('网卡', mac.isEmpty ? '-' : mac),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: '应用数据',
          children: [
            Row(
              children: [
                const Icon(AppIcons.pluginFile,
                    size: 17, color: AppColors.textTertiary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    AppPaths.dataDir,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.hint,
                  ),
                ),
                const SizedBox(width: 12),
                TextLink(
                  label: '打开目录',
                  fontSize: 12.5,
                  onTap: () => Process.start(
                    'explorer.exe',
                    [AppPaths.dataDir],
                    mode: ProcessStartMode.detached,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _SpecGrid extends StatelessWidget {
  const _SpecGrid({required this.items});

  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 16) / 2;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.$1, style: AppText.tiny),
                      const SizedBox(height: 5),
                      Text(
                        item.$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodyStrong.copyWith(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 连接设置
// ---------------------------------------------------------------------------
class _ConnectionPage extends StatefulWidget {
  const _ConnectionPage();

  @override
  State<_ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<_ConnectionPage> {
  late final TextEditingController _url;
  late final AppController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AppScope.read(context);
    _url = TextEditingController(text: _controller.settings.relayUrl);
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _controller.relayStatus;
    final color = switch (status) {
      RelayStatus.online => AppColors.success,
      RelayStatus.connecting => AppColors.warning,
      RelayStatus.error => AppColors.danger,
      RelayStatus.disconnected => AppColors.textTertiary,
    };
    final label = switch (status) {
      RelayStatus.online => '已连接',
      RelayStatus.connecting => '正在连接',
      RelayStatus.error => _controller.host.statusDetail.value ?? '连接失败',
      RelayStatus.disconnected => '未连接',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ContentHeading(
          title: '连接设置',
          subtitle: '控制端与被控端需要连接同一个中继服务器。',
        ),
        _Section(
          title: '中继服务器',
          subtitle: '修改地址后会立即断开并重新注册本机。',
          children: [
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    controller: _url,
                    height: 42,
                    hint: 'ws://127.0.0.1:7080/ws',
                    prefixIcon: const Icon(Icons.dns_outlined,
                        size: 16, color: AppColors.textTertiary),
                    onSubmitted: (_) => _save(),
                  ),
                ),
                const SizedBox(width: 10),
                PrimaryButton(
                  label: '保存并重连',
                  width: 112,
                  height: 42,
                  onPressed: _save,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
                const Spacer(),
                if (status == RelayStatus.error)
                  TextLink(
                    label: '立即重试',
                    fontSize: 12,
                    onTap: _controller.host.retry,
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _Section(
          title: '连接说明',
          children: [
            _InfoLine(
              icon: Icons.lan_outlined,
              text: '局域网内填写运行中继服务的电脑 IP，例如 ws://192.168.1.10:7080/ws。',
            ),
            SizedBox(height: 12),
            _InfoLine(
              icon: Icons.cloud_outlined,
              text: '跨网络使用时，请将中继服务部署在公网服务器，并开放对应端口。',
            ),
            SizedBox(height: 12),
            _InfoLine(
              icon: AppIcons.lock,
              text: '所有远程会话都需要对方输入本机验证码。',
            ),
          ],
        ),
      ],
    );
  }

  void _save() {
    final value = _url.text.trim();
    if (value.isEmpty) {
      _controller.showToast('请输入中继服务器地址');
      return;
    }
    _controller.setRelayUrl(value);
    _controller.showToast('中继地址已保存，正在重新连接');
  }
}

// ---------------------------------------------------------------------------
// 远程画面
// ---------------------------------------------------------------------------
class _DesktopPage extends StatefulWidget {
  const _DesktopPage();

  @override
  State<_DesktopPage> createState() => _DesktopPageState();
}

class _DesktopPageState extends State<_DesktopPage> {
  late int _fps;
  late int _quality;
  late int _width;

  @override
  void initState() {
    super.initState();
    final settings = AppScope.read(context).settings;
    _fps = settings.fps;
    _quality = settings.jpegQuality;
    _width = settings.maxWidth;
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ContentHeading(
          title: '远程画面',
          subtitle: '调整本机作为被控端时发送的画面质量。',
        ),
        _Section(
          title: '画面参数',
          subtitle: '默认 1920 px / 85% / 30 FPS，4:4:4 无色度抽样，文字更清晰。',
          children: [
            Row(
              children: [
                const _LiveTag(label: '当前配置'),
                const SizedBox(width: 10),
                Text(
                  '$_width px · JPEG $_quality% · $_fps FPS',
                  style: AppText.hint,
                ),
              ],
            ),
            const SizedBox(height: 18),
            _SliderRow(
              label: '帧率',
              value: '$_fps FPS',
              valueValue: _fps.toDouble(),
              min: 5,
              max: 30,
              divisions: 25,
              onChanged: (value) => setState(() => _fps = value.round()),
              onChangeEnd: (value) {
                controller.updateSettings((s) => s.fps = value.round());
              },
            ),
            const SizedBox(height: 10),
            _SliderRow(
              label: 'JPEG 质量',
              value: '$_quality%',
              valueValue: _quality.toDouble(),
              min: 40,
              max: 95,
              divisions: 55,
              onChanged: (value) => setState(() => _quality = value.round()),
              onChangeEnd: (value) {
                controller.updateSettings((s) => s.jpegQuality = value.round());
              },
            ),
            const SizedBox(height: 18),
            const Text('最大分辨率', style: AppText.label),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              children: [
                for (final option in const [1280, 1600, 1920, 2560])
                  _OptionChip(
                    label: '$option px',
                    selected: _width == option,
                    onTap: () {
                      setState(() => _width = option);
                      controller.updateSettings((s) => s.maxWidth = option);
                    },
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: '会话体验',
          children: [
            _ToggleTile(
              icon: AppIcons.fullscreen,
              label: '连接后默认全屏',
              description: '远控其他设备时，自动进入全屏画面。',
              value: controller.settings.fullscreenOnConnect,
              onChanged: (value) => controller
                  .updateSettings((s) => s.fullscreenOnConnect = value),
            ),
            const SizedBox(height: 12),
            const _InfoLine(
              icon: AppIcons.infoSquare,
              text: '帧率越高、质量越高，画面越流畅清晰，同时占用更多带宽。',
            ),
          ],
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.valueValue,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final String value;
  final double valueValue;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: AppText.label),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            activeTrackColor: AppColors.primary,
            inactiveTrackColor: const Color(0xFFE4E7EF),
            thumbColor: Colors.white,
            overlayColor: AppColors.primary.withOpacity(0.08),
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 8,
              elevation: 2,
            ),
          ),
          child: Slider(
            value: valueValue,
            min: min,
            max: max,
            divisions: divisions,
            label: value,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ],
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : AppColors.surface,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? AppColors.primaryBorder : AppColors.inputBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 安全验证
// ---------------------------------------------------------------------------
class _SecurityPage extends StatefulWidget {
  const _SecurityPage();

  @override
  State<_SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<_SecurityPage> {
  bool _reveal = false;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final s = controller.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ContentHeading(
          title: '安全验证',
          subtitle: '验证码是本机唯一的接入凭证，请只分享给信任的人。',
        ),
        _Section(
          title: '远程协助本机',
          children: [
            _ToggleTile(
              icon: AppIcons.security,
              label: '允许远程协助本机',
              description: s.allowRemote
                  ? '已开启，对方使用识别码与验证码即可发起连接。'
                  : '已关闭，所有远程连接请求将被拒绝。',
              value: s.allowRemote,
              onChanged: (value) {
                controller.updateSettings((x) => x.allowRemote = value);
                controller.showToast(value ? '已允许远程协助本机' : '已停止接受远程协助');
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: '验证码',
          subtitle: '对方发起连接时需要输入此验证码。',
          trailing: TextLink(
            label: '重新生成',
            fontSize: 12.5,
            onTap: () async {
              final confirmed = await showConfirmDialog(
                context,
                title: '重新生成验证码',
                message: '旧验证码将立即失效，正在进行的会话不会中断。',
                confirmText: '重新生成',
              );
              if (confirmed) controller.regeneratePassword();
            },
          ),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFF0EFFF), Color(0xFFF8F6FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFDCD9FC)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(AppIcons.lock,
                        size: 19, color: AppColors.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('当前验证码', style: AppText.tiny),
                        const SizedBox(height: 4),
                        Text(
                          _reveal ? controller.identity.password : '••••••',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 5,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AppIconButton(
                    icon: _reveal ? AppIcons.eyeClose : AppIcons.eyeOpen,
                    size: 18,
                    color: AppColors.textSecondary,
                    tooltip: _reveal ? '隐藏验证码' : '显示验证码',
                    onTap: () => setState(() => _reveal = !_reveal),
                  ),
                  const SizedBox(width: 4),
                  GhostButton(
                    label: '复制验证码',
                    width: 92,
                    onPressed: controller.copyPassword,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const _InfoLine(
              icon: AppIcons.security,
              text: '星轨远控不保存任何远程设备的凭证，验证码仅用于校验本次连接。',
            ),
          ],
        ),
        const SizedBox(height: 16),
        const _Section(
          title: '连接保护',
          children: [
            _ProtectionRow(
              icon: AppIcons.lock,
              title: '验证码校验',
              detail: '每次远程连接都必须提供正确验证码。',
            ),
            SizedBox(height: 14),
            _ProtectionRow(
              icon: AppIcons.desktop,
              title: '按需采集画面',
              detail: '仅在会话期间采集屏幕，会话结束后立即停止。',
            ),
            SizedBox(height: 14),
            _ProtectionRow(
              icon: Icons.visibility_off_outlined,
              title: '不常驻后台',
              detail: '未连接时不会截取或上传任何屏幕内容。',
            ),
          ],
        ),
      ],
    );
  }
}

class _ProtectionRow extends StatelessWidget {
  const _ProtectionRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: const BoxDecoration(
            color: AppColors.accentSoft,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: AppColors.accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.bodyStrong.copyWith(fontSize: 13)),
              const SizedBox(height: 2),
              Text(detail, style: AppText.hint),
            ],
          ),
        ),
        const Icon(AppIcons.checkFill, size: 17, color: AppColors.success),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 消息提醒
// ---------------------------------------------------------------------------
class _NotificationPage extends StatelessWidget {
  const _NotificationPage();

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final s = controller.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ContentHeading(
          title: '消息提醒',
          subtitle: '远程会话的关键事件会记录在消息中心。',
        ),
        _Section(
          title: '提醒方式',
          children: [
            _ToggleTile(
              icon: AppIcons.remoteControl,
              label: '远程控制提醒',
              description: '会话开始或结束时，在消息中心生成一条记录。',
              value: s.notifyControl,
              onChanged: (value) =>
                  controller.updateSettings((x) => x.notifyControl = value),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: '最近消息',
          trailing: TextLink(
            label: '全部已读',
            fontSize: 12.5,
            onTap: controller.markFeedRead,
          ),
          children: [
            if (controller.feed.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: Text('暂无消息', style: AppText.hint),
                ),
              )
            else
              for (var i = 0; i < controller.feed.length; i++) ...[
                if (i > 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Hairline(),
                  ),
                _FeedRow(item: controller.feed[i]),
              ],
          ],
        ),
      ],
    );
  }
}

class _FeedRow extends StatelessWidget {
  const _FeedRow({required this.item});

  final FeedItem item;

  @override
  Widget build(BuildContext context) {
    final color = switch (item.kind) {
      'security' => AppColors.warning,
      'session' => AppColors.primary,
      _ => AppColors.accent,
    };
    final icon = switch (item.kind) {
      'security' => AppIcons.lock,
      'session' => AppIcons.remoteControl,
      _ => AppIcons.device,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(item.title,
                        style: AppText.bodyStrong.copyWith(fontSize: 13)),
                  ),
                  Text(_relative(item.time), style: AppText.tiny),
                  if (!item.read) ...[
                    const SizedBox(width: 6),
                    const RedDot(size: 5),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Text(item.body, style: AppText.hint),
            ],
          ),
        ),
      ],
    );
  }

  String _relative(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------
class _ContentHeading extends StatelessWidget {
  const _ContentHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              )),
          const SizedBox(height: 4),
          Text(subtitle, style: AppText.hint),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  )),
              const Spacer(),
              if (trailing != null) trailing!,
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: AppText.hint),
          ],
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.icon,
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: value ? AppColors.primarySoft : AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: value ? AppColors.primaryBorder : AppColors.border,
            ),
          ),
          child: Icon(
            icon,
            size: 18,
            color: value ? AppColors.primary : AppColors.textTertiary,
          ),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppText.bodyStrong),
              const SizedBox(height: 2),
              Text(description, style: AppText.hint),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch(
          value: value,
          onChanged: onChanged,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({
    required this.label,
    required this.value,
    this.trailing,
    this.monospace = false,
  });

  final String label;
  final String value;
  final Widget? trailing;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          SizedBox(width: 132, child: Text(label, style: AppText.hint)),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.bodySecondary.copyWith(
                color: AppColors.textPrimary,
                letterSpacing: monospace ? 1.2 : 0,
                fontWeight: monospace ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 16, color: AppColors.textTertiary),
        ),
        const SizedBox(width: 9),
        Expanded(child: Text(text, style: AppText.hint.copyWith(height: 1.6))),
      ],
    );
  }
}

class _LiveTag extends StatelessWidget {
  const _LiveTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}
