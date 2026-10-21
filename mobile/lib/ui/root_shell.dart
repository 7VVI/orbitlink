import 'package:flutter/material.dart';

import '../core/mobile_controller.dart';
import '../core/mobile_scope.dart';
import 'pages/devices_page.dart';
import 'pages/home_page.dart';
import 'pages/session_page.dart';
import 'pages/settings_page.dart';
import 'theme.dart';
import 'widgets.dart';

class RootShell extends StatelessWidget {
  const RootShell({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = MobileScope.of(context);
    final activeSession = controller.session;
    if (activeSession != null) {
      return SessionPage(session: activeSession);
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          if (controller.status.sessionActive)
            _HostControlBanner(controller: controller),
          Expanded(
            child: IndexedStack(
              index: controller.tabIndex,
              children: const [
                HomePage(),
                DevicesPage(),
                SettingsPage(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: controller.tabIndex,
        onDestinationSelected: controller.setTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.screen_share_outlined),
            selectedIcon: Icon(Icons.screen_share),
            label: '远控',
          ),
          NavigationDestination(
            icon: Icon(Icons.devices_outlined),
            selectedIcon: Icon(Icons.devices),
            label: '设备',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}

class _HostControlBanner extends StatelessWidget {
  const _HostControlBanner({required this.controller});

  final MobileController controller;

  @override
  Widget build(BuildContext context) {
    final name = controller.status.controllerName ?? '远程用户';
    return SafeArea(
      bottom: false,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        decoration: BoxDecoration(
          color: AppColors.redSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.red.withOpacity(0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.screen_share, size: 18, color: AppColors.red),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$name 正在控制本机',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.red,
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                final ok = await confirmDialog(
                  context,
                  title: '停止被控',
                  message: '停止后将结束当前远程会话，确定继续？',
                  confirmLabel: '停止',
                  danger: true,
                );
                if (ok) await controller.stopHosting();
              },
              child: const Text('停止',
                  style: TextStyle(fontSize: 13, color: AppColors.red)),
            ),
          ],
        ),
      ),
    );
  }
}
