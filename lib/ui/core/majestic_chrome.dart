import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Bespoke SeiReminds Celestial Astrolabe crest that matches the Android launcher icon.
/// Displays the generated high-res emblem asset framed in a burnished-gold bezel,
/// with a pure-geometry CustomPainter fallback for headless/test environments.
class SeiRemindsEmblem extends StatelessWidget {
  const SeiRemindsEmblem({
    super.key,
    this.size = 40,
    this.showGlow = false,
  });

  final double size;
  final bool showGlow;

  static const String assetPath = 'assets/icon/seireminds_crest.png';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.imperialSapphireDeep,
        border: Border.all(
          color: AppTheme.burnishedGold.withValues(alpha: 0.85),
          width: size >= 56 ? 2.0 : 1.3,
        ),
        boxShadow: showGlow
            ? const <BoxShadow>[
                BoxShadow(
                  color: Color(0x40E8BE65),
                  blurRadius: 18,
                  offset: Offset(0, 6),
                ),
              ]
            : const <BoxShadow>[
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 8,
                  offset: Offset(0, 3),
                ),
              ],
      ),
      child: ClipOval(
        child: Image.asset(
          assetPath,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => CustomPaint(
            size: Size.square(size),
            painter: const _AstrolabeEmblemPainter(),
          ),
        ),
      ),
    );
  }
}

class _AstrolabeEmblemPainter extends CustomPainter {
  const _AstrolabeEmblemPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2;

    final bgPaint = Paint()
      ..shader = const RadialGradient(
        colors: <Color>[Color(0xFF1D3366), Color(0xFF0A1124)],
      ).createShader(Rect.fromCircle(center: center, radius: r));
    canvas.drawCircle(center, r, bgPaint);

    final ringPaint = Paint()
      ..color = AppTheme.burnishedGold
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, size.shortestSide * 0.045);

    canvas.drawCircle(center, r * 0.72, ringPaint);
    canvas.drawCircle(
      center,
      r * 0.52,
      Paint()
        ..color = AppTheme.burnishedGold.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.8, size.shortestSide * 0.02),
    );

    // Four-point North Star / celestial chime spark at center.
    final star = Path();
    final outer = r * 0.42;
    final inner = r * 0.14;
    for (var i = 0; i < 8; i++) {
      final angle = -math.pi / 2 + (i * math.pi / 4);
      final rad = i.isEven ? outer : inner;
      final pt = Offset(
        center.dx + math.cos(angle) * rad,
        center.dy + math.sin(angle) * rad,
      );
      if (i == 0) {
        star.moveTo(pt.dx, pt.dy);
      } else {
        star.lineTo(pt.dx, pt.dy);
      }
    }
    star.close();
    canvas.drawPath(
      star,
      Paint()..color = const Color(0xFFF6DC96),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Deep sapphire-and-gold architectural header with geometric astrolabe meridian arcs.
class CelestialHorizonBanner extends StatelessWidget {
  const CelestialHorizonBanner({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 14),
    this.borderRadius,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final radius = borderRadius ?? BorderRadius.zero;

    return ClipRRect(
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppTheme.royalBannerGradient(brightness),
          border: borderRadius != null
              ? Border.all(
                  color: AppTheme.burnishedGold.withValues(alpha: 0.35),
                  width: 1,
                )
              : Border(
                  bottom: BorderSide(
                    color: AppTheme.burnishedGold.withValues(alpha: 0.42),
                    width: 1,
                  ),
                ),
        ),
        child: CustomPaint(
          painter: const _MeridianArcPainter(),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _MeridianArcPainter extends CustomPainter {
  const _MeridianArcPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final arcPaint = Paint()
      ..color = AppTheme.burnishedGold.withValues(alpha: 0.13)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final origin = Offset(size.width * 0.92, -size.height * 0.15);
    canvas.drawCircle(origin, size.height * 0.95, arcPaint);
    canvas.drawCircle(
      origin,
      size.height * 1.45,
      Paint()
        ..color = AppTheme.burnishedGold.withValues(alpha: 0.08)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Subtle cardinal glint dot on the outer orbital arc.
    final dotAngle = math.pi * 0.78;
    final dotCenter = Offset(
      origin.dx + math.cos(dotAngle) * size.height * 0.95,
      origin.dy + math.sin(dotAngle) * size.height * 0.95,
    );
    if (dotCenter.dx >= 0 &&
        dotCenter.dx <= size.width &&
        dotCenter.dy >= 0 &&
        dotCenter.dy <= size.height) {
      canvas.drawCircle(
        dotCenter,
        2.5,
        Paint()..color = AppTheme.burnishedGold.withValues(alpha: 0.38),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Hairline gilded editorial divider with a small geometric diamond star in the center.
class GildedRule extends StatelessWidget {
  const GildedRule({super.key, this.verticalMargin = 16});

  final double verticalMargin;

  @override
  Widget build(BuildContext context) {
    final lineColor = AppTheme.goldHairline(Theme.of(context).brightness);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: verticalMargin),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Container(
              height: 1,
              color: lineColor.withValues(alpha: 0.65),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Transform.rotate(
              angle: math.pi / 4,
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: AppTheme.goldAccent(Theme.of(context).brightness)
                      .withValues(alpha: 0.75),
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              color: lineColor.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }
}

/// Framed jewel icon button used inside CelestialHorizonBanner toolbars.
class RoyalHeaderIconButton extends StatelessWidget {
  const RoyalHeaderIconButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0x1FF5EFE0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.burnishedGold.withValues(alpha: 0.28),
          ),
        ),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: icon,
          color: const Color(0xFFF6E7BE),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}
