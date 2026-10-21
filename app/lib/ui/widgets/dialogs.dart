import 'package:flutter/material.dart';

import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import 'ui_kit.dart';

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required String title,
  required Widget content,
  List<Widget> actions = const [],
  double width = 420,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierColor: const Color(0x40101828),
    barrierDismissible: barrierDismissible,
    builder: (context) => AppDialog(
      title: title,
      width: width,
      actions: actions,
      child: content,
    ),
  );
}

class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.width = 420,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26101828),
              blurRadius: 48,
              offset: Offset(0, 18),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: AppText.dialogTitle),
                ),
                AppIconButton(
                  icon: AppIcons.close,
                  size: 16,
                  color: AppColors.textTertiary,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DefaultTextStyle(
              style: AppText.bodySecondary.copyWith(height: 1.6),
              child: child,
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 10),
                    actions[i],
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmText = '确定',
  String cancelText = '取消',
  bool danger = false,
}) async {
  final result = await showAppDialog<bool>(
    context: context,
    title: title,
    content: Text(message),
    actions: [
      GhostButton(
        label: cancelText,
        width: 76,
        onPressed: () => Navigator.of(context).pop(false),
      ),
      PrimaryButton(
        label: confirmText,
        width: 100,
        height: 36,
        color: danger ? AppColors.danger : AppColors.primary,
        onPressed: () => Navigator.of(context).pop(true),
      ),
    ],
  );
  return result ?? false;
}

Future<void> showTextDialog(
  BuildContext context, {
  required String title,
  String hint = '请输入内容',
  String? initial,
  required ValueChanged<String> onConfirm,
}) async {
  final controller = TextEditingController(text: initial ?? '');
  await showAppDialog(
    context: context,
    title: title,
    content: AppTextField(
      controller: controller,
      hint: hint,
      autofocus: true,
      focused: true,
      height: 44,
    ),
    actions: [
      GhostButton(
        label: '取消',
        width: 76,
        onPressed: () => Navigator.of(context).pop(),
      ),
      PrimaryButton(
        label: '确定',
        width: 100,
        height: 36,
        onPressed: () {
          final text = controller.text.trim();
          Navigator.of(context).pop();
          if (text.isNotEmpty) onConfirm(text);
        },
      ),
    ],
  );
  controller.dispose();
}
