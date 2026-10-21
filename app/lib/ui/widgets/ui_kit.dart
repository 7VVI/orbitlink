import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../app_scope.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';

class HoverBuilder extends StatefulWidget {
  const HoverBuilder({
    super.key,
    required this.builder,
    this.cursor = SystemMouseCursors.click,
  });

  final Widget Function(bool hovered) builder;
  final MouseCursor cursor;

  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: widget.builder(_hovered),
    );
  }
}

class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    this.size = 18,
    this.color = AppColors.textSecondary,
    this.onTap,
    this.tooltip,
    this.padding = const EdgeInsets.all(6),
    this.hoverRadius = 4,
  });

  final IconData icon;
  final double size;
  final Color color;
  final VoidCallback? onTap;
  final String? tooltip;
  final EdgeInsets padding;
  final double hoverRadius;

  @override
  Widget build(BuildContext context) {
    final content = HoverBuilder(
      cursor:
          onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      builder: (hovered) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: hovered && onTap != null
                ? const Color(0x0D101828)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(hoverRadius),
          ),
          child: Icon(icon, size: size, color: color),
        ),
      ),
    );
    return tooltip == null
        ? content
        : Tooltip(message: tooltip!, child: content);
  }
}

class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.width = 41,
    this.height = 24,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final thumb = height - 6;
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: width,
        height: height,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: value ? AppColors.primary : const Color(0xFFD9DEE8),
          borderRadius: BorderRadius.circular(height / 2),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: thumb,
            height: thumb,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class AppCheckbox extends StatelessWidget {
  const AppCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 14,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: value ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(3),
          border: value ? null : Border.all(color: AppColors.inputBorder),
        ),
        child: value
            ? Icon(Icons.check, size: size - 2, color: Colors.white)
            : null,
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.width,
    this.height = 40,
    this.radius = 10,
    this.fontSize = 13.5,
    this.color = AppColors.primary,
    this.disabledColor = AppColors.disabled,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final double? width;
  final double height;
  final double radius;
  final double fontSize;
  final Color color;
  final Color disabledColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: enabled ? color : disabledColor,
        borderRadius: BorderRadius.circular(radius),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(radius),
          hoverColor: Colors.white.withOpacity(0.08),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: fontSize + 2, color: Colors.white),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    this.onPressed,
    this.width,
    this.height = 34,
    this.borderColor = AppColors.inputBorder,
    this.textColor = AppColors.textPrimary,
    this.fontSize = 13,
  });

  final String label;
  final VoidCallback? onPressed;
  final double? width;
  final double height;
  final Color borderColor;
  final Color textColor;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return HoverBuilder(
      cursor: onPressed == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      builder: (hovered) => GestureDetector(
        onTap: onPressed,
        child: Container(
          width: width,
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovered ? AppColors.surfaceMuted : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}

class TextLink extends StatelessWidget {
  const TextLink({
    super.key,
    required this.label,
    this.onTap,
    this.color = AppColors.blue,
    this.fontSize = 14,
    this.fontWeight = FontWeight.w400,
  });

  final String label;
  final VoidCallback? onTap;
  final Color color;
  final double fontSize;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: fontWeight,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    this.hint,
    this.prefixIcon,
    this.suffix,
    this.obscure = false,
    this.height = 44,
    this.width,
    this.focused = false,
    this.onChanged,
    this.onSubmitted,
    this.inputFormatters,
    this.autofocus = false,
    this.textAlign = TextAlign.start,
    this.style,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String? hint;
  final Widget? prefixIcon;
  final Widget? suffix;
  final bool obscure;
  final double height;
  final double? width;
  final bool focused;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final bool autofocus;
  final TextAlign textAlign;
  final TextStyle? style;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.field),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.10),
                  spreadRadius: 3,
                )
              ]
            : null,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadii.field),
          border: Border.all(
              color: focused ? AppColors.primary : AppColors.inputBorder),
        ),
        child: Row(
          children: [
            if (prefixIcon != null)
              Padding(
                padding: const EdgeInsets.only(left: 14, right: 8),
                child: prefixIcon,
              )
            else
              const SizedBox(width: 14),
            Expanded(
              child: TextField(
                controller: controller,
                obscureText: obscure,
                autofocus: autofocus,
                onChanged: onChanged,
                onSubmitted: onSubmitted,
                inputFormatters: inputFormatters,
                textAlign: textAlign,
                keyboardType: keyboardType,
                cursorColor: AppColors.blue,
                style: style ??
                    const TextStyle(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                      height: 1.4,
                    ),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: hint,
                  hintStyle: const TextStyle(
                    fontSize: 14,
                    color: AppColors.placeholder,
                    height: 1.4,
                  ),
                ),
              ),
            ),
            if (suffix != null)
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: suffix,
              )
            else
              const SizedBox(width: 14),
          ],
        ),
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(text, style: AppText.sectionTitle),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.label,
    this.subLabel,
    this.trailing,
    this.onTap,
    this.height,
  });

  final String label;
  final String? subLabel;
  final Widget? trailing;
  final VoidCallback? onTap;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final row = SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: AppText.body),
                if (subLabel != null) ...[
                  const SizedBox(height: 3),
                  Text(subLabel!, style: AppText.hint),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
    if (onTap == null) return row;
    return HoverBuilder(
      builder: (hovered) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: hovered ? AppColors.surfaceMuted : Colors.transparent,
          child: row,
        ),
      ),
    );
  }
}

