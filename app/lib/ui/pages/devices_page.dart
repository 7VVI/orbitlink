import 'package:flutter/material.dart';

import '../../core/app_controller.dart';
import '../../core/models.dart';
import '../../engine/host_engine.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../app_scope.dart';
import '../widgets/dialogs.dart';
import '../widgets/ui_kit.dart';

class DevicesPage extends StatefulWidget {
  const DevicesPage({super.key});

  @override
  State<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends State<DevicesPage> {
  bool _grid = true;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final recents = controller.config.recents;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(30, 26, 30, 30),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppPageHeader(
                title: '设备',
                subtitle: '管理本机与最近远程协助过的设备。',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ViewToggle(
                      grid: _grid,
                      onChanged: (value) => setState(() => _grid = value),
                    ),
                    const SizedBox(width: 10),
                    PrimaryButton(
                      label: '添加设备',
                      icon: AppIcons.addDevice,
                      width: 118,
                      onPressed: () => _showAddDevice(controller),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              _SelfDeviceCard(controller: controller),
              const SizedBox(height: 26),
              Row(
                children: [
                  const Text('最近访问', style: AppText.sectionTitle),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      '${recents.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (recents.isEmpty)
                    const Text('完成一次远程会话后自动记录', style: AppText.tiny),
                ],
              ),
              const SizedBox(height: 14),
              if (recents.isEmpty)
                _EmptyDevices(
                  onTap: () => controller.setTab(NavTab.assist),
                )
              else if (_grid)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 680 ? 3 : 2;
                    final width =
                        (constraints.maxWidth - 16 * (columns - 1)) / columns;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        for (final device in recents)
                          SizedBox(
                            width: width,
                            child: _RecentTile(
                              device: device,
                              onRemote: () =>
                                  controller.prefillAssist(device.id),
                              onDetail: () => _showDetail(controller, device),
                              onDelete: () => _deleteDevice(controller, device),
                            ),
                          ),
                      ],
                    );
                  },
                )
              else
                AppCard(
                  padding:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  child: Column(
                    children: [
                      for (var i = 0; i < recents.length; i++) ...[
                        if (i > 0) const Hairline(),
                        _RecentListRow(
                          device: recents[i],
                          onRemote: () =>
                              controller.prefillAssist(recents[i].id),
                          onDetail: () => _showDetail(controller, recents[i]),
                          onDelete: () => _deleteDevice(controller, recents[i]),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddDevice(AppController controller) => showAppDialog(
        context: context,
        title: '添加设备',
        content: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: AppGradients.brand,
                borderRadius: BorderRadius.circular(16),
              ),
              child:
                  const Icon(AppIcons.addDevice, size: 26, color: Colors.white),
            ),
            const SizedBox(height: 16),
            const Text(
              '在另一台电脑或手机上安装星轨远控，输入本机识别码即可发起协助。',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  const Text('本机识别码', style: AppText.hint),
                  const SizedBox(height: 6),
                  Text(
                    controller.displayId,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          GhostButton(
            label: '关闭',
            width: 76,
            onPressed: () => Navigator.of(context).pop(),
          ),
          PrimaryButton(
            label: '复制识别码',
            width: 116,
            height: 36,
            onPressed: () {
              controller.copyDeviceId();
              Navigator.of(context).pop();
            },
          ),
        ],
      );

  Future<void> _showDetail(
      AppController controller, RecentDevice device) async {
    final platform = device.platform == 'android' ? 'Android' : 'Windows';
    await showAppDialog(
      context: context,
      title: '设备详情',
      content: Column(
        children: [
          _DetailLine(label: '设备名称', value: device.name),
          _DetailLine(label: '识别码', value: formatDeviceId(device.id)),
          _DetailLine(label: '平台', value: platform),
          _DetailLine(label: '最近连接', value: _formatTime(device.lastConnected)),
        ],
      ),
      actions: [
        GhostButton(
          label: '删除记录',
          width: 90,
          borderColor: const Color(0xFFF7C9C4),
          textColor: AppColors.danger,
          onPressed: () {
            Navigator.of(context).pop();
            _deleteDevice(controller, device);
          },
        ),
        PrimaryButton(
          label: '发起协助',
          width: 100,
          height: 36,
          onPressed: () {
            Navigator.of(context).pop();
            controller.prefillAssist(device.id);
          },
        ),
      ],
    );
  }

  Future<void> _deleteDevice(
      AppController controller, RecentDevice device) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '删除设备记录',
      message: '将从最近访问中移除「${device.name}」，不会影响对方设备。',
      confirmText: '删除',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    controller.config.recents.removeWhere((item) => item.id == device.id);
    ConfigStore.save(controller.config);
    controller.showToast('已删除设备记录');
    setState(() {});
  }

  String _formatTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 30) return '${diff.inDays} 天前';
    return '${time.year}/${time.month}/${time.day}';
  }
}

