import 'package:flutter/material.dart';

import '../../engine/host_engine.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../app_scope.dart';
import '../overlays/notifications_overlay.dart';
import '../overlays/search_overlay.dart';
import '../pages/assist_page.dart';
import '../pages/devices_page.dart';
import '../pages/session_page.dart';
import '../pages/settings_page.dart';
import '../widgets/ui_kit.dart';
import 'top_nav.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final active = controller.session;
    if (active != null) {
      return SessionPage(session: active);
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          Column(
            children: [
              const TopNav(),
              Expanded(
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: AppColors.bg,
                    gradient: AppGradients.pageGlow,
                  ),
                  child: IndexedStack(
                    index: controller.tab.index,
                    children: const [
                      AssistPage(),
                      DevicesPage(),
                      SettingsPage(),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (controller.hostSession != null)
            _HostSessionBanner(info: controller.hostSession!),
          if (controller.searchOpen) const SearchOverlay(),
          if (controller.notificationsOpen) ...[
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => controller.toggleNotifications(false),
              ),
            ),
            const NotificationsOverlay(),
          ],
        ],
      ),
    );
  }
}

class _HostSessionBanner extends StatelessWidget {
  const _HostSessionBanner({required this.info});

  final HostSessionInfo info;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.read(context);
    return Positioned(
      bottom: 24,
      right: 24,
      child: Container(
        width: 400,
        height: 52,
        padding: const EdgeInsets.fromLTRB(14, 0, 10, 0),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primaryBorder),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(AppIcons.remoteControl,
                  size: 17, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${info.controllerName} 正在远程控制本机',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.textPrimary),
              ),
            ),
            TextLink(
              label: '结束',
              color: AppColors.danger,
              fontSize: 12.5,
              onTap: controller.host.endSession,
            ),
          ],
        ),
      ),
    );
  }
}
