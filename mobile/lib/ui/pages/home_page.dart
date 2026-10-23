import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/host_bridge.dart';
import '../../core/mobile_controller.dart';
import '../../core/mobile_scope.dart';
import '../../core/protocol.dart';
import '../brand.dart';
import '../theme.dart';
import '../widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _target = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _showPassword = false;
  bool _starting = false;
  bool _stopping = false;
  String? _consumedDraft;

  @override
  void initState() {
    super.initState();
    _target.addListener(_onChanged);
    _password.addListener(_onChanged);
  }

  @override
  void dispose() {
    _target.removeListener(_onChanged);
    _password.removeListener(_onChanged);
    _target.dispose();
    _password.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  bool get _canConnect =>
      _target.text.replaceAll(RegExp(r'\D'), '').length == 9 &&
      _password.text.trim().isNotEmpty;

  void _applyDraft(MobileController controller) {
    final draft = controller.targetDraft;
    if (draft == null || draft == _consumedDraft) return;
    _consumedDraft = draft;
    _target.text = draft;
    controller.takeTargetDraft();
  }

  @override
  Widget build(BuildContext context) {
    final controller = MobileScope.of(context);
    _applyDraft(controller);
    final host = controller.config;
    final status = controller.status;
    final recents = controller.recents;
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(status: status),
          Expanded(
            child: RefreshIndicator(
              onRefresh: controller.refreshOnResume,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  if (controller.bridgeError != null)
                    _Notice(
                      icon: Icons.warning_amber_rounded,
                      color: AppColors.warning,
                      message: controller.bridgeError!,
                    ),
                  _hostSection(controller, host, status),
                  const SizedBox(height: 36),
                  _connectSection(controller),
                  if (recents.isNotEmpty) ...[
                    const SizedBox(height: 26),
                    Row(
                      children: [
                        const Text('最近连接', style: AppText.caption),
                        const Spacer(),
                        Text('${recents.length} 台设备', style: AppText.caption),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final device in recents.take(5))
                          _RecentChip(
                            device: device,
                            onTap: () {
                              _target.text = device.id;
                              _password.clear();
                              setState(() {});
                            },
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 40),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline_rounded,
                          size: 13, color: AppColors.textTertiary),
                      SizedBox(width: 5),
                      Text('无需账号 · 设备身份只保存在本机', style: AppText.caption),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hostSection(
      MobileController controller, HostConfig host, HostStatus status) {
    final running = status.running;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '本机被控',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    host.allowRemote ? '允许他人远程控制这台手机' : '已暂停接受远程协助',
                    style: AppText.caption,
                  ),
                ],
              ),
            ),
            Switch(
              value: host.allowRemote,
              onChanged: controller.setAllowRemote,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 10, 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('本机识别码', style: AppText.caption),
                        const SizedBox(height: 5),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            formatDeviceId(host.id),
                            style: const TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.6,
                              height: 1.2,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '复制识别码',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: host.id));
                      controller.showMessage('识别码已复制');
                    },
                    icon: const Icon(Icons.copy_rounded,
                        size: 18, color: AppColors.textTertiary),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Text('验证码', style: AppText.caption),
                  const SizedBox(width: 10),
                  Text(
                    _showPassword ? host.password : '••••••',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 3,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: _showPassword ? '隐藏验证码' : '显示验证码',
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 18,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: '复制验证码',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: host.password));
                      controller.showMessage('验证码已复制');
                    },
                    icon: const Icon(Icons.copy_rounded,
                        size: 17, color: AppColors.textTertiary),
                  ),
                ],
              ),
              if (running) ...[
                const Divider(height: 14),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: status.sessionActive
                            ? AppColors.danger
                            : AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        status.sessionActive
                            ? '${status.controllerName ?? '远程用户'} 正在控制本机'
                            : '等待控制端连接',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    if (status.fps > 0 && status.sessionActive)
                      Text('${status.fps} FPS', style: AppText.caption),
                    const SizedBox(width: 8),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (running)
          OutlinedButton.icon(
            onPressed: (!_stopping && host.allowRemote)
                ? () => _stopHosting(controller)
                : null,
            icon: const Icon(Icons.stop_circle_outlined, size: 18),
            label: Text(_stopping ? '正在停止…' : '停止本机被控'),
          )
        else
          FilledButton.icon(
            onPressed: (!_starting && host.allowRemote)
                ? () => _startHosting(controller)
                : null,
            icon: const Icon(Icons.play_circle_outline, size: 18),
            label: Text(_starting ? '正在请求授权…' : '开启本机被控'),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(
              Icons.screenshot_monitor_outlined,
              size: 14,
              color: running ? AppColors.success : AppColors.textTertiary,
            ),
            const SizedBox(width: 5),
            Text(
              running ? '屏幕采集中' : '屏幕未共享',
              style: AppText.caption,
            ),
            const SizedBox(width: 14),
            GestureDetector(
              onTap: controller.openAccessibility,
              child: Row(
                children: [
                  Icon(
                    Icons.accessibility_new,
                    size: 14,
                    color: status.accessibilityEnabled
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    status.accessibilityEnabled ? '输入服务已开启' : '输入服务未开启',
                    style: TextStyle(
                      fontSize: 12,
                      color: status.accessibilityEnabled
                          ? AppColors.textTertiary
                          : AppColors.warning,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (!host.allowRemote) ...[
          const SizedBox(height: 6),
          const Text('请先允许远程协助本机', style: AppText.caption),
        ],
      ],
    );
  }

  Widget _connectSection(MobileController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '远程协助他人',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 3),
        const Text('输入对方识别码与验证码，发起远程协助', style: AppText.caption),
        const SizedBox(height: 14),
        Container(
          height: 54,
          padding: const EdgeInsets.only(left: 14, right: 4),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              const Icon(Icons.tag_rounded,
                  size: 17, color: AppColors.textTertiary),
              const SizedBox(width: 8),
              Expanded(
                flex: 5,
                child: TextField(
                  controller: _target,
                  keyboardType: TextInputType.number,
                  maxLength: 9,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(9),
                  ],
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1,
                    color: AppColors.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    counterText: '',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: '对方识别码',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      letterSpacing: 0,
                      color: AppColors.placeholder,
                    ),
                  ),
                ),
              ),
              Container(width: 1, height: 22, color: AppColors.divider),
              const SizedBox(width: 10),
              const Icon(Icons.lock_outline_rounded,
                  size: 16, color: AppColors.textTertiary),
              const SizedBox(width: 7),
              Expanded(
                flex: 4,
                child: TextField(
                  controller: _password,
                  obscureText: !_showPassword,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    letterSpacing: _showPassword ? 0 : 2,
                    color: AppColors.textPrimary,
                  ),
                  onSubmitted: (_) => _connect(controller),
                  decoration: const InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: '验证码',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      letterSpacing: 0,
                      color: AppColors.placeholder,
                    ),
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: _showPassword ? '隐藏验证码' : '显示验证码',
                onPressed: () => setState(() => _showPassword = !_showPassword),
                icon: Icon(
                  _showPassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 17,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _canConnect ? () => _connect(controller) : null,
          child: const Text('连接'),
        ),
      ],
    );
  }

  Future<void> _startHosting(MobileController controller) async {
    final status = controller.status;
    if (!status.accessibilityEnabled) {
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('输入服务未开启'),
          content: const Text(
            '开启「星轨输入服务」后，控制端才能点击、滑动和输入文字。\n'
            '也可以先仅共享屏幕，稍后在系统设置中开启。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('cancel'),
              child: const Text('取消',
                  style: TextStyle(color: AppColors.textTertiary)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('view'),
              child: const Text('仅共享屏幕'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('settings'),
              child: const Text('去开启',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
      if (!mounted || choice == null || choice == 'cancel') return;
      if (choice == 'settings') {
        await controller.openAccessibility();
        return;
      }
    }
    setState(() => _starting = true);
    try {
      final started = await controller.startHosting();
      if (!mounted) return;
      if (!started) {
        controller.showMessage('未完成屏幕共享授权');
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stopHosting(MobileController controller) async {
    final ok = await confirmDialog(
      context,
      title: '停止本机被控',
      message: '停止后将结束当前会话，并释放屏幕采集。确定继续？',
      confirmLabel: '停止',
      danger: true,
    );
    if (!ok || !mounted) return;
    setState(() => _stopping = true);
    try {
      await controller.stopHosting();
    } finally {
      if (mounted) setState(() => _stopping = false);
    }
  }

  void _connect(MobileController controller) {
    final target = _target.text.replaceAll(RegExp(r'\D'), '');
    if (target.length != 9) {
      controller.showMessage('请输入 9 位识别码');
      return;
    }
    final password = _password.text.trim();
    if (password.isEmpty) {
      controller.showMessage('请输入对方验证码');
      return;
    }
    final created = controller.startSession(
      target: target,
      password: password,
    );
    if (created == null) return;
    _password.clear();
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.status});

  final HostStatus status;

  @override
  Widget build(BuildContext context) {
    final running = status.running;
    final color = switch (status.relay) {
      'online' => AppColors.success,
      'connecting' => AppColors.warning,
      'error' => AppColors.danger,
      _ => AppColors.textTertiary,
    };
    final label = status.sessionActive
        ? '被控中'
        : running
            ? '等待连接'
            : '未开启';
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          const BrandLockup(markSize: 28),
          const Spacer(),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            running ? label : '未开启',
            style: TextStyle(fontSize: 11.5, color: color),
          ),
        ],
      ),
    );
  }
}

class _RecentChip extends StatelessWidget {
  const _RecentChip({required this.device, required this.onTap});

  final RecentDevice device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = device.platform == 'android'
        ? Icons.phone_android
        : Icons.desktop_windows_outlined;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.textTertiary),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: Text(
                device.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message, style: TextStyle(fontSize: 12, color: color)),
          ),
        ],
      ),
    );
  }
}
