import 'package:flutter/material.dart';

/// A single board cell coordinate (row, col). Used both for piece-local
/// offsets and absolute board positions.
@immutable
class Cell {
  final int row;
  final int col;
  const Cell(this.row, this.col);

  Cell shift(int dRow, int dCol) => Cell(row + dRow, col + dCol);

  @override
  bool operator ==(Object other) =>
      other is Cell && other.row == row && other.col == col;

  @override
  int get hashCode => Object.hash(row, col);
}

/// The 7 standard tetromino types.
enum TetrominoType { i, o, t, s, z, j, l }

/// A tetromino definition: its four rotation states (clockwise) and color.
///
/// Each piece lives in an [boxSize] x [boxSize] bounding box. Rotation states
/// are pre-computed by rotating the spawn cells 90° clockwise three times so
/// the rotation behaviour is correct by construction.
class Tetromino {
  final TetrominoType type;
  final Color color;
  final int boxSize;

  /// rotations[state] = the cells occupied at that rotation (relative to the
  /// bounding box origin). state 0 is the spawn orientation.
  final List<List<Cell>> rotations;

  const Tetromino._(this.type, this.color, this.boxSize, this.rotations);

  /// Cells for the given rotation index (wraps around the 4 states).
  List<Cell> cells(int rotation) => rotations[rotation % 4];

  static final Map<TetrominoType, Tetromino> _registry = {
    TetrominoType.i: _build(
      TetrominoType.i,
      const Color(0xFF22D3EE), // cyan
      4,
      const [Cell(1, 0), Cell(1, 1), Cell(1, 2), Cell(1, 3)],
    ),
    TetrominoType.o: _build(
      TetrominoType.o,
      const Color(0xFFFACC15), // yellow
      2,
      const [Cell(0, 0), Cell(0, 1), Cell(1, 0), Cell(1, 1)],
    ),
    TetrominoType.t: _build(
      TetrominoType.t,
      const Color(0xFFA855F7), // purple
      3,
      const [Cell(0, 1), Cell(1, 0), Cell(1, 1), Cell(1, 2)],
    ),
    TetrominoType.s: _build(
      TetrominoType.s,
      const Color(0xFF4ADE80), // green
      3,
      const [Cell(0, 1), Cell(0, 2), Cell(1, 0), Cell(1, 1)],
    ),
    TetrominoType.z: _build(
      TetrominoType.z,
      const Color(0xFFF87171), // red
      3,
      const [Cell(0, 0), Cell(0, 1), Cell(1, 1), Cell(1, 2)],
    ),
    TetrominoType.j: _build(
      TetrominoType.j,
      const Color(0xFF60A5FA), // blue
      3,
      const [Cell(0, 0), Cell(1, 0), Cell(1, 1), Cell(1, 2)],
    ),
    TetrominoType.l: _build(
      TetrominoType.l,
      const Color(0xFFFB923C), // orange
      3,
      const [Cell(0, 2), Cell(1, 0), Cell(1, 1), Cell(1, 2)],
    ),
  };

  static Tetromino of(TetrominoType type) => _registry[type]!;

  /// Builds all 4 rotation states from the spawn cells by repeated 90° CW
  /// rotation inside an n x n box: (r, c) -> (c, n - 1 - r).
  static Tetromino _build(
    TetrominoType type,
    Color color,
    int n,
    List<Cell> spawn,
  ) {
    final states = <List<Cell>>[];
    var current = spawn;
    for (var i = 0; i < 4; i++) {
      states.add(current);
      current = current
          .map((cell) => Cell(cell.col, n - 1 - cell.row))
          .toList();
    }
    return Tetromino._(type, color, n, states);
  }
}
