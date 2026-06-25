import 'package:flutter/material.dart';

import 'tetris_engine.dart';
import 'tetromino.dart';

/// Compact board <-> string codec so the opponent's board can be mirrored
/// through `room.state`. Each of the rows*cols cells becomes one char: '0'
/// empty, '1'..'7' the seven piece colors, '8' garbage. The active piece is
/// baked in so the opponent sees the falling piece too.
///
/// Both peers run the same build, so the string length tracks
/// [TetrisEngine.rows] * [TetrisEngine.cols]; a shorter/blank string decodes as
/// an empty board.
class TetrisNet {
  static final List<Color> _pieceColors =
      TetrominoType.values.map((t) => Tetromino.of(t).color).toList();

  static final Map<int, int> _colorToIndex = {
    for (var i = 0; i < _pieceColors.length; i++)
      _pieceColors[i].toARGB32(): i + 1,
    TetrisEngine.garbageColor.toARGB32(): 8,
  };

  static String encodeBoard(TetrisEngine game) {
    final grid = [
      for (var r = 0; r < TetrisEngine.rows; r++)
        [for (var c = 0; c < TetrisEngine.cols; c++) game.board[r][c]],
    ];
    final color = game.currentColor;
    if (color != null) {
      for (final cell in game.currentCells()) {
        if (cell.row >= 0 &&
            cell.row < TetrisEngine.rows &&
            cell.col >= 0 &&
            cell.col < TetrisEngine.cols) {
          grid[cell.row][cell.col] = color;
        }
      }
    }
    final sb = StringBuffer();
    for (var r = 0; r < TetrisEngine.rows; r++) {
      for (var c = 0; c < TetrisEngine.cols; c++) {
        final cell = grid[r][c];
        sb.write(cell == null ? 0 : (_colorToIndex[cell.toARGB32()] ?? 8));
      }
    }
    return sb.toString();
  }

  static List<List<Color?>> decodeBoard(String? s) {
    final grid = List.generate(
      TetrisEngine.rows,
      (_) => List<Color?>.filled(TetrisEngine.cols, null),
    );
    if (s == null || s.length < TetrisEngine.rows * TetrisEngine.cols) {
      return grid;
    }
    var i = 0;
    for (var r = 0; r < TetrisEngine.rows; r++) {
      for (var c = 0; c < TetrisEngine.cols; c++) {
        final v = s.codeUnitAt(i++) - 48; // '0'..'8'
        if (v >= 1 && v <= 7) {
          grid[r][c] = _pieceColors[v - 1];
        } else if (v == 8) {
          grid[r][c] = TetrisEngine.garbageColor;
        }
      }
    }
    return grid;
  }

  static List<List<Color?>> emptyBoard() => List.generate(
        TetrisEngine.rows,
        (_) => List<Color?>.filled(TetrisEngine.cols, null),
      );
}
