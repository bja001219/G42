import 'package:flutter/material.dart';

import '../tetris_engine.dart';
import 'board_view.dart';

/// A board wrapped with touch controls: tap = rotate, horizontal drag = move,
/// downward drag = soft drop. Movement is emitted one cell per [_step] pixels.
class Playfield extends StatefulWidget {
  final TetrisEngine game;
  final VoidCallback onRotate;
  final VoidCallback onMoveLeft;
  final VoidCallback onMoveRight;
  final VoidCallback onSoftDrop;

  const Playfield({
    super.key,
    required this.game,
    required this.onRotate,
    required this.onMoveLeft,
    required this.onMoveRight,
    required this.onSoftDrop,
  });

  @override
  State<Playfield> createState() => _PlayfieldState();
}

class _PlayfieldState extends State<Playfield> {
  double _dx = 0;
  double _dy = 0;
  static const double _step = 24;

  void _reset([_]) {
    _dx = 0;
    _dy = 0;
  }

  void _update(DragUpdateDetails d) {
    _dx += d.delta.dx;
    _dy += d.delta.dy;
    while (_dx >= _step) {
      widget.onMoveRight();
      _dx -= _step;
    }
    while (_dx <= -_step) {
      widget.onMoveLeft();
      _dx += _step;
    }
    while (_dy >= _step) {
      widget.onSoftDrop();
      _dy -= _step;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onRotate,
      onPanStart: _reset,
      onPanUpdate: _update,
      onPanEnd: _reset,
      child: Center(child: BoardView(game: widget.game)),
    );
  }
}
