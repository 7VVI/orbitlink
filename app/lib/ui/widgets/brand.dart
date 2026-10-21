import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppGradients.brand,
        borderRadius: BorderRadius.circular(size * 0.29),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.22),
            blurRadius: size * 0.45,
            offset: Offset(0, size * 0.12),
          ),
        ],
      ),
      child: CustomPaint(painter: _OrbitPainter()),
    );
  }
}

class BrandLockup extends StatelessWidget {
  const BrandLockup({
    super.key,
    this.markSize = 30,
    this.onDark = false,
    this.showTagline = true,
  });

  final double markSize;
  final bool onDark;
  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: markSize),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '星轨远控',
              style: TextStyle(
                fontSize: onDark ? 16 : 17,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                color: onDark ? Colors.white : AppColors.textPrimary,
                height: 1.2,
              ),
            ),
            if (showTagline)
              Text(
                'ORBITLINK',
                style: TextStyle(
                  fontSize: 8.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2.2,
                  color: onDark
                      ? Colors.white.withOpacity(0.45)
                      : AppColors.textTertiary,
                  height: 1.4,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _OrbitPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.055
      ..strokeCap = StrokeCap.round;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.55);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: size.width * 0.78,
        height: size.height * 0.38,
      ),
      paint,
    );
    final satellite = Offset(
      size.width * 0.39 * math.cos(-0.55),
      size.height * 0.19 * math.sin(-0.55),
    );
    canvas.drawCircle(
      satellite,
      size.width * 0.075,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      satellite,
      size.width * 0.047,
      Paint()..color = const Color(0xFF5DE0CC),
    );
    canvas.restore();

    canvas.drawCircle(
      center,
      size.width * 0.075,
      Paint()..color = Colors.white,
    );

    final spark = Paint()
      ..color = Colors.white.withOpacity(0.7)
      ..strokeWidth = size.width * 0.028
      ..strokeCap = StrokeCap.round;
    final sparkCenter = Offset(size.width * 0.78, size.height * 0.24);
    canvas.drawLine(
      sparkCenter.translate(-size.width * 0.05, 0),
      sparkCenter.translate(size.width * 0.05, 0),
      spark,
    );
    canvas.drawLine(
      sparkCenter.translate(0, -size.height * 0.08),
      sparkCenter.translate(0, size.height * 0.08),
      spark,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