class _SelfDeviceCard extends StatelessWidget {
  const _SelfDeviceCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final status = controller.relayStatus;
    final color = switch (status) {
      RelayStatus.online => AppColors.success,
      RelayStatus.connecting => AppColors.warning,
      RelayStatus.error => AppColors.danger,
      RelayStatus.disconnected => AppColors.textTertiary,
    };
    final label = switch (status) {
      RelayStatus.online => '中继在线',
      RelayStatus.connecting => '连接中',
      RelayStatus.error => '连接异常',
      RelayStatus.disconnected => '未连接',
    };
    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: AppGradients.brand,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.18),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child:
                    const Icon(AppIcons.desktop, size: 24, color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            controller.identity.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.sectionTitle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const _Tag(
                          label: '本机',
                          color: AppColors.primary,
                          background: AppColors.primarySoft,
                        ),
                        const SizedBox(width: 6),
                        const _Tag(
                          label: 'Windows',
                          color: AppColors.textSecondary,
                          background: AppColors.surfaceMuted,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      controller.settings.deviceNote.isEmpty
                          ? '这台电脑已准备好接受远程协助'
                          : controller.settings.deviceNote,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.hint,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(AppRadii.chip),
                  border: Border.all(color: color.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration:
                          BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              GhostButton(
                label: '复制识别码',
                width: 104,
                onPressed: controller.copyDeviceId,
              ),
              const SizedBox(width: 8),
              PrimaryButton(
                label: '管理设备',
                width: 100,
                icon: AppIcons.setting,
                onPressed: () {
                  controller.setSettingsTab(SettingsTab.info);
                  controller.setTab(NavTab.settings);
                },
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.tag_rounded,
                    size: 16, color: AppColors.textTertiary),
                const SizedBox(width: 8),
                const Text('识别码', style: AppText.hint),
                const SizedBox(width: 12),
                Text(
                  controller.displayId,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.6,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 6),
                AppIconButton(
                  icon: AppIcons.copy,
                  size: 14,
                  color: AppColors.primary,
                  tooltip: '复制识别码',
                  onTap: controller.copyDeviceId,
                ),
                const Spacer(),
                const Icon(Icons.dns_outlined,
                    size: 15, color: AppColors.textTertiary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _shortRelay(controller.settings.relayUrl),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.tiny,
                  ),
                ),
                const SizedBox(width: 10),
                TextLink(
                  label: '中继设置',
                  fontSize: 12,
                  onTap: () {
                    controller.setSettingsTab(SettingsTab.general);
                    controller.setTab(NavTab.settings);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({
    required this.device,
    required this.onRemote,
    required this.onDetail,
    required this.onDelete,
  });

  final RecentDevice device;
  final VoidCallback onRemote;
  final VoidCallback onDetail;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return HoverBuilder(
      builder: (hovered) => GestureDetector(
        onTap: onRemote,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 148,
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hovered ? AppColors.primaryBorder : AppColors.border,
            ),
            boxShadow: hovered ? AppShadows.card : AppShadows.soft,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Icon(
                      _platformIcon(device.platform),
                      size: 19,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  _MoreMenu(onDetail: onDetail, onDelete: onDelete),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                device.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${formatDeviceId(device.id)} · ${_platformName(device.platform)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.tiny,
              ),
              const Spacer(),
              Row(
                children: [
                  const Icon(Icons.schedule_rounded,
                      size: 13, color: AppColors.textTertiary),
                  const SizedBox(width: 5),
                  Text(_relativeTime(device.lastConnected),
                      style: AppText.tiny),
                  const Spacer(),
                  const Text(
                    '远程协助',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  const Icon(AppIcons.arrowRight,
                      size: 16, color: AppColors.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentListRow extends StatelessWidget {
  const _RecentListRow({
    required this.device,
    required this.onRemote,
    required this.onDetail,
    required this.onDelete,
  });

  final RecentDevice device;
  final VoidCallback onRemote;
  final VoidCallback onDetail;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return HoverBuilder(
      builder: (hovered) => GestureDetector(
        onTap: onRemote,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 62,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: hovered ? AppColors.surfaceMuted : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Icon(
                  _platformIcon(device.platform),
                  size: 17,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Text(
                  device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodyStrong,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(formatDeviceId(device.id), style: AppText.hint),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  '上次连接 ${_relativeTime(device.lastConnected)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.hint,
                ),
              ),
              TextLink(label: '远程协助', fontSize: 12, onTap: onRemote),
              const SizedBox(width: 6),
              _MoreMenu(onDetail: onDetail, onDelete: onDelete),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.onDetail, required this.onDelete});

  final VoidCallback onDetail;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '更多',
      offset: const Offset(0, 30),
      icon: const Icon(AppIcons.more2, size: 18, color: AppColors.textTertiary),
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'detail', height: 36, child: Text('设备详情')),
        PopupMenuItem(value: 'delete', height: 36, child: Text('删除记录')),
      ],
      onSelected: (value) => value == 'detail' ? onDetail() : onDelete(),
    );
  }
}

class _EmptyDevices extends StatelessWidget {
  const _EmptyDevices({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 38),
      child: Column(
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: const BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.18),
                    ),
                  ),
                ),
                const Icon(AppIcons.device, size: 26, color: AppColors.primary),
                Positioned(
                  right: 10,
                  top: 12,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('还没有最近连接', style: AppText.sectionTitle),
          const SizedBox(height: 6),
          const Text(
            '完成一次远程协助后，对方设备会显示在这里。',
            style: AppText.hint,
          ),
          const SizedBox(height: 18),
          PrimaryButton(
            label: '发起远程协助',
            icon: AppIcons.remoteControl,
            width: 160,
            onPressed: onTap,
          ),
        ],
      ),
    );
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.grid, required this.onChanged});

  final bool grid;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          _ViewOption(
            icon: AppIcons.gridStyle,
            selected: grid,
            onTap: () => onChanged(true),
          ),
          _ViewOption(
            icon: AppIcons.listStyle,
            selected: !grid,
            onTap: () => onChanged(false),
          ),
        ],
      ),
    );
  }
}

class _ViewOption extends StatelessWidget {
  const _ViewOption({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 17,
          color: selected ? AppColors.primary : AppColors.textTertiary,
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({
    required this.label,
    required this.color,
    required this.background,
  });

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(label, style: AppText.hint),
          ),
          Expanded(
            child: Text(
              value,
              style: AppText.bodySecondary.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

IconData _platformIcon(String platform) => switch (platform) {
      'android' => AppIcons.android,
      'win' || 'windows' => AppIcons.desktop,
      _ => AppIcons.device,
    };

String _platformName(String platform) => switch (platform) {
      'android' => 'Android',
      'win' || 'windows' => 'Windows',
      _ => '未知平台',
    };

String _relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
  if (diff.inDays < 1) return '${diff.inHours} 小时前';
  if (diff.inDays < 30) return '${diff.inDays} 天前';
  return '${time.year}/${time.month}/${time.day}';
}

String _shortRelay(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return url;
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '${uri.host}$port';
}
