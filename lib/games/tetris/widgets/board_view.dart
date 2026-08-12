import 'package:flutter/material.dart';

import '../tetris_engine.dart';
import 'blocks.dart';

/// Renders the playfield: grid, locked blocks, ghost preview and active piece,
/// inside a glowing glass panel.
class BoardView extends StatelessWidget {
  final TetrisEngine game;
  const BoardView({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: TetrisEngine.cols / TetrisEngine.rows,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF273449), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withValues(alpha: 0.18),
              blurRadius: 24,
              spreadRadius: 1,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: CustomPaint(painter: _BoardPainter(game), size: Size.infinite),
        ),
      ),
    );
  }
}

/// Renders a static board grid from a raw `board[row][col]` colour matrix (the
/// active piece is already baked in). Used for the online opponent, whose state
/// arrives as decoded snapshots rather than a live [TetrisEngine].
class OpponentBoardView extends StatelessWidget {
  final List<List<Color?>> board;
  const OpponentBoardView({super.key, required this.board});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: TetrisEngine.cols / TetrisEngine.rows,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF273449), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withValues(alpha: 0.18),
              blurRadius: 24,
              spreadRadius: 1,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: CustomPaint(painter: _GridPainter(board), size: Size.infinite),
        ),
      ),
    );
  }
}

/// Shared backdrop (gradient, glow, grid lines) used by both painters.
void _paintBackdrop(Canvas canvas, Size size) {
  canvas.drawRect(
    Offset.zero & size,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF0C1120), Color(0xFF070A12)],
      ).createShader(Offset.zero & size),
  );
  canvas.drawRect(
    Rect.fromLTWH(0, 0, size.width, size.height * 0.4),
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF6366F1).withValues(alpha: 0.10),
          const Color(0xFF6366F1).withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.4)),
  );
  final grid = Paint()
    ..color = const Color(0x0DFFFFFF)
    ..strokeWidth = 1;
  final cw = size.width / TetrisEngine.cols;
  final ch = size.height / TetrisEngine.rows;
  for (var c = 1; c < TetrisEngine.cols; c++) {
    canvas.drawLine(Offset(c * cw, 0), Offset(c * cw, size.height), grid);
  }
  for (var r = 1; r < TetrisEngine.rows; r++) {
    canvas.drawLine(Offset(0, r * ch), Offset(size.width, r * ch), grid);
  }
}

class _GridPainter extends CustomPainter {
  final List<List<Color?>> board;
  _GridPainter(this.board);

  @override
  void paint(Canvas canvas, Size size) {
    _paintBackdrop(canvas, size);
    final cw = size.width / TetrisEngine.cols;
    final ch = size.height / TetrisEngine.rows;
    Rect cellRect(int col, int row) =>
        Rect.fromLTWH(col * cw + 1, row * ch + 1, cw - 2, ch - 2);
    for (var r = 0; r < TetrisEngine.rows && r < board.length; r++) {
      final rowCells = board[r];
      for (var c = 0; c < TetrisEngine.cols && c < rowCells.length; c++) {
        final color = rowCells[c];
        if (color != null) Blocks.paint(canvas, cellRect(c, r), color);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) =>
      !identical(oldDelegate.board, board);
}

class _BoardPainter extends CustomPainter {
  final TetrisEngine game;
  _BoardPainter(this.game) : super(repaint: game);

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width / TetrisEngine.cols;
    final ch = size.height / TetrisEngine.rows;

    // Background gradient.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0C1120), Color(0xFF070A12)],
        ).createShader(Offset.zero & size),
    );

    // Top glow.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.4),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF6366F1).withValues(alpha: 0.10),
            const Color(0xFF6366F1).withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height * 0.4)),
    );

    // Grid lines.
    final grid = Paint()
      ..color = const Color(0x0DFFFFFF)
      ..strokeWidth = 1;
    for (var c = 1; c < TetrisEngine.cols; c++) {
      canvas.drawLine(Offset(c * cw, 0), Offset(c * cw, size.height), grid);
    }
    for (var r = 1; r < TetrisEngine.rows; r++) {
      canvas.drawLine(Offset(0, r * ch), Offset(size.width, r * ch), grid);
    }

    Rect cellRect(int col, int row) =>
        Rect.fromLTWH(col * cw + 1, row * ch + 1, cw - 2, ch - 2);

    // Locked blocks.
    final board = game.board;
    for (var r = 0; r < TetrisEngine.rows; r++) {
      for (var c = 0; c < TetrisEngine.cols; c++) {
        final color = board[r][c];
        if (color != null) Blocks.paint(canvas, cellRect(c, r), color);
      }
    }

    // Ghost preview.
    final ghostColor = game.currentColor;
    if (ghostColor != null) {
      for (final cell in game.ghostCells()) {
        if (cell.row >= 0) {
          Blocks.paintGhost(canvas, cellRect(cell.col, cell.row), ghostColor);
        }
      }
    }

    // Active piece (with glow).
    final color = game.currentColor;
    if (color != null) {
      for (final cell in game.currentCells()) {
        if (cell.row >= 0) {
          Blocks.paint(canvas, cellRect(cell.col, cell.row), color, glow: true);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BoardPainter oldDelegate) => false;
}
