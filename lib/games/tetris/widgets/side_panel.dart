import 'package:flutter/material.dart';

import '../tetris_engine.dart';
import 'control_button.dart';
import 'piece_preview.dart';

/// The right-hand panel: score/level/lines, NEXT and HOLD previews, and the two
/// control buttons (top = HOLD, bottom = HARD DROP).
class GameSidePanel extends StatelessWidget {
  final TetrisEngine game;
  final VoidCallback onHold;
  final VoidCallback onHardDrop;

  const GameSidePanel({
    super.key,
    required this.game,
    required this.onHold,
    required this.onHardDrop,
  });

  @override
  Widget build(BuildContext context) {
    // The panel lives in a height-constrained Row. On small phones (and once
    // safe-area insets are subtracted) that height shrinks, so the fixed
    // SCORE/HOLD/DROP chrome would otherwise overflow off the bottom. Derive a
    // single vertical scale from the available height and compress every fixed
    // metric proportionally — the board keeps its size, the panel always fits.
    return LayoutBuilder(
      builder: (context, c) {
        const refHeight = 440.0; // height at which everything is full-size.
        // Floor 0.72 keeps fonts legible (e.g. SCORE value 20*0.72≈14px, button
        // label 12*0.72≈8.6px). It still fits very short panels: at s=0.72 the
        // fixed chrome needs ~240px, well under the ~312px panel even the
        // smallest tested phone (320x568 + safe-area insets) provides — so the
        // floor never sacrifices the one-screen fit on real devices.
        final s = (c.maxHeight / refHeight).clamp(0.72, 1.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _statBox('SCORE', '${game.score}', s),
            SizedBox(height: 8 * s),
            Row(
              children: [
                Expanded(child: _statBox('LV', '${game.level}', s)),
                SizedBox(width: 8 * s),
                Expanded(child: _statBox('LINES', '${game.lines}', s)),
              ],
            ),
            // NEXT / HOLD sit side-by-side inside an Expanded that absorbs any
            // leftover height, so the panel fits one screen without scrolling.
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 6 * s),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: PiecePreview(label: 'NEXT', type: game.nextPiece),
                    ),
                    SizedBox(width: 8 * s),
                    Expanded(
                      child: PiecePreview(
                        label: 'HOLD',
                        type: game.hold,
                        dimmed: game.hold == null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ControlButton(
              icon: Icons.back_hand,
              label: 'HOLD',
              color: const Color(0xFF6366F1),
              onTap: onHold,
              scale: s,
            ),
            SizedBox(height: 10 * s),
            ControlButton(
              icon: Icons.keyboard_double_arrow_down,
              label: 'DROP',
              color: const Color(0xFFEF4444),
              onTap: onHardDrop,
              scale: s,
            ),
          ],
        );
      },
    );
  }

  static Widget _statBox(String label, String value, double s) {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 8 * s, horizontal: 10 * s),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0F17),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF1F2937)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: const Color(0xFF94A3B8),
              fontSize: 10 * s,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
          SizedBox(height: 2 * s),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20 * s,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
