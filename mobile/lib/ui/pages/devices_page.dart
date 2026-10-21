import 'package:flutter/material.dart';

import '../../core/mobile_controller.dart';
import '../../core/mobile_scope.dart';
import '../../core/protocol.dart';
import '../theme.dart';
import '../widgets.dart';

class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = MobileScope.of(context);
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                const Text('设备', style: AppText.h2),
                const SizedBox(width: 8),
                Text('${controller.recents.length}', style: AppText.caption),
              ],
            ),
          ),
          Expanded(
            child: controller.recents.isEmpty
                ? _empty(context, controller)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      const Text('最近访问',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          )),
                      const SizedBox(height: 8),
                      for (final device in controller.recents)
                        _RecentCard(device: device, controller: controller),
                      const SizedBox(height: 8),
                      const Text(
                        '设备记录只保存在本机，不依赖云端账号。',
                        style: AppText.caption,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, MobileController controller) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              decoration: const BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.16),
                      ),
                    ),
                  ),
                  const Icon(Icons.devices_other,
                      size: 36, color: AppColors.primary),
                  Positioned(
                    right: 16,
                    top: 18,
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
            const SizedBox(height: 18),
            const Text('还没有访问过远程设备', style: AppText.bodyStrong),
            const SizedBox(height: 6),
            const Text(
              '在「远控」页输入对方识别码完成第一次连接，记录会出现在这里。',
              style: AppText.caption,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            TextButton(
              onPressed: () => controller.setTab(0),
              child: const Text('去远控'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.device, required this.controller});

  final RecentDevice device;
  final MobileController controller;

  @override
  Widget build(BuildContext context) {
    final isAndroid = device.platform == 'android';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D101828),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isAndroid ? Icons.phone_android : Icons.desktop_windows,
              color: AppColors.accent,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.bodyStrong),
                const SizedBox(height: 3),
                Text(
                  '${formatDeviceId(device.id)}  ·  ${relativeTime(device.lastConnected)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => controller.prefillTarget(device.id),
            child: const Text('远控'),
          ),
          IconButton(
            tooltip: '删除记录',
            onPressed: () async {
              final ok = await confirmDialog(
                context,
                title: '删除记录',
                message: '仅删除本机保存的访问记录，不影响对方设备。',
                confirmLabel: '删除',
                danger: true,
              );
              if (ok) controller.removeRecent(device.id);
            },
            icon: const Icon(Icons.delete_outline,
                size: 18, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}
