import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_controller.dart';
import '../../core/models.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../app_scope.dart';
import '../widgets/ui_kit.dart';

class AssistPage extends StatefulWidget {
  const AssistPage({super.key});

  @override
  State<AssistPage> createState() => _AssistPageState();
}

class _AssistPageState extends State<AssistPage> {
  final _target = TextEditingController();
  final _password = TextEditingController();
  final _targetFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _passwordVisible = false;
  bool _restoredConnection = false;
  String? _appliedPrefill;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_restoredConnection) return;
    _restoredConnection = true;
    final config = AppScope.read(context).config;
    if (config.lastTargetId.isNotEmpty) {
      _target.text = config.lastTargetId;
      _password.text = config.lastPassword;
    }
  }

  @override
  void dispose() {
    _target.dispose();
    _password.dispose();
    _targetFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _applyPrefill(AppController controller) {
    final prefill = controller.prefillTarget;
    if (prefill == null || prefill == _appliedPrefill) return;
    _appliedPrefill = prefill;
    _target.text = prefill;
    _password.text = prefill == controller.config.lastTargetId
        ? controller.config.lastPassword
        : '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      controller.prefillTarget = null;
      _passwordFocus.requestFocus();
    });
  }

  void _connect(AppController controller) {
    final target = _target.text.replaceAll(RegExp(r'\D'), '');
    if (target.length != 9) {
      controller.showToast('请输入 9 位设备识别码');
      _targetFocus.requestFocus();
      return;
    }
    final password = _password.text.trim();
    if (password.isEmpty) {
      controller.showToast('请输入对方设备的验证码');
      _passwordFocus.requestFocus();
      return;
    }
    controller.startSession(
      target: target,
      password: password,
      mode: 'desktop',
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    _applyPrefill(controller);
    final settings = controller.settings;
    final recents = controller.config.recents;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(40, 40, 40, 36),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '远程协助本机',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  AppSwitch(
                    value: settings.allowRemote,
                    onChanged: (value) {
                      controller.updateSettings((s) => s.allowRemote = value);
                      controller.showToast(value ? '已允许远程协助本机' : '已停止接受远程协助');
                    },
                  ),
                  const SizedBox(width: 8),
                  Text(
                    settings.allowRemote ? '已开启' : '已暂停',
                    style: AppText.hint,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: _IdentityValue(
                      label: '本机识别码',
                      onCopy: controller.copyDeviceId,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          formatDeviceId(controller.identity.id),
                          style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.6,
                            height: 1.15,
                            color: AppColors.textPrimary,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                  Expanded(
                    flex: 2,
                    child: _IdentityValue(
                      label: '验证码',
                      onCopy: controller.copyPassword,
                      extra: AppIconButton(
                        icon: _passwordVisible
                            ? AppIcons.eyeClose
                            : AppIcons.eyeOpen,
                        size: 16,
                        color: AppColors.textTertiary,
                        tooltip: _passwordVisible ? '隐藏验证码' : '显示验证码',
                        onTap: () => setState(
                            () => _passwordVisible = !_passwordVisible),
                      ),
                      child: Text(
                        _passwordVisible
                            ? controller.identity.password
                            : '••••••',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 4,
                          height: 1.3,
                          color: AppColors.textPrimary,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (controller.hostSession != null) ...[
                const SizedBox(height: 20),
                _ActiveSessionBar(controller: controller),
              ],
              const SizedBox(height: 42),
              const Text(
                '远程协助他人',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ListenableBuilder(
                      listenable:
                          Listenable.merge([_targetFocus, _passwordFocus]),
                      builder: (context, _) {
                        final focused =
                            _targetFocus.hasFocus || _passwordFocus.hasFocus;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          height: 58,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: focused
                                  ? AppColors.primary
                                  : AppColors.inputBorder,
                              width: focused ? 1.3 : 1,
                            ),
                            boxShadow: focused
                                ? [
                                    BoxShadow(
                                      color:
                                          AppColors.primary.withOpacity(0.10),
                                      spreadRadius: 3,
                                    ),
                                  ]
                                : AppShadows.soft,
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.tag_rounded,
                                  size: 18, color: AppColors.textTertiary),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 3,
                                child: TextField(
                                  controller: _target,
                                  focusNode: _targetFocus,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(9),
                                  ],
                                  cursorColor: AppColors.primary,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 1.2,
                                    color: AppColors.textPrimary,
                                    fontFeatures: [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                  onSubmitted: (_) =>
                                      _passwordFocus.requestFocus(),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    filled: false,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    contentPadding: EdgeInsets.zero,
                                    hintText: '请输入对方识别码',
                                    hintStyle: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w400,
                                      letterSpacing: 0,
                                      color: AppColors.placeholder,
                                    ),
                                  ),
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 24,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 14),
                                color: AppColors.border,
                              ),
                              const Icon(AppIcons.lock,
                                  size: 16, color: AppColors.textTertiary),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: _password,
                                  focusNode: _passwordFocus,
                                  obscureText: !_passwordVisible,
                                  cursorColor: AppColors.primary,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: _passwordVisible ? 0 : 3,
                                    color: AppColors.textPrimary,
                                  ),
                                  onSubmitted: (_) => _connect(controller),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    filled: false,
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    contentPadding: EdgeInsets.zero,
                                    hintText: '验证码',
                                    hintStyle: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w400,
                                      letterSpacing: 0,
                                      color: AppColors.placeholder,
                                    ),
                                  ),
                                ),
                              ),
                              AppIconButton(
                                icon: _passwordVisible
                                    ? AppIcons.eyeClose
                                    : AppIcons.eyeOpen,
                                size: 16,
                                color: AppColors.textTertiary,
                                tooltip: _passwordVisible ? '隐藏验证码' : '显示验证码',
                                onTap: () => setState(
                                    () => _passwordVisible = !_passwordVisible),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  GradientButton(
                    label: '连接',
                    width: 128,
                    height: 58,
                    onPressed: () => _connect(controller),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Row(
                children: [
                  Icon(AppIcons.lock, size: 13, color: AppColors.textTertiary),
                  SizedBox(width: 6),
                  Text(
                    '连接需要对方验证码，画面仅在远程会话期间传输。',
                    style: AppText.tiny,
                  ),
                ],
              ),
              if (recents.isNotEmpty) ...[
                const SizedBox(height: 30),
                Row(
                  children: [
                    const Text('最近连接', style: AppText.sectionTitle),
                    const Spacer(),
                    Text('${recents.length} 台设备', style: AppText.tiny),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final device in recents.take(5))
                      _RecentChip(
                        device: device,
                        onTap: () {
                          _target.text = device.id;
                          _password.text =
                              device.id == controller.config.lastTargetId
                                  ? controller.config.lastPassword
                                  : '';
                          _passwordFocus.requestFocus();
                        },
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IdentityValue extends StatelessWidget {
  const _IdentityValue({
    required this.label,
    required this.child,
    required this.onCopy,
    this.extra,
  });

  final String label;
  final Widget child;
  final VoidCallback onCopy;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: AppText.hint),
            const SizedBox(width: 4),
            AppIconButton(
              icon: AppIcons.copy,
              size: 13,
              color: AppColors.textTertiary,
              tooltip: '复制$label',
              padding: const EdgeInsets.all(4),
              onTap: onCopy,
            ),
            if (extra != null) ...[
              const SizedBox(width: 2),
              extra!,
            ],
          ],
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _ActiveSessionBar extends StatelessWidget {
  const _ActiveSessionBar({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final info = controller.hostSession!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
      decoration: BoxDecoration(
        color: AppColors.dangerSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCD9D5)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: AppColors.danger,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.danger.withOpacity(0.35),
                  spreadRadius: 4,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${info.controllerName} 正在控制本机',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          TextLink(
            label: '结束协助',
            color: AppColors.danger,
            fontSize: 12.5,
            onTap: controller.host.endSession,
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
    final icon = switch (device.platform) {
      'android' => AppIcons.android,
      _ => AppIcons.desktop,
    };
    return HoverBuilder(
      builder: (hovered) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: hovered ? AppColors.surfaceMuted : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: hovered ? AppColors.primaryBorder : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: AppColors.textSecondary),
              const SizedBox(width: 7),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: Text(
                  device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(formatDeviceId(device.id), style: AppText.tiny),
            ],
          ),
        ),
      ),
    );
  }
}