class Hairline extends StatelessWidget {
  const Hairline({super.key, this.color = AppColors.divider, this.height = 1});

  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => Container(height: height, color: color);
}

class Caption extends StatelessWidget {
  const Caption(this.text, {super.key, this.color, this.size = 12});

  final String text;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style:
            TextStyle(fontSize: size, color: color ?? AppColors.textTertiary),
      );
}

class WindowButtons extends StatelessWidget {
  const WindowButtons({super.key, this.showNotification = true});

  final bool showNotification;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.read(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showNotification) ...[
          _TitleBarAction(
            icon: AppIcons.notification,
            tooltip: '消息',
            onTap: () => controller.toggleNotifications(),
          ),
          const SizedBox(width: 8),
        ],
        _TitleBarAction(
          icon: AppIcons.minimize,
          tooltip: '最小化',
          onTap: () => windowManager.minimize(),
        ),
        const SizedBox(width: 8),
        _TitleBarAction(
          icon: AppIcons.close,
          tooltip: '关闭',
          onTap: () => windowManager.close(),
        ),
      ],
    );
  }
}

class RedDot extends StatelessWidget {
  const RedDot({super.key, this.size = 6});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration:
            const BoxDecoration(color: AppColors.red, shape: BoxShape.circle),
      );
}

class GreenDot extends StatelessWidget {
  const GreenDot({super.key, this.size = 6});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
            color: AppColors.success, shape: BoxShape.circle),
      );
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(22),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: child,
    );
    if (onTap == null) return content;
    return GestureDetector(onTap: onTap, child: content);
  }
}

class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.pageTitle),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(subtitle!, style: AppText.bodySecondary),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 16),
          trailing!,
        ],
      ],
    );
  }
}

class _TitleBarAction extends StatelessWidget {
  const _TitleBarAction({
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
          width: 24,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovered ? const Color(0x14FFFFFF) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, size: 16, color: AppColors.railLabel),
        ),
      ),
    );
    return tooltip == null ? child : Tooltip(message: tooltip!, child: child);
  }
}

class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.width,
    this.height = 48,
    this.gradient = AppGradients.brand,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double? width;
  final double height;
  final Gradient gradient;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.button),
        child: Ink(
          decoration: BoxDecoration(
            gradient: enabled ? gradient : null,
            color: enabled ? null : AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(AppRadii.button),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.22),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(AppRadii.button),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon,
                        size: 18,
                        color: enabled ? Colors.white : AppColors.textTertiary),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: enabled ? Colors.white : AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
