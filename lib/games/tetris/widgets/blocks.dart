import 'package:flutter/material.dart';

/// Shared glossy, beveled 3D block renderer used by the board and the previews.
class Blocks {
  static Color _lighten(Color c, double amount) =>
      Color.lerp(c, Colors.white, amount)!;
  static Color _darken(Color c, double amount) =>
      Color.lerp(c, Colors.black, amount)!;

  /// Paints a single glossy block filling [rect]. [glow] adds a soft colored
  /// halo (used for the active piece).
  static void paint(Canvas canvas, Rect rect, Color color, {bool glow = false}) {
    final body = RRect.fromRectAndRadius(rect, const Radius.circular(4));

    if (glow) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.inflate(1.5), const Radius.circular(6)),
        Paint()
          ..color = color.withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    // Gradient body: bright top-left -> base -> dark bottom-right.
    canvas.drawRRect(
      body,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_lighten(color, 0.36), color, _darken(color, 0.24)],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(rect),
    );

    // Glossy sheen in the upper half.
    final sheen = Rect.fromLTWH(
      rect.left + rect.width * 0.16,
      rect.top + rect.height * 0.14,
      rect.width * 0.68,
      rect.height * 0.34,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(sheen, const Radius.circular(2)),
      Paint()..color = Colors.white.withValues(alpha: 0.12),
    );

    // Top + left highlight edges.
    final hl = Paint()
      ..color = Colors.white.withValues(alpha: 0.40)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(rect.left + 2.5, rect.top + 2.5),
        Offset(rect.right - 2.5, rect.top + 2.5), hl);
    canvas.drawLine(Offset(rect.left + 2.5, rect.top + 2.5),
        Offset(rect.left + 2.5, rect.bottom - 2.5),
        hl..color = Colors.white.withValues(alpha: 0.26));

    // Subtle outline for definition.
    canvas.drawRRect(
      body,
      Paint()
        ..color = _darken(color, 0.4).withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  /// Paints the ghost (landing preview) of the active piece.
  static void paintGhost(Canvas canvas, Rect rect, Color color) {
    final r =
        RRect.fromRectAndRadius(rect.deflate(0.5), const Radius.circular(4));
    canvas.drawRRect(r, Paint()..color = color.withValues(alpha: 0.10));
    canvas.drawRRect(
      r,
      Paint()
        ..color = color.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }
}
