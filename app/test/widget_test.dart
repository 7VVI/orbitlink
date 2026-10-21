import 'package:orbitlink/theme/app_icons.dart';
import 'package:orbitlink/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('OrbitLink design tokens and original icon set', () {
    expect(AppColors.bg, const Color(0xFFF5F7FB));
    expect(AppColors.primary, const Color(0xFF5A55F2));
    expect(AppColors.accent, const Color(0xFF0FB5A5));
    expect(AppIcons.remoteControl, Icons.screen_share_outlined);
  });
}
