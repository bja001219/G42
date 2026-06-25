import 'package:flutter/material.dart';

/// A large, tappable control button used for HOLD and HARD DROP.
class ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  /// Vertical compression for small phones (1.0 = full size). Drives padding,
  /// icon and label so HOLD/DROP shrink to fit rather than overflow off-screen.
  /// The caller (GameSidePanel) already clamps this to a legible floor.
  final double scale;

  const ControlButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.scale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.85),
                color.withValues(alpha: 0.55),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          padding: EdgeInsets.symmetric(vertical: 14 * s),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 30 * s),
              SizedBox(height: 4 * s),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12 * s,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
