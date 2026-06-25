import 'package:flutter/material.dart';

import '../tetromino.dart';
import 'blocks.dart';

/// A small labelled box showing a single tetromino, used for NEXT and HOLD.
class PiecePreview extends StatelessWidget {
  final String label;
  final TetrominoType? type;
  final bool dimmed;

  const PiecePreview({
    super.key,
    required this.label,
    required this.type,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        AspectRatio(
          aspectRatio: 1.3,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0E1424), Color(0xFF0A0E18)],
              ),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF222C40)),
            ),
            padding: const EdgeInsets.all(7),
            child: CustomPaint(
              painter: _PiecePainter(type, dimmed),
              size: Size.infinite,
            ),
          ),
        ),
      ],
    );
  }
}

class _PiecePainter extends CustomPainter {
  final TetrominoType? type;
  final bool dimmed;
  _PiecePainter(this.type, this.dimmed);

  @override
  void paint(Canvas canvas, Size size) {
    final t = type;
    if (t == null) return;
    final piece = Tetromino.of(t);
    final cells = piece.cells(0);

    var minR = 99, maxR = -99, minC = 99, maxC = -99;
    for (final cell in cells) {
      minR = cell.row < minR ? cell.row : minR;
      maxR = cell.row > maxR ? cell.row : maxR;
      minC = cell.col < minC ? cell.col : minC;
      maxC = cell.col > maxC ? cell.col : maxC;
    }
    final wCells = (maxC - minC + 1).toDouble();
    final hCells = (maxR - minR + 1).toDouble();

    final cell = (size.width / wCells < size.height / hCells
            ? size.width / wCells
            : size.height / hCells) *
        0.92;
    final offX = (size.width - wCells * cell) / 2;
    final offY = (size.height - hCells * cell) / 2;

    final color = dimmed
        ? Color.lerp(piece.color, const Color(0xFF1F2937), 0.55)!
        : piece.color;

    for (final c in cells) {
      final x = offX + (c.col - minC) * cell;
      final y = offY + (c.row - minR) * cell;
      Blocks.paint(
        canvas,
        Rect.fromLTWH(x + 1, y + 1, cell - 2, cell - 2),
        color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PiecePainter oldDelegate) =>
      oldDelegate.type != type || oldDelegate.dimmed != dimmed;
}
