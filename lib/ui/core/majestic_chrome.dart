import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Clean, minimalist SeiReminds geometric app icon matching the Android launcher icon.
/// Uses a flat Academic Blue rounded square with crisp white schedule geometry and
/// a matching pure-vector CustomPainter fallback for headless/test environments.
class SeiRemindsEmblem extends StatelessWidget {
  const SeiRemindsEmblem({
    super.key,
    this.size = 38,
    this.showGlow = false,
  });

  final double size;
  final bool showGlow;

  static const String assetPath = 'assets/icon/seireminds_crest.png';

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.24);
    return ClipRRect(
      borderRadius: radius,
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => CustomPaint(
          size: Size.square(size),
          painter: const _MinimalCalendarLogoPainter(),
        ),
      ),
    );
  }
}

class _MinimalCalendarLogoPainter extends CustomPainter {
  const _MinimalCalendarLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = AppTheme.brandBlue,
    );

    final box = size.shortestSide * 0.60;
    final cardW = box * 0.90;
    final cardH = box * 0.80;
    final cardL = (w - cardW) / 2;
    final cardT = (h - cardH) / 2 + box * 0.06;
    final radius = Radius.circular(cardW * 0.19);
    final stroke = (cardW * 0.105).clamp(1.2, 8.0);

    final cardRect = Rect.fromLTWH(cardL, cardT, cardW, cardH);
    final cardRRect = RRect.fromRectAndRadius(cardRect, radius);

    canvas.save();
    canvas.clipRRect(cardRRect);
    final headerH = cardH * 0.28;
    canvas.drawRect(
      Rect.fromLTWH(cardL, cardT, cardW, headerH),
      Paint()..color = Colors.white,
    );
    canvas.restore();

    canvas.drawRRect(
      cardRRect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    final tabW = stroke * 1.1;
    final tabH = cardH * 0.24;
    final tabY = cardT - tabH * 0.56;
    for (final frac in const <double>[0.30, 0.70]) {
      final tx = cardL + cardW * frac - tabW / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(tx, tabY, tabW, tabH),
          Radius.circular(tabW / 2),
        ),
        Paint()..color = Colors.white,
      );
    }

    final innerL = cardL + cardW * 0.20;
    final innerR = cardL + cardW * 0.80;
    final innerW = innerR - innerL;
    final bodyTop = cardT + headerH;
    final bodyH = cardH - headerH;
    final barH = stroke * 0.9;

    final row1Y = bodyTop + bodyH * 0.34 - barH / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(innerL, row1Y, innerW, barH),
        Radius.circular(barH / 2),
      ),
      Paint()..color = Colors.white,
    );

    final dotD = barH * 1.28;
    final row2CenterY = bodyTop + bodyH * 0.67;
    final bar2W = innerW - dotD * 1.65;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(innerL, row2CenterY - barH / 2, bar2W, barH),
        Radius.circular(barH / 2),
      ),
      Paint()..color = const Color(0xFFBFDBFE),
    );
    canvas.drawCircle(
      Offset(innerR - dotD / 2, row2CenterY),
      dotD / 2,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Clean, neutral surface header/banner container replacing ornate gradients.
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
    final cs = Theme.of(context).colorScheme;
    final radius = borderRadius ?? BorderRadius.zero;

    return ClipRRect(
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: radius,
          border: borderRadius != null
              ? Border.all(color: cs.outlineVariant, width: 1)
              : Border(
                  bottom: BorderSide(color: cs.outlineVariant, width: 1),
                ),
        ),
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

/// Subtle hairline divider.
class GildedRule extends StatelessWidget {
  const GildedRule({super.key, this.verticalMargin = 14});

  final double verticalMargin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: verticalMargin),
      child: const Divider(height: 1),
    );
  }
}

/// Clean icon button for the app header toolbar.
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
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: icon,
          color: cs.onSurface,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}
