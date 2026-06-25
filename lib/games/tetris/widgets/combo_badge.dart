import 'package:flutter/material.dart';

import '../tetris_engine.dart';

/// Small overlay badge surfacing the player's current combo chain and
/// back-to-back state, so the attack bonuses are visible while playing.
class ComboBadge extends StatelessWidget {
  final TetrisEngine game;
  const ComboBadge({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    final combo = game.combo; // 0-based: 0 = first clear, 1 = second in a row...
    final showCombo = combo >= 1;
    final showB2b = game.backToBack;
    if (!showCombo && !showB2b) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showB2b) _chip('BACK·TO·BACK', const Color(0xFFFACC15)),
        if (showCombo) ...[
          if (showB2b) const SizedBox(height: 6),
          _chip('COMBO ×${combo + 1}', const Color(0xFF22D3EE)),
        ],
      ],
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF05070A).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.8), width: 1.5),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 14),
        ],
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}
