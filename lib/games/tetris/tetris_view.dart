import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/game_session.dart';
import 'tetris_engine.dart';
import 'tetris_versus_controller.dart';
import 'widgets/board_view.dart';
import 'widgets/combo_badge.dart';
import 'widgets/playfield.dart';
import 'widgets/side_panel.dart';

/// In-room Tetris versus widget. The opponent thumbnail is driven by network
/// snapshots; result/leave/rematch are handled centrally by [GameHostScreen],
/// so this widget intentionally has no header, pause, or result overlay.
class TetrisView extends StatefulWidget {
  final GameSession session;
  const TetrisView({super.key, required this.session});

  @override
  State<TetrisView> createState() => _TetrisViewState();
}

class _TetrisViewState extends State<TetrisView>
    with SingleTickerProviderStateMixin {
  final FocusNode _focusNode = FocusNode();
  late final TetrisVersusController _vs;
  late final AnimationController _flash;
  double _flashStrength = 0;

  @override
  void initState() {
    super.initState();
    _vs = TetrisVersusController(widget.session);
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _vs.player.onClearEffect = _onPlayerClear;
  }

  void _onPlayerClear(int lines) {
    _flashStrength = (lines * 0.12).clamp(0.10, 0.45);
    _flash.forward(from: 0);
  }

  @override
  void dispose() {
    _vs.dispose();
    _flash.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _vs.moveLeft();
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _vs.moveRight();
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _vs.softDrop();
    } else if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.keyX) {
      _vs.rotate();
    } else if (key == LogicalKeyboardKey.space) {
      _vs.hardDrop();
    } else if (key == LogicalKeyboardKey.keyC ||
        key == LogicalKeyboardKey.shiftLeft) {
      _vs.hold();
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: ListenableBuilder(
        listenable: _vs,
        builder: (context, _) => _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              _opponentArea(),
              const SizedBox(height: 10),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Playfield(
                        game: _vs.player,
                        onRotate: _vs.rotate,
                        onMoveLeft: _vs.moveLeft,
                        onMoveRight: _vs.moveRight,
                        onSoftDrop: _vs.softDrop,
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 116,
                      child: GameSidePanel(
                        game: _vs.player,
                        onHold: _vs.hold,
                        onHardDrop: _vs.hardDrop,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        _flashOverlay(),
        Positioned.fill(
          child: IgnorePointer(
            child: Align(
              alignment: const Alignment(0, 0.12),
              child: ComboBadge(game: _vs.player),
            ),
          ),
        ),
      ],
    );
  }

  Widget _opponentArea() {
    // Shrink the opponent thumbnail on short windows so the (taller) player
    // board keeps priority; stays full size on normal portrait screens.
    final height = (MediaQuery.sizeOf(context).height * 0.14).clamp(80.0, 118.0);
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: TetrisEngine.cols / TetrisEngine.rows,
            child: OpponentBoardView(board: _vs.opponentBoard),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    const Text(
                      '상대',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.circle,
                      size: 9,
                      color: _vs.opponentPresent
                          ? const Color(0xFF4ADE80)
                          : const Color(0xFFF87171),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'LINES  ${_vs.opponentLines}',
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                _garbageBar(
                  '내가 받을 줄',
                  _vs.player.pendingGarbage,
                  const Color(0xFFFACC15),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _garbageBar(String label, int count, Color color) {
    return Row(
      children: [
        SizedBox(
          width: 78,
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 2,
            children: List.generate(
              count.clamp(0, 12),
              (_) => Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _flashOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _flash,
          builder: (context, _) => ColoredBox(
            color: Colors.white
                .withValues(alpha: _flashStrength * (1 - _flash.value)),
          ),
        ),
      ),
    );
  }
}
