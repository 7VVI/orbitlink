import 'package:flutter/material.dart';

/// OrbitLink / 星轨远控 design tokens.
class AppColors {
  AppColors._();

  // Canvas & surfaces
  static const bg = Color(0xFFF5F7FB);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF8FAFC);
  static const surfaceElevated = Color(0xFFFCFCFE);
  static const border = Color(0xFFE7EAF0);
  static const divider = Color(0xFFE7EAF0);
  static const shadow = Color(0x14101828);

  // Ink
  static const textPrimary = Color(0xFF101828);
  static const textSecondary = Color(0xFF475467);
  static const textTertiary = Color(0xFF98A2B3);
  static const textMuted = Color(0xFF667085);
  static const placeholder = Color(0xFF98A2B3);
  static const disabled = Color(0xFFC4C9D4);

  // Brand
  static const primary = Color(0xFF5A55F2);
  static const primaryHover = Color(0xFF4842E0);
  static const primarySoft = Color(0xFFEEEDFE);
  static const primaryBorder = Color(0xFFC7C4FB);
  static const accent = Color(0xFF0FB5A5);
  static const accentSoft = Color(0xFFE6F8F5);
  static const accentBorder = Color(0xFF9BE3DA);

  // Semantic
  static const success = Color(0xFF12B76A);
  static const successSoft = Color(0xFFE8F8F0);
  static const warning = Color(0xFFF79009);
  static const warningSoft = Color(0xFFFFF6E8);
  static const danger = Color(0xFFF04438);
  static const dangerSoft = Color(0xFFFEF3F2);
  static const info = Color(0xFF2E90FA);
  static const infoSoft = Color(0xFFEAF4FF);

  // Legacy aliases kept for the remaining UI pieces.
  static const rail = Color(0xFFFFFFFF);
  static const railSelected = primarySoft;
  static const railDivider = Color(0xFFE7EAF0);
  static const subnavSelected = primarySoft;
  static const railLabel = Color(0xFF475467);
  static const red = danger;
  static const redSoft = dangerSoft;
  static const blue = primary;
  static const blueDisabled = primaryBorder;
  static const blueDisabledDark = primarySoft;
  static const inputBorder = Color(0xFFD9DEE8);
  static const dialog = Color(0xFFFFFFFF);
  static const dropdown = Color(0xFFFFFFFF);
  static const dropdownAlt = Color(0xFFF8FAFC);
  static const highlight = primarySoft;
  static const card = Color(0xFFFFFFFF);
  static const cardHover = Color(0xFFF8FAFC);
  static const searchStart = Color(0xFFF2F4F8);
  static const searchEnd = Color(0xFFF2F4F8);
  static const searchText = Color(0xFF667085);
  static const promoOrange = warning;
  static const promoBg = primarySoft;
  static const glass = Color(0xFFF8FAFC);

  // Session (remote desktop) canvas
  static const sessionBg = Color(0xFF0B0F19);
  static const sessionBar = Color(0xFF121826);
  static const sessionBarGlass = Color(0xE61A2130);
  static const sessionText = Color(0xFFF2F4F7);
  static const sessionMuted = Color(0xFF98A2B3);
  static const sessionBorder = Color(0xFF2A3346);
  static const sessionDanger = Color(0xFFFF6B6B);
}

class AppGradients {
  AppGradients._();

  static const brand = LinearGradient(
    colors: [Color(0xFF5A55F2), Color(0xFF8B7BFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const mint = LinearGradient(
    colors: [Color(0xFF0FB5A5), Color(0xFF54D6B7)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const pageGlow = RadialGradient(
    center: Alignment(-0.85, -1.1),
    radius: 1.15,
    colors: [Color(0x1A5A55F2), Color(0x00F5F7FB)],
  );
}

class AppRadii {
  AppRadii._();
  static const card = 20.0;
  static const panel = 16.0;
  static const field = 12.0;
  static const button = 12.0;
  static const chip = 999.0;
}

class AppShadows {
  AppShadows._();
  static const card = [
    BoxShadow(color: Color(0x0D101828), blurRadius: 24, offset: Offset(0, 8)),
  ];
  static const soft = [
    BoxShadow(color: Color(0x08101828), blurRadius: 12, offset: Offset(0, 4)),
  ];
}

class AppText {
  AppText._();

  static const display = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 1.2,
    letterSpacing: -0.4,
  );
  static const pageTitle = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 1.25,
    letterSpacing: -0.3,
  );
  static const dialogTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.3,
  );
  static const sectionTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.4,
  );
  static const body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.5,
  );
  static const bodyStrong = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.4,
  );
  static const bodySecondary = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.55,
  );
  static const label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: AppColors.textSecondary,
    height: 1.4,
  );
  static const hint = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textTertiary,
    height: 1.5,
  );
  static const tiny = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w400,
    color: AppColors.textTertiary,
    height: 1.4,
  );
  static const link = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: AppColors.primary,
    height: 1.4,
  );
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.bg,
    canvasColor: AppColors.bg,
    primaryColor: AppColors.primary,
    fontFamilyFallback: const [
      'Microsoft YaHei UI',
      'Microsoft YaHei',
      'Segoe UI',
    ],
    colorScheme: const ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.accent,
      onSecondary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
      outline: AppColors.border,
    ),
    splashFactory: InkRipple.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: const Color(0x08101828),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
      fontFamilyFallback: const ['Microsoft YaHei UI', 'Segoe UI'],
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      foregroundColor: AppColors.textPrimary,
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    ),
    cardTheme: CardTheme(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.button),
        ),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        minimumSize: const Size.fromHeight(44),
        side: const BorderSide(color: AppColors.primaryBorder),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.button),
        ),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: const TextStyle(fontSize: 14, color: AppColors.placeholder),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.field),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.field),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.field),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.primary;
        return const Color(0xFFD9DEE8);
      }),
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.divider,
      thickness: 1,
      space: 1,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.textPrimary,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(fontSize: 12, color: Colors.white),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(const Color(0x330F172A)),
      thickness: WidgetStateProperty.all(6),
      radius: const Radius.circular(3),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 16,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      textStyle: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
    ),
    dialogTheme: DialogTheme(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: const BorderSide(color: AppColors.border),
      ),
      titleTextStyle: AppText.dialogTitle,
      contentTextStyle: AppText.body.copyWith(color: AppColors.textSecondary),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.textPrimary,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}
