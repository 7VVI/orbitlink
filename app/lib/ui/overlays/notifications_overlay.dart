import 'package:flutter/material.dart';

import '../../core/app_controller.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../app_scope.dart';
import '../widgets/ui_kit.dart';

class NotificationsOverlay extends StatelessWidget {
  const NotificationsOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final unread = controller.unreadCount;
    return Positioned(
      right: 20,
      top: 80,
      width: 384,
      height: 452,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F101828),
              blurRadius: 36,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          children: [
            SizedBox(
              height: 58,
              child: Padding(
                padding: const EdgeInsets.only(left: 18, right: 10),
                child: Row(
                  children: [
                    const Text(
                      '消息中心',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (unread > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$unread 条未读',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    TextLink(
                      label: '全部已读',
                      fontSize: 12,
                      onTap: controller.markFeedRead,
                    ),
                    const SizedBox(width: 4),
                    AppIconButton(
                      icon: AppIcons.close,
                      size: 16,
                      color: AppColors.textTertiary,
                      onTap: () => controller.toggleNotifications(false),
                    ),
                  ],
                ),
              ),
            ),
            const Hairline(),
            Expanded(
              child: controller.feed.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(AppIcons.notification,
                              size: 26, color: AppColors.textTertiary),
                          SizedBox(height: 10),
                          Text('暂无消息', style: AppText.hint),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 8),
                      itemCount: controller.feed.length,
                      separatorBuilder: (_, __) => const Padding(
                        padding: EdgeInsets.only(left: 54, right: 10),
                        child: Hairline(),
                      ),
                      itemBuilder: (context, index) => _FeedRow(
                        item: controller.feed[index],
                      ),
                    ),
            ),
            const Hairline(),
            const SizedBox(
              height: 42,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(AppIcons.infoSquare,
                      size: 13, color: AppColors.textTertiary),
                  SizedBox(width: 6),
                  Text('仅显示本次运行期间产生的消息', style: AppText.tiny),
                ],
              ),
            ),
          ],
        ),
      ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 11, 10, 11),
      child: Row(
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
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Text(_relative(item.time), style: AppText.tiny),
                    if (!item.read) ...[
                      const SizedBox(width: 6),
                      const RedDot(size: 5),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  item.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.hint.copyWith(height: 1.55),
                ),
              ],
            ),
          ),
        ],
      ),
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
