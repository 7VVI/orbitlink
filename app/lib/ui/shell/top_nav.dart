import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/app_controller.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../app_scope.dart';
import '../widgets/brand.dart';
import '../widgets/ui_kit.dart';

class TopNav extends StatelessWidget {
  const TopNav({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    return Container(
      height: 72,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => windowManager.startDragging(),
              onDoubleTap: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const BrandLockup(markSize: 32),
                  const SizedBox(width: 34),
                  _NavItem(
                    label: '远程协助',
                    icon: AppIcons.remoteControl,
                    selected: controller.tab == NavTab.assist,
                    onTap: () => controller.setTab(NavTab.assist),
                  ),
                  const SizedBox(width: 4),
                  _NavItem(
                    label: '设备',
                    icon: AppIcons.device,
                    selected: controller.tab == NavTab.devices,
                    onTap: () => controller.setTab(NavTab.devices),
                  ),
                  const Spacer(),
                  _SearchBox(
                    active: controller.searchOpen,
                    onTap: () => controller.toggleSearch(),
                  ),
                  const SizedBox(width: 8),
                  _IconAction(
                    icon: AppIcons.setting,
                    tooltip: '设置',
                    active: controller.tab == NavTab.settings,
                    onTap: () => controller.setTab(NavTab.settings),
                  ),
                  _IconAction(
                    icon: AppIcons.notification,
                    tooltip: '消息',
                    badge: controller.unreadCount > 0,
                    active: controller.notificationsOpen,
                    onTap: () => controller.toggleNotifications(),
                  ),
                  const SizedBox(width: 8),
                  const _TopDivider(),
                  const SizedBox(width: 8),
                  _WindowAction(
                    icon: AppIcons.minimize,
                    tooltip: '最小化',
                    onTap: () => windowManager.minimize(),
                  ),
                  _WindowAction(
                    icon: AppIcons.close,
                    tooltip: '关闭',
                    onTap: () => windowManager.close(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HoverBuilder(
      builder: (hovered) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primarySoft
                : hovered
                    ? AppColors.surfaceMuted
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 18,
                  color: selected ? AppColors.primary : AppColors.textMuted),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return HoverBuilder(
      builder: (hovered) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 248,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: active
                ? AppColors.surface
                : hovered
                    ? const Color(0xFFF1F3F8)
                    : AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? AppColors.primary : AppColors.border,
            ),
          ),
          child: const Row(
            children: [
              Icon(AppIcons.search, size: 16, color: AppColors.textTertiary),
              SizedBox(width: 7),
              Text('搜索设备或识别码',
                  style:
                      TextStyle(fontSize: 12.5, color: AppColors.textTertiary)),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.active = false,
    this.badge = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool active;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final child = HoverBuilder(
      builder: (hovered) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 36,
          height: 36,
          margin: const EdgeInsets.only(left: 4),
          decoration: BoxDecoration(
            color: active
                ? AppColors.primarySoft
                : hovered
                    ? AppColors.surfaceMuted
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon,
                  size: 19,
                  color: active ? AppColors.primary : AppColors.textSecondary),
              if (badge)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.surface, width: 1.2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
  }
}

class _WindowAction extends StatelessWidget {
  const _WindowAction({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final child = HoverBuilder(
      builder: (hovered) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 30,
          height: 36,
          margin: const EdgeInsets.only(left: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovered ? AppColors.surfaceMuted : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 17, color: AppColors.textMuted),
        ),
      ),
    );
    return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
  }
}

class _TopDivider extends StatelessWidget {
  const _TopDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 22, color: AppColors.border);
  }
}
